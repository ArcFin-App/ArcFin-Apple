// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
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
    @ObservationIgnored private let client = JellyfinMediaClient()
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var artwork: (id: String, image: MPMediaItemArtwork)?
    @ObservationIgnored private var hasCommands = false
    /// Reports go out one after another, so a song's Stopped always lands before the next Start.
    @ObservationIgnored private var lastReport: Task<Void, Never>?

    private static let deviceID = UserDefaults.standard.string(forKey: "arcfin.deviceId") ?? UUID().uuidString

    init(authManager: AuthManager) {
        self.authManager = authManager
        player = MusicQueuePlayer { [authManager] song in
            guard let credential = authManager.state.credential else { return nil }
            return JellyfinMediaClient().audioStreamURL(credential: credential, deviceId: Self.deviceID, trackId: song.id,
                                                      container: song.container)
        }
        player.onEvent = { [weak self] event in self?.handle(event) }
        followPlayer()
    }

    /// Whether there's anything to show a mini player for.
    var isActive: Bool { player.current != nil }

    /// A video is starting: the music pauses, its report ends, and the lock screen's controls
    /// go to the video until the music plays again.
    func yieldToVideo() {
        guard player.current != nil else { return }
        player.suspend()
        removeCommands()
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

    // MARK: Server reports

    private func handle(_ event: MusicQueuePlayer.Event) {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let client = client
        switch event {
        case .started(let song, let seconds):
            installCommands()
            report {
                await client.reportPlaybackStart(credential: credential, authHeader: header, itemId: song.id,
                                                 mediaSourceId: song.id, positionTicks: Int64(seconds * 10_000_000))
            }
            startProgressReports()
        case .ended(let song, let seconds):
            progressTask?.cancel()
            report {
                await client.reportPlaybackStopped(credential: credential, authHeader: header, itemId: song.id,
                                                   mediaSourceId: song.id, positionTicks: Int64(seconds * 10_000_000))
            }
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
                guard let self, !Task.isCancelled, let song = player.current,
                      let credential = authManager.state.credential else { return }
                let header = authManager.authClient.authHeader(token: credential.accessToken)
                let client = client, ticks = Int64(player.position * 10_000_000), isPaused = !player.isPlaying
                report {
                    await client.reportPlaybackProgress(credential: credential, authHeader: header, itemId: song.id,
                                                        mediaSourceId: song.id, positionTicks: ticks, isPaused: isPaused)
                }
            }
        }
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
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateNowPlaying()
                self?.followPlayer()
            }
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let song = player.current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artist = song.artistLine { info[MPMediaItemPropertyArtist] = artist }
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
        center.playbackState = player.isPlaying ? .playing : .paused
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
                center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand]
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
        let player = player
        center.playCommand.addTarget { _ in Task { @MainActor in player.resume() }; return .success }
        center.pauseCommand.addTarget { _ in Task { @MainActor in player.pause() }; return .success }
        center.togglePlayPauseCommand.addTarget { _ in Task { @MainActor in player.togglePlayPause() }; return .success }
        center.nextTrackCommand.addTarget { _ in Task { @MainActor in player.next() }; return .success }
        center.previousTrackCommand.addTarget { _ in Task { @MainActor in player.previous() }; return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime
            Task { @MainActor in player.seek(to: seconds) }
            return .success
        }
        Self.commands.forEach { $0.isEnabled = true }
        // A song is skipped, not jumped through ten seconds at a time.
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }
}
