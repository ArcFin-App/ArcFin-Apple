// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
#if !os(tvOS)
import MediaPlayer
#if os(macOS)
import AppKit
#endif

/// Lock screen / Control Center / AirPods "Now Playing" surface — driven off whichever
/// engine (AVFoundation or VLC) is actually playing via MediaPlayerProtocol, not tied to
/// AVPlayer directly, since PlayerView abstracts over both. MediaPlayer itself (unlike
/// UIKit) is available on macOS too — Control Center and the keyboard media keys are its
/// macOS equivalent of iOS's lock screen/AirPods surface, driven by this same class.
@MainActor
final class NowPlayingManager {
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var isConfigured = false

    func configureCommands(
        isPlaying: @escaping () -> Bool,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onSkip: @escaping (Int) -> Void,
        onSeek: @escaping (TimeInterval) -> Void,
        onNextTrack: (() -> Void)?
    ) {
        guard !isConfigured else { return }
        isConfigured = true

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in onPlay(); return .success }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in onPause(); return .success }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            if isPlaying() { onPause() } else { onPlay() }
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.addTarget { event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            onSkip(Int(event.interval))
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.addTarget { event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            onSkip(-Int(event.interval))
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            onSeek(event.positionTime)
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = onNextTrack != nil
        commandCenter.nextTrackCommand.addTarget { _ in
            guard let onNextTrack else { return .commandFailed }
            onNextTrack()
            return .success
        }

        // Not meaningful for a single VOD item — disabled rather than left to silently no-op.
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
    }

    func update(title: String, artist: String?, duration: TimeInterval, elapsed: TimeInterval, rate: Float, artwork: PlatformImage?) {
        guard duration.isFinite, duration > 0 else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        [commandCenter.playCommand, commandCenter.pauseCommand, commandCenter.togglePlayPauseCommand,
         commandCenter.skipForwardCommand, commandCenter.skipBackwardCommand,
         commandCenter.changePlaybackPositionCommand, commandCenter.nextTrackCommand].forEach {
            $0.removeTarget(nil)
        }
        isConfigured = false
    }
}
#endif
