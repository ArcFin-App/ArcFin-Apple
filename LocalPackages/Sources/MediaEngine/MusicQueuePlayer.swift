// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import Foundation
import JellyfinAPI
import Observation
import Telemetry
import os

/// Plays a `MusicQueue`. AVQueuePlayer always holds the playing song and the one after it, so
/// one runs into the next with no gap.
@MainActor @Observable
public final class MusicQueuePlayer {
    public enum Event: Sendable {
        /// Started or resumed after `suspend()`, at a position in seconds.
        case started(MusicSong, at: Double)
        /// Finished, skipped or stopped, at a position in seconds.
        case ended(MusicSong, at: Double)
        /// Paused at the end of a song because `pausesAtEndOfSong` was set.
        case pausedAtEnd
    }

    public private(set) var queue = MusicQueue()
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0
    /// This player's own level, under the device's; a remote sets it.
    public var volume: Float = 1 { didSet { if fade == nil { player.volume = volume } } }
    public var isMuted = false {
        didSet {
            player.isMuted = isMuted
            fadingOut?.isMuted = isMuted
        }
    }
    /// Seconds each song fades into the next; 0 runs them together with no gap.
    public var crossfade: Double = 0
    /// Pause when the playing song ends, with the next one ready (a sleep timer's End of Song).
    public var pausesAtEndOfSong = false
    /// Goes up on every seek, for anything that shows the position without following it.
    public private(set) var seekCount = 0
    /// Copies each song's audio into `levels` as it plays, for a visualizer.
    public var isMetering = false { didSet { refreshTaps() } }
    /// Evens out loudness between songs with the server's per-song gain.
    public var soundCheck = false {
        didSet {
            levels.setSoundCheck(soundCheck)
            refreshTaps()
        }
    }
    public var equalizer = MusicEqualizer.off {
        didSet {
            levels.setEqualizer(equalizer)
            refreshTaps()
        }
    }
    @ObservationIgnored public let levels = MusicLevels()
    /// Each song is tapped while any of the above needs its audio; with none, nothing is.
    @ObservationIgnored private var isTapped = false

    @ObservationIgnored public var onEvent: ((Event) -> Void)?
    @ObservationIgnored private let streamURL: (MusicSong) -> URL?
    /// The player for the current song. A crossfade starts the next song on a new one.
    @ObservationIgnored private var player: AVQueuePlayer
    /// The player still fading out the last song, during a crossfade.
    @ObservationIgnored private var fadingOut: AVQueuePlayer?
    @ObservationIgnored private var fade: Task<Void, Never>?
    @ObservationIgnored private let log = Telemetry.logger(category: "MusicQueuePlayer")
    @ObservationIgnored private var entryIDs: [ObjectIdentifier: MusicQueue.Entry.ID] = [:]
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var started: MusicQueue.Entry?
    /// Songs that failed in a row; a whole queue of them stops instead of looping.
    @ObservationIgnored private var failures = 0

