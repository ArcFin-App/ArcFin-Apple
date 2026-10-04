// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
import Observation
import SwiftVLC
import Telemetry

// MARK: - libVLC adapter (secondary engine — broader container/codec support than AVFoundation)

@MainActor
@Observable
public final class VLCEnginePlayer: MediaPlayerProtocol, @unchecked Sendable {

    private let log = Telemetry.logger(category: "VLCEnginePlayer")
    public let vlcPlayer = SwiftVLC.Player()

    public var status: PlaybackStatus {
        switch vlcPlayer.state {
        case .idle, .stopped, .stopping: .idle
        case .opening, .buffering: .loading
        case .playing: .playing
        case .paused: .paused
        case .error: .failed("VLC playback error")
        }
    }
    public var positionTicks: Int64 { Self.ticks(from: vlcPlayer.currentTime) }
    public var durationTicks: Int64 { vlcPlayer.duration.map(Self.ticks(from:)) ?? 0 }
    public var isBuffering: Bool { vlcPlayer.state == .opening || vlcPlayer.state == .buffering }
    public var availableAudioTracks: [AudioTrack] {
        vlcPlayer.audioTracks.map { AudioTrack(id: $0.id.hashValue, displayName: $0.name, language: $0.language) }
    }
    public var availableSubtitleTracks: [SubtitleTrack] {
        vlcPlayer.subtitleTracks.map { SubtitleTrack(id: $0.id.hashValue, displayName: $0.name, language: $0.language, isExternal: false) }
    }
    public var selectedAudioTrackIndex: Int { vlcPlayer.selectedAudioTrack?.id.hashValue ?? 0 }
    public var selectedSubtitleTrackIndex: Int? { vlcPlayer.selectedSubtitleTrack?.id.hashValue }
    public private(set) var playbackRate: Float = 1.0

    public var state: PlayerState {
        PlayerState(status: status, positionTicks: positionTicks, durationTicks: durationTicks,
                    isBuffering: isBuffering, availableAudioTracks: availableAudioTracks,
                    availableSubtitleTracks: availableSubtitleTracks,
                    selectedAudioTrackIndex: selectedAudioTrackIndex,
                    selectedSubtitleTrackIndex: selectedSubtitleTrackIndex)
    }

    public init() {}

    public func load(url: URL, startPositionTicks: Int64) async throws {
        do throws(VLCError) {
            try vlcPlayer.play(url: url)
        } catch {
            log.error("VLC play(url:) failed: \(error.localizedDescription)")
            throw error
        }
        log.info("Loading \(url.absoluteString)")

        // play(url:) starts playback immediately — wait for a real ready/error signal, then
        // normalize back to "loaded but paused" to match this protocol's load() contract
        // (AVFoundationPlayer ends load() paused too; a separate play() call is what starts it).
        try await waitUntilReady()
        vlcPlayer.pause()

        if startPositionTicks > 0 {
            // vlcPlayer.isSeekable can still be false right when playback first reaches
            // .playing/.paused for a fresh stream (libVLC determines seekability slightly
            // after playback starts, especially for a transcode) — seek(to:) throws
            // .invalidState in that window, and it was being swallowed by `try?` below,
            // silently dropping the resume position. Same race AVFoundationPlayer already
            // works around via waitUntilSeekable/SeekableRangeWait; ported here too.
            await waitUntilSeekable()
            await seek(to: startPositionTicks)
        }
    }

    private func waitUntilReady() async throws {
        if vlcPlayer.state == .playing || vlcPlayer.state == .paused { return }
        if vlcPlayer.state == .error { throw VLCError.playbackFailed(reason: "VLC reported a playback error") }
        for await event in vlcPlayer.events {
            guard case .stateChanged(let newState) = event else { continue }
            if newState == .playing || newState == .paused { return }
            if newState == .error { throw VLCError.playbackFailed(reason: "VLC reported a playback error") }
        }
    }

    private func waitUntilSeekable(timeoutSeconds: Double = 5) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !vlcPlayer.isSeekable, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    public func play() async {
        vlcPlayer.resume()
    }

    public func setRate(_ rate: Float) async {
        playbackRate = rate
        try? vlcPlayer.setPlaybackRate(PlaybackRate(rate))
    }

    public func pause() async {
        vlcPlayer.pause()
    }

