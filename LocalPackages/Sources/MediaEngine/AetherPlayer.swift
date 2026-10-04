// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AVFoundation
import Combine
import Observation
import Telemetry
import AetherEngine

// MARK: - AetherEngine adapter (primary — FFmpeg demux + VideoToolbox decode + a real AVPlayer
// leg for Dolby Vision display-criteria switching and Atmos passthrough; see
// PlaybackEngineSelector for when Auto picks this over AVFoundation/VLC, and PlayerView's setup()
// for the runtime fallback to one of those two if this engine itself fails to open a source)

@MainActor
@Observable
public final class AetherEnginePlayer: MediaPlayerProtocol, @unchecked Sendable {

    private let log = Telemetry.logger(category: "AetherEnginePlayer")
    // AetherEngine.AetherEngine, fully qualified — the module and its main class share the exact
    // same name, which Swift needs disambiguated here rather than left to infer.
    public let engine: AetherEngine.AetherEngine

    public var state: PlayerState {
        PlayerState(status: status, positionTicks: positionTicks, durationTicks: durationTicks,
                    isBuffering: isBuffering, availableAudioTracks: availableAudioTracks,
                    availableSubtitleTracks: availableSubtitleTracks,
                    selectedAudioTrackIndex: selectedAudioTrackIndex,
                    selectedSubtitleTrackIndex: selectedSubtitleTrackIndex)
    }

    public private(set) var status: PlaybackStatus = .idle
    public private(set) var positionTicks: Int64 = 0
    public private(set) var durationTicks: Int64 = 0
    public private(set) var isBuffering: Bool = false
    public private(set) var availableAudioTracks: [AudioTrack] = []
    public private(set) var availableSubtitleTracks: [SubtitleTrack] = []
    public private(set) var selectedAudioTrackIndex: Int = 0
    public private(set) var selectedSubtitleTrackIndex: Int? = nil
    public private(set) var playbackRate: Float = 1.0

    /// Native PGS/DVB bitmap + text cues the engine decodes itself — additive to the app's own
    /// Jellyfin-delivery-URL text-cue path (SubtitleLoader), which stays the renderer for every
    /// external subtitle on every engine. Only populated for an embedded track selected on this
    /// engine. `PlayerView+Controls.subtitleOverlay` renders a `.image` cue here as a bitmap
    /// overlay alongside the existing text overlay.
    public private(set) var subtitleCues: [SubtitleCue] = []

    /// Where the active session is actually rendering — drives which PiP mechanism applies
    /// (native `AVPictureInPictureController` on `.remoteBypass`/`.loopback`, the engine's own
    /// `softwarePiPSource` on `.software`).
    public private(set) var videoRoute: VideoRoute = .none

    @ObservationIgnored private var cancellables: [AnyCancellable] = []

    public init() throws {
        engine = try AetherEngine.AetherEngine()
        // Arcfin already owns audio-session activation generically (PlayerView.
        // activateAudioSession()) for both existing engines — let this one release the session
        // cleanly on a genuine final stop() instead of leaving it dangling.
        engine.deactivatesAudioSessionOnStop = true
        // Arcfin's own NowPlayingManager is already wired generically for both existing engines
        // via plain closures — do NOT also opt into the engine's own competing Now Playing
        // session (ownsVideoNowPlayingSession), which would fight it for the same MPNowPlayingInfo.
        bridgeObservation()
    }

    // MARK: - Bridging Combine @Published state into @Observable

    private func bridgeObservation() {
        engine.$playbackPhase.sink { [weak self] phase in
            self?.status = Self.status(for: phase)
        }.store(in: &cancellables)
        engine.$isBuffering.sink { [weak self] in self?.isBuffering = $0 }.store(in: &cancellables)
        engine.$duration.sink { [weak self] seconds in
            self?.durationTicks = Self.ticks(from: seconds)
        }.store(in: &cancellables)
        engine.clock.$currentTime.sink { [weak self] seconds in
            self?.positionTicks = Self.ticks(from: seconds)
        }.store(in: &cancellables)
        engine.$audioTracks.sink { [weak self] tracks in
            self?.availableAudioTracks = tracks.map {
                AudioTrack(id: $0.id, displayName: $0.name, language: $0.language)
            }
        }.store(in: &cancellables)
        engine.$subtitleTracks.sink { [weak self] tracks in
            self?.availableSubtitleTracks = tracks.map {
                SubtitleTrack(id: $0.id, displayName: $0.name, language: $0.language, isExternal: $0.isExternal)
            }
        }.store(in: &cancellables)
        engine.$activeAudioTrackIndex.sink { [weak self] index in
            self?.selectedAudioTrackIndex = index ?? 0
        }.store(in: &cancellables)
        engine.$subtitleCues.sink { [weak self] in self?.subtitleCues = $0 }.store(in: &cancellables)
        engine.$videoRoute.sink { [weak self] in self?.videoRoute = $0 }.store(in: &cancellables)
    }

    private static func status(for phase: PlaybackPhase) -> PlaybackStatus {
        switch phase {
        case .idle: return .idle
        case .loading, .seeking, .rebuffering, .stalled: return .loading
        case .playing: return .playing
        case .paused: return .paused
        case .ended: return .ended
        case .error(let message): return .failed(message)
        }
    }

    // Jellyfin's own tick convention (10,000,000 ticks/sec) — same constant VLCEnginePlayer's
    // ticks(from:)/duration(fromTicks:) use, just against plain Double seconds instead of
    // Duration, since that's what AetherEngine's own API takes/publishes throughout.
    private static func ticks(from seconds: Double) -> Int64 {
        Int64((seconds * 10_000_000).rounded())
    }

    private static func seconds(fromTicks ticks: Int64) -> Double {
        Double(ticks) / 10_000_000
    }

    // MARK: - MediaPlayerProtocol

    public func load(url: URL, startPositionTicks: Int64) async throws {
        let startPosition = startPositionTicks > 0 ? Self.seconds(fromTicks: startPositionTicks) : nil
        // LoadOptions.matchContentEnabled defaults to true in the engine's own API — read
        // Arcfin's existing matchContentFrameRate toggle directly (same plain-UserDefaults
        // pattern CodecProfileSettingsView's keys already use to reach cross-cutting playback
        // settings) rather than silently overriding it; the toggle defaults off specifically
        // because of display judder/a black flash on some TVs when the refresh rate switches.
        var options = LoadOptions()
        options.matchContentEnabled = UserDefaults.standard.bool(forKey: "matchContentFrameRate")
        try await engine.load(url: url, startPosition: startPosition, options: options)
    }

    public func play() async { engine.play() }
    public func pause() async { engine.pause() }
    public func seek(to positionTicks: Int64) async {
        await engine.seek(to: Self.seconds(fromTicks: positionTicks))
    }
    public func setRate(_ rate: Float) async {
        playbackRate = rate
        engine.setRate(rate)
    }
    public func stop() async { engine.stop() }

    public func setAudioTrack(index: Int) async {
        engine.selectAudioTrack(index: index)
    }

    public func setSubtitleTrack(index: Int?) async {
        selectedSubtitleTrackIndex = index
        if let index {
            engine.selectSubtitleTrack(index: index)
        } else {
            engine.clearSubtitle()
        }
    }
}