    public init(streamURL: @escaping (MusicSong) -> URL?) {
        self.streamURL = streamURL
        player = Self.makeDeck()
        follow(player)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: nil, queue: .main) { [weak self] note in
            let ended = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.itemEnded(ended) }
        }
    }

    private static func makeDeck() -> AVQueuePlayer {
        let deck = AVQueuePlayer()
        deck.actionAtItemEnd = .advance
        // Music goes to AirPlay as audio, so the receiver shows the song and its art; as
        // external (video) playback an Apple TV took over its screen with nothing on it.
        deck.allowsExternalPlayback = false
        return deck
    }

    /// Watches `deck` for whether it plays and where it is, and stops watching the last one.
    private func follow(_ deck: AVQueuePlayer) {
        statusObservation = deck.observe(\.timeControlStatus) { [weak self] deck, _ in
            let status = deck.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, deck === player else { return }
                isPlaying = status != .paused
                isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        }
        timeObserver = deck.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                    queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
    }

    public var current: MusicSong? { queue.current?.track }
    /// Between a song's started and ended events; suspended or stopped, it isn't.
    public var isInSession: Bool { started != nil }

    // MARK: Playing

    public func play(_ tracks: [MusicSong], startingAt index: Int = 0, shuffled: Bool = false) {
        finishCrossfade()
        endCurrent()
        let repeatMode = queue.repeatMode
        queue = MusicQueue(tracks, startingAt: index, shuffled: shuffled)
        queue.repeatMode = repeatMode
        reload()
        resume()
    }

    /// Lines up a queue paused at a position, as it was when the app last closed;
    /// `resume()` plays it. Nothing is reported until then.
    public func load(_ tracks: [MusicSong], startingAt index: Int, at seconds: Double,
                     repeatMode: MusicQueue.RepeatMode) {
        finishCrossfade()
        endCurrent()
        player.pause()
        queue = MusicQueue(tracks, startingAt: index)
        queue.repeatMode = repeatMode
        reload()
        if seconds > 0 { seek(to: seconds) }
    }

    public func resume() {
        guard let entry = queue.current else { return }
        Self.activateAudioSession()
        player.play()
        if started == nil { markStarted(entry) }
    }

    public func pause() {
        finishCrossfade()
        player.pause()
    }

    /// Pauses and ends the song's report, for something else taking over the audio.
    /// `resume()` starts it again.
    public func suspend() {
        finishCrossfade()
        player.pause()
        endCurrent()
    }

    public func togglePlayPause() { isPlaying ? pause() : resume() }

    public func seek(to seconds: Double) {
        finishCrossfade()
        position = seconds
        seekCount += 1
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func next() {
        finishCrossfade()
        endCurrent()
        if queue.advance() == nil {
            seek(to: 0)
            pause()
            return
        }
        reload()
    }

    public func previous() {
        finishCrossfade()
        let before = queue.current
        if queue.goBack(from: position)?.id == before?.id {
            seek(to: 0)
            return
        }
        endCurrent()
        reload()
    }

    /// `plays` false only moves the queue there, for a song playing somewhere else.
    public func jump(to id: MusicQueue.Entry.ID, plays: Bool = true) {
        finishCrossfade()
        endCurrent()
        guard queue.jump(to: id) != nil else { return }
        reload()
        if plays { resume() }
    }

    /// Stops and empties the queue.
    public func stop() {
        finishCrossfade()
        endCurrent()
        player.pause()
        forgetItems()
        queue = MusicQueue()
        position = 0
        duration = 0
        Self.deactivateAudioSession()
    }

    // MARK: Changing the queue

    public func playNext(_ tracks: [MusicSong]) {
        let wasEmpty = queue.isEmpty
        queue.playNext(tracks)
        wasEmpty ? startFresh() : refreshUpcoming()
    }

    public func addToQueue(_ tracks: [MusicSong]) {
        let wasEmpty = queue.isEmpty
        queue.addToQueue(tracks)
        wasEmpty ? startFresh() : refreshUpcoming()
    }

    public func remove(_ id: MusicQueue.Entry.ID) {
        finishCrossfade()
        let playing = queue.current?.id
        if id == playing { endCurrent() }
        queue.remove(id)
        if queue.isEmpty { return stop() }
        id == playing ? reload() : refreshUpcoming()
    }

    public func moveUpNext(from source: Int, to destination: Int) {
        queue.moveUpNext(from: source, to: destination)
        refreshUpcoming()
    }

    public func clearUpNext() {
        queue.clearUpNext()
        refreshUpcoming()
    }

    public func setShuffled(_ on: Bool) {
        queue.setShuffled(on)
        refreshUpcoming()
    }

    public var repeatMode: MusicQueue.RepeatMode {
        get { queue.repeatMode }
        set {
            queue.repeatMode = newValue
            refreshUpcoming()
        }
    }

    // MARK: AVQueuePlayer

    private func startFresh() {
        reload()
        resume()
    }

    /// The current song from its start, and the one after it. A playing player plays it
    /// straight away; a paused one waits for `resume()`.
    private func reload() {
        forgetItems()
        position = 0
        duration = queue.current?.track.duration ?? 0
        if let entry = queue.current, let item = makeItem(entry) {
            player.insert(item, after: nil)
            if player.rate != 0 { markStarted(entry) }
        }
        refreshUpcoming()
    }

    private func forgetItems() {
        player.removeAllItems()
        entryIDs.removeAll()
        itemObservations.removeAll()
    }

    /// Replaces whatever is lined up behind the playing song.
    private func refreshUpcoming() {
        for item in player.items().dropFirst() {
            entryIDs[ObjectIdentifier(item)] = nil
            itemObservations[ObjectIdentifier(item)] = nil
            player.remove(item)
        }
        var peek = queue
        guard let following = peek.advance(finished: true), let item = makeItem(following) else { return }
        player.insert(item, after: player.items().last)
    }

    private func makeItem(_ entry: MusicQueue.Entry) -> AVPlayerItem? {
        guard let url = streamURL(entry.track) else { return nil }
        let item = AVPlayerItem(url: url)
        entryIDs[ObjectIdentifier(item)] = entry.id
        let path = url.path
        // Which way it streams: the file as is (stream.flac, …) or converted (stream.mp3 with a codec).
        log.notice("Song stream: \(path, privacy: .public)\(url.query?.contains("static=true") == true ? "" : " (converted)", privacy: .public)")
        itemObservations[ObjectIdentifier(item)] = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let failed = ObjectIdentifier(item)
            Task { @MainActor [weak self] in self?.itemFailed(failed, path: path) }
        }
        if isTapped { tap(item, gain: entry.track.normalizationGain) }
        return item
    }

    private func refreshTaps() {
        let needed = isMetering || soundCheck || equalizer != .off
        guard needed != isTapped else { return }
        isTapped = needed
        for item in player.items() {
            let id = entryIDs[ObjectIdentifier(item)]
            tap(item, gain: queue.entries.first { $0.id == id }?.track.normalizationGain)
        }
    }

    /// The track only exists once a streamed file has started loading, so the tap goes on after.
    private func tap(_ item: AVPlayerItem, gain: Double?) {
        guard isTapped else {
            item.audioMix = nil
            return
        }
        Task { @MainActor [weak self] in
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
                  let self, isTapped, entryIDs[ObjectIdentifier(item)] != nil else { return }
            item.audioMix = levels.audioMix(for: track, gain: gain)
        }
    }

    private func itemEnded(_ item: ObjectIdentifier?) {
        guard let item, entryIDs[item] != nil else { return }
        entryIDs[item] = nil
        itemObservations[item] = nil
        endCurrent(at: duration)
        if pausesAtEndOfSong {
            pausesAtEndOfSong = false
            player.pause()
            if queue.advance(finished: true) == nil { queue.jump(to: queue.entries[0].id) }
            reload()
            onEvent?(.pausedAtEnd)
            return
        }
        guard queue.advance(finished: true) != nil else {
            // The end of the queue: back to the first song, paused.
            pause()
            queue.jump(to: queue.entries[0].id)
            reload()
            return
        }
        // AVQueuePlayer has moved on to the song lined up for this; anything else reloads.
        if let next = player.currentItem, entryIDs[ObjectIdentifier(next)] == queue.current?.id, let entry = queue.current {
            position = 0
            duration = entry.track.duration ?? 0
            markStarted(entry)
            refreshUpcoming()
        } else {
            reload()
            resume()
        }
    }

    private func itemFailed(_ item: ObjectIdentifier, path: String) {
        guard let failed = entryIDs[item] else { return }
        let error = player.items().first { ObjectIdentifier($0) == item }?.error as NSError?
        let reason = error.map { "\($0.domain) \($0.code): \($0.localizedDescription)" } ?? "unknown"
        log.error("Song failed (\(path, privacy: .public)): \(reason, privacy: .public)")
        if failed == queue.current?.id {
            failures += 1
            guard failures < queue.entries.count else {
                failures = 0
                endCurrent()
                player.pause()
                return
            }
            next()
            resume()
        } else {
            refreshUpcoming()
        }
    }

    private func tick(_ time: CMTime) {
        guard let item = player.currentItem, entryIDs[ObjectIdentifier(item)] == queue.current?.id else { return }
        if time.isNumeric { position = time.seconds }
        if position > 0 { failures = 0 }
        if item.duration.isNumeric, item.duration.seconds > 0 { duration = item.duration.seconds }
        if crossfade > 0, fade == nil, !pausesAtEndOfSong, isPlaying, queue.repeatMode != .one, duration > crossfade * 2 + 1,
           position >= duration - crossfade {
            startCrossfade()
        }
    }

    // MARK: Crossfade

    /// Starts the next song on a new player and fades the two across; the old one keeps
    /// only the song it's finishing.
    private func startCrossfade() {
        var peek = queue
        guard peek.advance(finished: true) != nil else { return }
        endCurrent(at: duration)
        let old = player
        old.actionAtItemEnd = .pause
        for item in old.items().dropFirst() { old.remove(item) }
        if let timeObserver { old.removeTimeObserver(timeObserver) }
        fadingOut = old
        player = Self.makeDeck()
        player.isMuted = isMuted
        player.volume = 0
        follow(player)
        queue.advance(finished: true)
        // Drops the old song's item from what's tracked, so its end doesn't move the queue.
        reload()
        resume()
        let seconds = crossfade
        fade = Task { @MainActor [weak self] in
            let steps = max(Int(seconds * 20), 1)
            for step in 1...steps {
                guard (try? await Task.sleep(for: .seconds(seconds / Double(steps)))) != nil, let self else { return }
                // Equal power, so the middle doesn't dip.
                let progress = Double(step) / Double(steps)
                player.volume = volume * Float(sin(progress * .pi / 2))
                old.volume = volume * Float(cos(progress * .pi / 2))
            }
            self?.finishCrossfade()
        }
    }

    /// Ends a crossfade now: the old song stops and the new one is at full volume.
    private func finishCrossfade() {
        fade?.cancel()
        fade = nil
        guard let old = fadingOut else { return }
        fadingOut = nil
        old.pause()
        old.removeAllItems()
        player.volume = volume
    }

    private func markStarted(_ entry: MusicQueue.Entry) {
        started = entry
        onEvent?(.started(entry.track, at: position))
    }

    private func endCurrent(at seconds: Double? = nil) {
        guard let entry = started else { return }
        started = nil
        onEvent?(.ended(entry.track, at: seconds ?? position))
    }

    // MARK: Audio session

    // setCategory and setActive block, so they run off the main actor.
    private static func activateAudioSession() {
        #if os(iOS) || os(tvOS)
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        #endif
    }

    private static func deactivateAudioSession() {
        #if os(iOS) || os(tvOS)
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }
}