    public func seek(to positionTicks: Int64) async {
        do throws(VLCError) {
            try vlcPlayer.seek(to: Self.duration(fromTicks: positionTicks))
        } catch {
            // Previously a bare `try?` — silently dropped the resume position whenever this
            // raced isSeekable (see waitUntilSeekable). Logging instead of swallowing so a
            // real failure here is diagnosable if it ever happens again.
            log.warning("VLC seek failed: \(error.localizedDescription)")
        }
    }

    public func setAudioTrack(index: Int) async {
        vlcPlayer.selectedAudioTrack = vlcPlayer.audioTracks.first { $0.id.hashValue == index }
    }

    public func setSubtitleTrack(index: Int?) async {
        guard let index else {
            vlcPlayer.selectedSubtitleTrack = nil
            return
        }
        vlcPlayer.selectedSubtitleTrack = vlcPlayer.subtitleTracks.first { $0.id.hashValue == index }
    }

    public func stop() async {
        vlcPlayer.stop()
    }

    // MARK: - Duration <-> ticks (Jellyfin convention: 10,000,000 ticks/sec)

    private static func ticks(from duration: Duration) -> Int64 {
        let c = duration.components
        return c.seconds * 10_000_000 + c.attoseconds / 100_000_000_000
    }

    private static func duration(fromTicks ticks: Int64) -> Duration {
        let seconds = ticks / 10_000_000
        let attoseconds = (ticks % 10_000_000) * 100_000_000_000
        return Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
    }
}

// MARK: - Engine selection

public enum PlaybackEngineKind: String, CaseIterable, Sendable {
    case auto = "Auto"
    case avFoundation = "AVFoundation"
    case vlc = "VLC"
}

public enum PlaybackEngineSelector {
    private static let log = Telemetry.logger(category: "PlaybackEngineSelector")

    /// A container AVFoundation can't open — picks VLC instead of AVFoundation for Auto.
    /// AVFoundation stays preferred otherwise, including HEVC (natively hardware-decoded on
    /// every iOS 26 device): less battery, native PiP/AirPlay/Now-Playing/HDR tone-mapping,
    /// the better fit for HLS transcode output, and — unlike VLC's PiPVideoView — its surface
    /// has a working implicit-animation fix for the player's tap-to-toggle-controls zoom glitch.
    public static func choose(
        preference: PlaybackEngineKind, container: String?, videoStream: JellyfinMediaStream?
    ) -> PlaybackEngineKind {
        switch preference {
        case .avFoundation, .vlc:
            return preference
        case .auto:
            // Jellyfin's Container field comes straight from ffprobe, which for the
            // ISO-base-media family reports a comma-joined alias list — "mov,mp4,m4a,
            // 3gp,3g2,mj2" for a plain .mp4, not a clean "mp4" token. An exact Set match
            // against that whole string always failed, silently routing a completely
            // AVFoundation-compatible file to VLC on Auto. Split on "," and check whether
            // any alias is actually compatible instead of matching the raw string.
            let aliases = (container ?? "").lowercased().split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let isCompatible = aliases.contains { JellyfinMediaClient.avFoundationCompatibleContainers.contains($0) }
            // Direct-played Dolby Vision has been reported to fail on AVPlayerLayer
            // (remoteXPCPlayer_clearVideoLayer / FigUseVideoReceiverForCALayer "Not
            // supported") — routed to VLC as a precaution. That same failure has ALSO now
            // been seen on a plain SDR HEVC/mp4 file, so Dolby Vision isn't the whole
            // picture — profile/bitDepth/level are logged below but not yet used to
            // decide, since which exact property breaks AVPlayerLayer isn't confirmed.
            let isDolbyVision = (videoStream?.videoRange ?? "").localizedCaseInsensitiveContains("dolby")
            let chosen: PlaybackEngineKind = (isCompatible && !isDolbyVision) ? .avFoundation : .vlc
            log.debug("""
                Auto chose \(chosen.rawValue, privacy: .public) — container: \(container ?? "nil", privacy: .public), \
                videoCodec: \(videoStream?.codec ?? "nil", privacy: .public), \
                videoRange: \(videoStream?.videoRange ?? "nil", privacy: .public), \
                profile: \(videoStream?.profile ?? "nil", privacy: .public), \
                bitDepth: \(videoStream?.bitDepth.map { "\($0)" } ?? "nil", privacy: .public), \
                level: \(videoStream?.level.map { "\($0)" } ?? "nil", privacy: .public), \
                resolution: \(videoStream?.width ?? 0)x\(videoStream?.height ?? 0)
                """)
            return chosen
        }
    }
}
