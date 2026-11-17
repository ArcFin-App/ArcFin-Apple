// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import CastKit
import Foundation
import JellyfinAPI
import MediaEngine
import MediaPlayer
import Observation
import SwiftUI

/// The app's one music player: streams from the signed-in server, tells the server what's
/// playing so play counts and Recently Played work, and shows it on the lock screen and in
/// Control Center.
@MainActor @Observable
final class MusicPlayback {
    let player: MusicQueuePlayer

    @ObservationIgnored private let authManager: AuthManager
    @ObservationIgnored let scrobbler: MusicScrobbler
    @ObservationIgnored private let client = JellyfinMediaClient()
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var artwork: (id: String, image: MPMediaItemArtwork)?
    @ObservationIgnored private var hasCommands = false
    /// Paused for a video; remotes and the lock screen belong to the video until it plays again.
    @ObservationIgnored private var hasYielded = false
    @ObservationIgnored private var isSwitchingProfile = false
    /// Reports go out one after another, so a song's Stopped always lands before the next Start.
    @ObservationIgnored private var lastReport: Task<Void, Never>?

    /// Playing on a Chromecast: the receiver plays each song, this keeps the queue.
    private(set) var isCasting = false
    private(set) var castPosition: Double = 0
    @ObservationIgnored private var castSong: MusicSong?
    @ObservationIgnored private var castTick: Task<Void, Never>?
    @ObservationIgnored private var castFinishedCount = CastManager.shared.playbackFinishedCount
    /// A local start being handed to the receiver, so it isn't reported as played here.
    @ObservationIgnored private var isHandingToCast = false
    private var cast: CastManager { .shared }

    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    private static let deviceID = UserDefaults.standard.string(forKey: "arcfin.deviceId") ?? UUID().uuidString

    init(authManager: AuthManager) {
        self.authManager = authManager
        scrobbler = MusicScrobbler(authManager: authManager)
        player = MusicQueuePlayer { [authManager] song, start, convert in
            // A saved song plays from its file, unless the file won't play or seek.
            if !convert, let local = MusicDownloads.shared.localURL(for: song.id) { return local }
            guard let credential = authManager.state.credential else { return nil }
            return JellyfinMediaClient().audioStreamURL(credential: credential, deviceId: Self.deviceID, trackId: song.id,
                                                      container: song.container,
                                                      direct: convert ? [] : JellyfinMediaClient.directAudioContainers,
                                                      bitrateCap: MusicSettings.streamBitrate, startSeconds: start)
        }
        player.onEvent = { [weak self] event in self?.handle(event) }
        followPlayer()
        followProfile(authManager.state.credential?.userID)
        followCast()
        followVisualizerSetting()
        restoreQueue()
    }

    private func followVisualizerSetting() {
        applySettings()
        // A synced change from another device lands without the Settings screen open.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
    }

    private func applySettings() {
        let defaults = UserDefaults.standard
        // Any setting changing lands here; only a real change touches the player.
        let metering = defaults.object(forKey: MusicSettings.visualizerKey) as? Bool ?? true
        let soundCheck = defaults.bool(forKey: MusicSettings.soundCheckKey)
        let equalizer = defaults.string(forKey: MusicSettings.equalizerKey).flatMap(MusicEqualizer.init(rawValue:)) ?? .off
        if player.isMetering != metering { player.isMetering = metering }
        if player.soundCheck != soundCheck { player.soundCheck = soundCheck }
        if player.equalizer != equalizer { player.equalizer = equalizer }
        let crossfade = Double(defaults.integer(forKey: MusicSettings.crossfadeKey))
        if player.crossfade != crossfade { player.crossfade = crossfade }
        let autoplay = MusicSettings.isAutoplayOn
        if autoplay != wasAutoplayOn {
            wasAutoplayOn = autoplay
            if autoplay { topUpAutoplay() } else { autoplayTask?.cancel(); autoplayTask = nil }
        }
    }

