// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SwiftUI
import AVFoundation
import Combine
import Observation
import Telemetry
import AetherEngine

// MARK: - AetherEngine adapter (primary — FFmpeg demux + VideoToolbox decode + a real AVPlayer
// leg for Dolby Vision display-criteria switching and Atmos passthrough; see
// PlaybackEngineSelector for when Auto picks this over AVFoundation/VLC, and PlayerView's setup()
// for the runtime fallback to one of those two if this engine itself fails to open a source)

/// A decoded PGS/DVB bitmap subtitle cue, bridged out of AetherEngine.SubtitleCue/SubtitleImage
/// into a type the app target can use without importing AetherEngine's own subtitle types
/// (see the name-collision note on AetherEnginePlayer.nativeBitmapCues below).
public struct NativeBitmapCue: Identifiable, Sendable {
    public let id: Int
    public let startTime: Double
    public let endTime: Double
    public let cgImage: CGImage
    /// Normalized [0, 1] position against `canvasSize` — multiply by the on-screen video
    /// rect to place it (same contract as AetherEngine.SubtitleImage.position).
    public let position: CGRect
    public let canvasSize: CGSize
}

@MainActor
@Observable
public final class AetherEnginePlayer: MediaPlayerProtocol, @unchecked Sendable {

    private let log = Telemetry.logger(category: "AetherEnginePlayer")
    // The module and its main class share the exact same name ("AetherEngine") — unqualified
    // use here resolves to the class, not the module, so no further qualification is needed
    // (AetherEngine.AetherEngine was tried first and fails: Swift resolves the first
    // "AetherEngine" to the class type, then looks for a nested type of that name on it).
    public let engine: AetherEngine

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

    /// Native PGS/DVB bitmap cues the engine decodes itself — additive to the app's own
    /// Jellyfin-delivery-URL text-cue path (SubtitleLoader.SubtitleCue), which stays the
    /// renderer for every external subtitle on every engine. Only populated for an embedded
    /// bitmap track selected on this engine; text/rich-text cues already have a home via the
    /// existing path and aren't duplicated here.
    ///
    /// Deliberately a local, minimal type rather than exposing AetherEngine.SubtitleCue
    /// directly — Arcfin already has its own `SubtitleCue` (SubtitleLoader.swift, same app
    /// module as PlayerView.swift); the app target never needs to import AetherEngine's own
    /// subtitle types at all this way, so there's no name collision to manage at every call site.
    public private(set) var nativeBitmapCues: [NativeBitmapCue] = []

    @ObservationIgnored private var cancellables: [AnyCancellable] = []

    /// Playback volume — passthrough so a caller (PlayerView+Gestures' macOS volume
    /// handling) never needs `import AetherEngine` itself just to reach `engine.volume`.
    public var volume: Float {
        get { engine.volume }
        set { engine.volume = newValue }
    }

    /// Non-nil only on the `.remoteBypass`/`.loopback` routes (both still ultimately
    /// AVPlayer/AVPlayerLayer under the hood) — nil on `.software`, where PiP would need a
    /// materially different sample-buffer-based coordinator this wrapper doesn't implement
    /// yet. Same passthrough rationale as `volume` above.
    public var nativePlayerLayer: AVPlayerLayer? { engine.nativePlayerLayer }

    /// Passthrough so PlayerView's fill-screen toggle can reach this engine's own
    /// videoGravity — applies on every route (it re-applies to whichever of nativeHost's
    /// playerLayer / softwareHost's displayLayer is actually live), unlike nativePlayerLayer
    /// above which is nil on .software.
    public var isFillScreen: Bool {
        get { engine.videoGravity == .resizeAspectFill }
        set { engine.videoGravity = newValue ? .resizeAspectFill : .resizeAspect }
    }

    public init() throws {
        engine = try AetherEngine()
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
        engine.$subtitleCues.sink { [weak self] cues in
            self?.nativeBitmapCues = cues.compactMap { cue in
                guard case .image(let image) = cue.body else { return nil }
                return NativeBitmapCue(
                    id: cue.id, startTime: cue.startTime, endTime: cue.endTime,
                    cgImage: image.cgImage, position: image.position, canvasSize: image.canvasSize
                )
            }
        }.store(in: &cancellables)
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
        // About ten minutes ahead (segments are ~4 s) instead of the engine's ~40 s, filled while
        // paused too. Held on disk, not in memory, and the engine stops at a quarter of the free
        // space, so a large title on a full device buffers less rather than crowding it out.
        options.forwardBufferSegments = 150
        // The engine's open-time probe reads up to 50 MB / 60 s, which a remux with sparse PGS
        // tracks always exhausts — over a remote link that held the first frame for over a
        // minute. Video and audio resolve within the first few MB; subtitle tracks come from
        // the engine's own side demuxer, which keeps the full budget.
        if url.scheme == "http" || url.scheme == "https" {
            options.probesize = 8 * 1024 * 1024
            options.maxAnalyzeDuration = 5_000_000
        }
        log.notice("Loading \(url.absoluteString) from \(Int(startPosition ?? 0), privacy: .public) s")
        do {
            try await engine.load(url: url, startPosition: startPosition, options: options)
        } catch {
            log.error("Couldn't open the stream: \(error.localizedDescription, privacy: .public)")
            throw error
        }
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

/// Thin SwiftUI wrapper over AetherPlayerSurface, taking an AetherEnginePlayer directly —
/// same rationale as the passthroughs above: the app target's video-surface switch
/// (PlayerView.videoSurface) never needs `import AetherEngine` just for this one view.
public struct AetherEngineVideoSurface: View {
    private let player: AetherEnginePlayer

    public init(player: AetherEnginePlayer) {
        self.player = player
    }

    public var body: some View {
        AetherPlayerSurface(engine: player.engine)
    }
}
