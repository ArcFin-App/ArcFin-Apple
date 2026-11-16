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
    }

    public private(set) var queue = MusicQueue()
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var position: Double = 0
    public private(set) var duration: Double = 0
    /// Goes up on every seek, for anything that shows the position without following it.
    public private(set) var seekCount = 0

    @ObservationIgnored public var onEvent: ((Event) -> Void)?
    @ObservationIgnored private let streamURL: (MusicSong) -> URL?
    @ObservationIgnored private let player = AVQueuePlayer()
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
        player.actionAtItemEnd = .advance
        statusObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                self?.isPlaying = status != .paused
                self?.isBuffering = status == .waitingToPlayAtSpecifiedRate
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: nil, queue: .main) { [weak self] note in
            let ended = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.itemEnded(ended) }
        }
    }

    public var current: MusicSong? { queue.current?.track }

    // MARK: Playing

    public func play(_ tracks: [MusicSong], startingAt index: Int = 0, shuffled: Bool = false) {
        endCurrent()
        let repeatMode = queue.repeatMode
        queue = MusicQueue(tracks, startingAt: index, shuffled: shuffled)
        queue.repeatMode = repeatMode
        reload()
        resume()
    }

    public func resume() {
        guard let entry = queue.current else { return }
        Self.activateAudioSession()
        player.play()
        if started == nil { markStarted(entry) }
    }

    public func pause() { player.pause() }

    /// Pauses and ends the song's report, for something else taking over the audio.
    /// `resume()` starts it again.
    public func suspend() {
        player.pause()
        endCurrent()
    }

    public func togglePlayPause() { isPlaying ? pause() : resume() }

    public func seek(to seconds: Double) {
        position = seconds
        seekCount += 1
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func next() {
        endCurrent()
        if queue.advance() == nil {
            seek(to: 0)
            pause()
            return
        }
        reload()
    }

    public func previous() {
        let before = queue.current
        if queue.goBack(from: position)?.id == before?.id {
            seek(to: 0)
            return
        }
        endCurrent()
        reload()
    }

    public func jump(to id: MusicQueue.Entry.ID) {
        endCurrent()
        guard queue.jump(to: id) != nil else { return }
        reload()
        resume()
    }

    /// Stops and empties the queue.
    public func stop() {
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
        itemObservations[ObjectIdentifier(item)] = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let failed = ObjectIdentifier(item)
            let reason = (item.error as NSError?).map { "\($0.domain) \($0.code): \($0.localizedDescription)" } ?? "unknown"
            let path = (item.asset as? AVURLAsset)?.url.path ?? "?"
            Task { @MainActor [weak self] in
                self?.log.error("Song failed (\(path, privacy: .public)): \(reason, privacy: .public)")
            }
            Task { @MainActor [weak self] in self?.itemFailed(failed) }
        }
        return item
    }

    private func itemEnded(_ item: ObjectIdentifier?) {
        guard let item, entryIDs[item] != nil else { return }
        entryIDs[item] = nil
        itemObservations[item] = nil
        endCurrent(at: duration)
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

    private func itemFailed(_ item: ObjectIdentifier) {
        guard let failed = entryIDs[item] else { return }
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