    /// Signing out or switching profile stops the music: the queue was the last profile's.
    private func followProfile(_ userID: String?) {
        withObservationTracking {
            _ = authManager.state.credential?.userID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = authManager.state.credential?.userID
                if now != userID {
                    // The new profile's sign-in mustn't report the last one's song.
                    isSwitchingProfile = true
                    player.stop()
                    isSwitchingProfile = false
                    scrobbler.reset()
                    // Signing in, at launch too: that profile's last queue comes back.
                    if now != nil { restoreQueue() }
                }
                followProfile(now)
            }
        }
    }

    /// Whether there's anything to show a mini player for.
    var isActive: Bool { player.current != nil }

    /// A video is starting, here or (with Play On) on another device: the music pauses, its
    /// report ends, and the lock screen's controls go to the video until the music plays again.
    func yieldToVideo() {
        guard player.current != nil else { return }
        if isCasting { leaveCast() }
        player.suspend()
        removeCommands()
        hasYielded = true
        // The video's player fills Now Playing in; a paused state left here would hide it on the Mac.
        if PlatformMetrics.setsNowPlayingState { MPNowPlayingInfoCenter.default().playbackState = .unknown }
    }

    func artworkURL(for song: MusicSong, width: Int = 600) -> URL? {
        guard let credential = authManager.state.credential else { return nil }
        if let tag = song.primaryImageTag {
            return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: song.id, tag: tag,
                                                fillWidth: width, token: credential.accessToken)
        }
        guard let album = song.albumId, let tag = song.albumPrimaryImageTag else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: album, tag: tag,
                                            fillWidth: width, token: credential.accessToken)
    }

    // MARK: Transport, here or on a Chromecast

    var isPlaying: Bool { isCasting ? !cast.isPaused : player.isPlaying }
    var position: Double { isCasting ? castPosition : player.position }

    func togglePlayPause() { isCasting ? cast.togglePlayPause() : player.togglePlayPause() }
    func resume() { isCasting ? cast.play() : player.resume() }
    func pause() { isCasting ? cast.pause() : player.pause() }

    func seek(to seconds: Double) {
        guard isCasting else { return player.seek(to: seconds) }
        castPosition = seconds
        cast.seek(toSeconds: seconds)
        updateNowPlaying()
    }

    func next() {
        guard isCasting else { return player.next() }
        let before = player.queue.currentIndex
        endCastSong()
        player.next()
        if player.queue.currentIndex == before { cast.pause() } else { castCurrent(at: 0) }
    }

    func previous() {
        guard isCasting else { return player.previous() }
        if castPosition > MusicQueue.restartThreshold { return seek(to: 0) }
        endCastSong()
        player.seek(to: 0)
        player.previous()
        castCurrent(at: 0)
    }

    func jump(to id: MusicQueue.Entry.ID) {
        guard isCasting else { return player.jump(to: id) }
        endCastSong()
        player.jump(to: id, plays: false)
        castCurrent(at: 0)
    }

    func stop() {
        if isCasting {
            leaveCast()
            cast.pause()
        }
        player.stop()
    }

    /// A command from a remote (the web app, the watch, another device) while no video is
    /// open. Returns false for what music has no use for, like subtitles.
    func apply(_ command: RemoteControl.Kind) -> Bool {
        guard player.current != nil, !hasYielded else { return false }
        switch command {
        case .pause: pause()
        case .unpause: resume()
        case .playPause: togglePlayPause()
        case .stop: stop()
        case .seek(let ticks): seek(to: Double(ticks) / 10_000_000)
        case .rewind: seek(to: max(position - 10, 0))
        case .fastForward: seek(to: min(position + 10, player.duration))
        case .nextTrack: next()
        case .previousTrack: previous()
        case .setVolume(let level): player.volume = level
        case .volumeUp: player.volume = min(player.volume + 0.05, 1)
        case .volumeDown: player.volume = max(player.volume - 0.05, 0)
        case .mute: player.isMuted = true
        case .unmute: player.isMuted = false
        case .toggleMute: player.isMuted.toggle()
        case .audioTrack, .subtitleTrack, .message: return false
        }
        return true
    }

    /// The web app's Play On with songs: they play here, from the one asked for. False when
    /// they aren't all songs.
    func playFromRemote(_ ids: [String], startIndex: Int, startTicks: Int64?) async -> Bool {
        guard let songs = try? await MusicAPI.call({ try await $0.getSongs(credential: $1, authHeader: $2, ids: ids) }),
              !songs.isEmpty else { return false }
        if PlayerActivity.shared.isPlayerOpen {
            // The closing player clears the lock screen's controls, so the music waits for it.
            RemoteControl.shared.stopPlayer()
            for _ in 0..<20 where PlayerActivity.shared.isPlayerOpen {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        player.play(songs, startingAt: min(startIndex, songs.count - 1))
        if let startTicks, startTicks > 0 { player.seek(to: Double(startTicks) / 10_000_000) }
        return true
    }

    /// Play Next or Play Last from a remote.
    func queueFromRemote(_ ids: [String], next: Bool) async -> Bool {
        guard let songs = try? await MusicAPI.call({ try await $0.getSongs(credential: $1, authHeader: $2, ids: ids) }),
              !songs.isEmpty else { return false }
        next ? player.playNext(songs) : player.addToQueue(songs)
        return true
    }

    // MARK: Server reports

    private func handle(_ event: MusicQueuePlayer.Event) {
        if isSwitchingProfile { progressTask?.cancel() }
        guard !isSwitchingProfile, !isHandingToCast else { return }
        switch event {
        case .started(let song, let seconds):
            hasYielded = false
            installCommands()
            // Music started while connected to a Chromecast plays there.
            if isCasting || cast.isConnected {
                handToCast(at: seconds)
            } else {
                reportStart(song, at: seconds)
            }
            topUpAutoplay()
            MusicLyricsSource.shared.prefetch(song)
            refreshRating(of: song)
            saveQueue()
        case .ended(let song, let seconds):
            reportStop(song, at: seconds)
        case .pausedAtEnd:
            sleepTimer = nil
        case .queueEnded(let song):
            continueAfterQueue(song)
        }
    }

    private func reportStart(_ song: MusicSong, at seconds: Double) {
        scrobbler.started(song, at: seconds)
        scrobbler.flush()
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken), client = client
        report {
            await client.reportPlaybackStart(credential: credential, authHeader: header, itemId: song.id,
                                             mediaSourceId: song.id, positionTicks: Int64(seconds * 10_000_000))
        }
        startProgressReports()
    }

    private func reportStop(_ song: MusicSong, at seconds: Double) {
        progressTask?.cancel()
        scrobbler.heard(song, upTo: seconds)
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken), client = client
        report {
            await client.reportPlaybackStopped(credential: credential, authHeader: header, itemId: song.id,
                                               mediaSourceId: song.id, positionTicks: Int64(seconds * 10_000_000))
        }
    }

    private func report(_ send: @escaping @Sendable () async -> Void) {
        let previous = lastReport
        lastReport = Task {
            await previous?.value
            await send()
        }
    }

    private func startProgressReports() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                reportProgress()
            }
        }
    }

    /// Where the song is, whether it's paused, and the volume, so remotes show it.
    private func reportProgress() {
        saveQueue()
        guard let song = castSong ?? (player.isInSession ? player.current : nil),
              let credential = authManager.state.credential else { return }
        scrobbler.heard(song, upTo: position)
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let client = client, ticks = Int64(position * 10_000_000), isPaused = !isPlaying
        let volume = Int(((isCasting ? cast.volume : player.volume) * 100).rounded()), isMuted = player.isMuted
        report {
            await client.reportPlaybackProgress(credential: credential, authHeader: header, itemId: song.id,
                                                mediaSourceId: song.id, positionTicks: ticks, isPaused: isPaused,
                                                volumeLevel: volume, isMuted: isMuted)
        }
    }

    // MARK: Autoplay

    @ObservationIgnored private var autoplayTask: Task<Void, Never>?
    @ObservationIgnored private var wasAutoplayOn = MusicSettings.isAutoplayOn

    /// On the last song, a station from it goes behind it, so the music keeps going.
    private func topUpAutoplay() {
        guard MusicSettings.isAutoplayOn, player.repeatMode == .off, player.isInSession,
              let song = player.current, player.queue.upNext.isEmpty else { return }
        fetchAutoplay(after: song) { [weak self] songs in
            guard let self, player.current?.id == song.id, player.queue.upNext.isEmpty else { return }
            player.addToQueue(songs)
        }
    }

    /// The queue ran out before a station arrived: it carries on from the last song.
    private func continueAfterQueue(_ song: MusicSong) {
        guard MusicSettings.isAutoplayOn, player.repeatMode == .off else { return }
        let last = player.queue.entries.last?.id, endedAt = Date.now
        fetchAutoplay(after: song) { [weak self] songs in
            // Only if nothing has been played or changed since.
            guard let self, !player.isPlaying, player.queue.entries.last?.id == last,
                  player.queue.current?.id == player.queue.entries.first?.id else { return }
            let count = player.queue.entries.count
            player.addToQueue(songs)
            // Arriving long after the music stopped, they wait for Play instead of starting it.
            guard player.queue.entries.count > count else { return }
            player.jump(to: player.queue.entries[count].id, plays: Date.now.timeIntervalSince(endedAt) < 8)
        }
    }

    /// A newer request replaces one still loading; a server that can't be reached is tried again.
    private func fetchAutoplay(after song: MusicSong, then add: @escaping @MainActor ([MusicSong]) -> Void) {
        autoplayTask?.cancel()
        let queued = Set(player.queue.entries.map(\.track.id))
        autoplayTask = Task { [weak self] in
            for attempt in 0..<3 {
                if attempt > 0, (try? await Task.sleep(for: .seconds(10))) == nil { return }
                guard let songs = await Self.autoplaySongs(after: song, leavingOut: queued) else { continue }
                guard !Task.isCancelled, let self else { return }
                autoplayTask = nil
                if !songs.isEmpty { add(songs) }
                return
            }
        }
    }

    /// Songs to carry on with, the closest match first: this song's mix, its album's, its
    /// artist's, then songs by similar artists, then anything in the library. Nil when the
    /// server couldn't be reached.
    private static func autoplaySongs(after song: MusicSong, leavingOut queued: Set<String>) async -> [MusicSong]? {
        var sources: [@MainActor () async throws -> [MusicSong]] = [
            { try await MusicAPI.call { try await $0.getInstantMix(credential: $1, authHeader: $2, itemId: song.id, limit: 50) } },
        ]
        if let albumID = song.albumId {
            sources.append {
                try await MusicAPI.call { try await $0.getInstantMix(credential: $1, authHeader: $2, itemId: albumID, limit: 50) }
            }
        }
        if let artistID = song.artists.first?.id {
            sources.append {
                try await MusicAPI.call { try await $0.getInstantMix(credential: $1, authHeader: $2, itemId: artistID, limit: 50) }
            }
            sources.append {
                let similar = try await MusicAPI.call {
                    try await $0.getSimilarArtists(credential: $1, authHeader: $2, artistId: artistID)
                }
                guard !similar.isEmpty else { return [] }
                let filter = MusicFilter(artistId: similar.map(\.id).joined(separator: ","))
                return try await MusicAPI.call {
                    try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: .random,
                                                filter: filter, limit: 50)
                }.tracks
            }
        }
        let anything: @MainActor () async throws -> [MusicSong] = {
            try await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: .random, limit: 50)
            }.tracks
        }
        sources.append(anything)
        var reached = false
        for source in sources {
            guard !Task.isCancelled else { return [] }
            guard let songs = try? await source() else { continue }
            reached = true
            let fresh = songs.filter { !queued.contains($0.id) }
            if !fresh.isEmpty { return Array(fresh.prefix(25)) }
        }
        // Everything has been played already: it plays again, just not this song straight away.
        guard reached, let again = try? await anything() else { return reached ? [] : nil }
        return Array(again.filter { $0.id != song.id }.prefix(25))
    }

    // MARK: Remembering the queue

    /// Not on the main actor, so it can be encoded off it.
    nonisolated private struct SavedQueue: Codable, Sendable {
        var userID: String
        var songs: [MusicSong]
        var index: Int
        var position: Double
        var repeatMode: String
    }

    private static let savedQueueURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("MusicQueue.json")
    }()

    /// Written on each song and every progress report, off the main thread.
    private func saveQueue() {
        guard MusicSettings.remembersQueue, let userID = authManager.state.credential?.userID,
              let index = player.queue.currentIndex else { return }
        let saved = SavedQueue(userID: userID, songs: player.queue.entries.map(\.track), index: index,
                               position: position, repeatMode: player.repeatMode.rawValue)
        let url = Self.savedQueueURL
        // Encoding a long queue would hitch the main thread on every progress report.
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(saved) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The last queue for this profile, paused where it was.
    /// The profile's saved queue, when nothing's queued; also run by a widget's Play on a cold start.
    func restoreQueue() {
        guard MusicSettings.remembersQueue, player.queue.isEmpty, let userID = authManager.state.credential?.userID,
              let data = try? Data(contentsOf: Self.savedQueueURL),
              let saved = try? JSONDecoder().decode(SavedQueue.self, from: data),
              saved.userID == userID, !saved.songs.isEmpty else { return }
        player.load(saved.songs, startingAt: saved.index, at: saved.position,
                    repeatMode: MusicQueue.RepeatMode(rawValue: saved.repeatMode) ?? .off)
        // Play on the lock screen, CarPlay and remotes reaches it before anything has played.
        installCommands()
        updateNowPlaying()
    }

    // MARK: Sleep timer

    enum SleepTimer: Hashable {
        case minutes(Int)
        case endOfSong
    }

    private(set) var sleepTimer: SleepTimer?
    /// When a minutes timer stops the music.
    private(set) var sleepsAt: Date?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?

    func setSleepTimer(_ timer: SleepTimer?) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimer = timer
        sleepsAt = nil
        player.pausesAtEndOfSong = timer == .endOfSong
        if timer == .endOfSong {
            sleepTask = Task { [weak self] in await self?.fadeOutWithSong() }
            return
        }
        guard case .minutes(let minutes) = timer else { return }
        let seconds = Double(minutes * 60)
        sleepsAt = .now.addingTimeInterval(seconds)
        sleepTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(seconds - Self.sleepFade))) != nil else { return }
            await self?.fallAsleep()
        }
    }

    private static let sleepFade = 15.0

    /// Fades the last seconds out, then pauses and puts the volume back. The level falls on
    /// a curve, so the end sounds gradual rather than dropping away at the last moment.
    private func fallAsleep() async {
        let steps = 90
        for step in 1...steps {
            guard (try? await Task.sleep(for: .seconds(Self.sleepFade / Double(steps)))) != nil else {
                player.fadeLevel = 1
                return
            }
            player.fadeLevel = Self.fadeLevel(remaining: Double(steps - step) / Double(steps))
        }
        pause()
        autoplayTask?.cancel()
        autoplayTask = nil
        player.fadeLevel = 1
        sleepTimer = nil
        sleepsAt = nil
        sleepTask = nil
    }

    /// End of Song: the song's last seconds fade out, so it doesn't stop dead. Seeking back
    /// out of them brings the level back up.
    private func fadeOutWithSong() async {
        defer { player.fadeLevel = 1 }
        while sleepTimer == .endOfSong {
            guard (try? await Task.sleep(for: .milliseconds(150))) != nil else { return }
            let remaining = player.duration - player.position
            let level: Float = player.duration > Self.sleepFade * 2 && !isCasting && remaining < Self.sleepFade
                ? Self.fadeLevel(remaining: max(remaining / Self.sleepFade, 0)) : 1
            if abs(player.fadeLevel - level) > 0.005 { player.fadeLevel = level }
        }
    }

    /// Volume for a fade with this share of it left: sounds even to the ear, unlike a straight line.
    private static func fadeLevel(remaining: Double) -> Float { Float(remaining * remaining) }

    // MARK: Chromecast

    private func followCast() {
        withObservationTracking {
            _ = cast.isConnected
            _ = cast.isPaused
            _ = cast.playbackFinishedCount
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.castChanged()
                self?.followCast()
            }
        }
    }

    private func castChanged() {
        if cast.playbackFinishedCount != castFinishedCount {
            castFinishedCount = cast.playbackFinishedCount
            if isCasting { castSongFinished() }
        }
        if cast.isConnected, !isCasting, !hasYielded, player.isInSession {
            // Connected while music plays here: it moves over, from where it is.
            handToCast(at: player.position)
        } else if !cast.isConnected, isCasting {
            // The session ended: the music waits here, paused where the receiver left it.
            let at = cast.lastKnownPositionSeconds ?? castPosition
            leaveCast()
            player.seek(to: at)
        }
        updateNowPlaying()
        reportProgress()
    }

    /// Pauses the song here and plays it on the receiver from `seconds`.
    private func handToCast(at seconds: Double) {
        endCastSong()
        isCasting = true
        isHandingToCast = true
        player.suspend()
        isHandingToCast = false
        castCurrent(at: seconds)
        castTick?.cancel()
        castTick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, isCasting else { return }
                if let now = cast.currentPositionSeconds() { castPosition = now }
            }
        }
    }

    private func castCurrent(at seconds: Double) {
        guard let song = player.current, let credential = authManager.state.credential,
              let url = client.audioStreamURL(credential: credential, deviceId: Self.deviceID, trackId: song.id,
                                              container: song.container, direct: JellyfinMediaClient.castAudioContainers,
                                              bitrateCap: MusicSettings.streamBitrate)
        else { return }
        let type = switch url.pathExtension.lowercased() {
        case "flac": "audio/flac"
        case "wav": "audio/wav"
        default: "audio/mpeg"
        }
        cast.loadSong(itemID: song.id, streamURL: url, title: song.name, artist: song.artistLine, album: song.albumName,
                      artworkURL: artworkURL(for: song), contentType: type, startPositionSeconds: seconds)
        castSong = song
        castPosition = seconds
        reportStart(song, at: seconds)
        updateNowPlaying()
    }

    private func castSongFinished() {
        endCastSong(at: player.duration)
        if sleepTimer == .endOfSong {
            // The next song waits here, not cast.
            setSleepTimer(nil)
            player.next()
            return
        }
        if player.repeatMode == .one { return castCurrent(at: 0) }
        let before = player.queue.currentIndex
        player.next()
        if player.queue.currentIndex != before { castCurrent(at: 0) }
    }

    private func endCastSong(at seconds: Double? = nil) {
        guard let song = castSong else { return }
        castSong = nil
        reportStop(song, at: seconds ?? castPosition)
    }

    private func leaveCast() {
        endCastSong(at: cast.lastKnownPositionSeconds)
        isCasting = false
        castTick?.cancel()
    }

    // MARK: Lock screen and Control Center

    /// Redraws Now Playing whenever the song, a seek, the duration or the play state changes.
    private func followPlayer() {
        withObservationTracking {
            _ = player.current
            _ = player.isPlaying
            _ = player.duration
            _ = player.queue.currentIndex
            _ = player.seekCount
            _ = player.volume
            _ = player.isMuted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateNowPlaying()
                // A remote sees a pause, a seek or a volume change straight away.
                self?.reportProgress()
                self?.followPlayer()
            }
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard !hasYielded else { return }
        guard let song = player.current else {
            center.nowPlayingInfo = nil
            if PlatformMetrics.setsNowPlayingState { center.playbackState = .unknown }
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            // The car's instrument cluster and dashboard run their progress on at this rate.
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
        ]
        if let artist = song.artistLine { info[MPMediaItemPropertyArtist] = artist }
        if let albumArtist = song.albumArtist { info[MPMediaItemPropertyAlbumArtist] = albumArtist }
        if let album = song.albumName { info[MPMediaItemPropertyAlbumTitle] = album }
        if let index = player.queue.currentIndex {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = player.queue.entries.count
        }
        if let artwork, artwork.id == song.id {
            info[MPMediaItemPropertyArtwork] = artwork.image
        } else {
            loadArtwork(for: song)
        }
        center.nowPlayingInfo = info
        if PlatformMetrics.setsNowPlayingState { center.playbackState = isPlaying ? .playing : .paused }
        updateRatingCommands(for: song)
    }

    /// The system's Like, Dislike and Favorite show what this song has.
    private func updateRatingCommands(for song: MusicSong) {
        let commands = MPRemoteCommandCenter.shared()
        let likes = MusicRatings.shared.likes(song.id, server: song.likes)
        commands.likeCommand.isActive = likes == true
        commands.dislikeCommand.isActive = likes == false
        commands.bookmarkCommand.isActive = MusicFavorites.shared.isFavorite(song.id, server: song.isFavorite)
    }

    /// A rating changed in the app: the system's buttons follow.
    func ratingsChanged() {
        guard let song = castSong ?? player.current else { return }
        updateRatingCommands(for: song)
    }

    func rateCurrent(likes: Bool) {
        guard let song = castSong ?? player.current else { return }
        MusicRatings.shared.set(song.id, likes: likes, server: song.likes)
        updateRatingCommands(for: song)
    }

    func favoriteCurrent() {
        guard let song = castSong ?? player.current else { return }
        MusicFavorites.shared.toggle(song.id, server: song.isFavorite)
        updateRatingCommands(for: song)
    }

    /// What the server has now for the song that started: liked, disliked or a favorite may
    /// have changed elsewhere, or not have come with a queue saved before.
    private func refreshRating(of song: MusicSong) {
        Task {
            guard let fresh = try? await MusicAPI.call({ try await $0.getSongs(credential: $1, authHeader: $2, ids: [song.id]) })?.first
            else { return }
            MusicFavorites.shared.sync(fresh.id, isFavorite: fresh.isFavorite)
            MusicRatings.shared.sync(fresh.id, likes: fresh.likes)
            if player.current?.id == song.id || castSong?.id == song.id { updateRatingCommands(for: fresh) }
        }
    }

    private func loadArtwork(for song: MusicSong) {
        guard let url = artworkURL(for: song) else { return }
        Task {
            guard let data = await URLSession.arcfin.imageData(from: url),
                  let image = PlatformImage(data: data), player.current?.id == song.id else { return }
            artwork = (song.id, MPMediaItemArtwork(boundsSize: image.size) { _ in image })
            updateNowPlaying()
        }
    }

    /// Installed again each time a song starts: the video player clears every command when it
    /// closes.
    private static var commands: [MPRemoteCommand] {
        let center = MPRemoteCommandCenter.shared()
        return [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand,
                center.likeCommand, center.dislikeCommand, center.bookmarkCommand]
    }

    private func removeCommands() {
        guard hasCommands else { return }
        hasCommands = false
        Self.commands.forEach { $0.removeTarget(nil) }
    }

    private func installCommands() {
        removeCommands()
        hasCommands = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in Task { @MainActor in AppServices.music.resume() }; return .success }
        center.pauseCommand.addTarget { _ in Task { @MainActor in AppServices.music.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in AppServices.music.togglePlayPause() }; return .success }
        center.nextTrackCommand.addTarget { _ in Task { @MainActor in AppServices.music.next() }; return .success }
        center.previousTrackCommand.addTarget { _ in Task { @MainActor in AppServices.music.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor in AppServices.music.seek(to: seconds) }
            return .success
        }
        // Like, Dislike and Favorite, where the system shows them (CarPlay, the watch, the menu
        // on the lock screen and in Control Center).
        center.likeCommand.localizedTitle = String(localized: "Like")
        center.dislikeCommand.localizedTitle = String(localized: "Dislike")
        center.bookmarkCommand.localizedTitle = String(localized: "Favorite")
        center.likeCommand.addTarget { _ in Task { @MainActor in AppServices.music.rateCurrent(likes: true) }; return .success }
        center.dislikeCommand.addTarget { _ in Task { @MainActor in AppServices.music.rateCurrent(likes: false) }; return .success }
        center.bookmarkCommand.addTarget { _ in Task { @MainActor in AppServices.music.favoriteCurrent() }; return .success }
        Self.commands.forEach { $0.isEnabled = true }
        // A song is skipped, not jumped through ten seconds at a time.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }
}
