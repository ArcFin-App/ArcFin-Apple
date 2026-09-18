import Foundation
import AVFoundation
import AVKit
import Observation
import Telemetry

// MARK: - Player protocol

@MainActor
public protocol MediaPlayerProtocol: AnyObject, Sendable {
    var state: PlayerState { get }
    func load(url: URL, startPositionTicks: Int64) async throws
    func play() async
    func pause() async
    func seek(to positionTicks: Int64) async
    func setAudioTrack(index: Int) async
    func setSubtitleTrack(index: Int?) async
    func setRate(_ rate: Float) async
    func stop() async
}

// MARK: - Player state

public struct PlayerState: Sendable, Equatable {
    public var status: PlaybackStatus = .idle
    public var positionTicks: Int64 = 0
    public var durationTicks: Int64 = 0
    public var isBuffering: Bool = false
    public var availableAudioTracks: [AudioTrack] = []
    public var availableSubtitleTracks: [SubtitleTrack] = []
    public var selectedAudioTrackIndex: Int = 0
    public var selectedSubtitleTrackIndex: Int? = nil

    public init(status: PlaybackStatus = .idle, positionTicks: Int64 = 0, durationTicks: Int64 = 0,
                isBuffering: Bool = false, availableAudioTracks: [AudioTrack] = [],
                availableSubtitleTracks: [SubtitleTrack] = [], selectedAudioTrackIndex: Int = 0,
                selectedSubtitleTrackIndex: Int? = nil) {
        self.status = status; self.positionTicks = positionTicks; self.durationTicks = durationTicks
        self.isBuffering = isBuffering; self.availableAudioTracks = availableAudioTracks
        self.availableSubtitleTracks = availableSubtitleTracks
        self.selectedAudioTrackIndex = selectedAudioTrackIndex
        self.selectedSubtitleTrackIndex = selectedSubtitleTrackIndex
    }
}

public enum PlaybackStatus: Sendable, Equatable {
    case idle, loading, playing, paused, ended, failed(String)
}

public struct AudioTrack: Sendable, Equatable, Identifiable {
    public let id: Int
    public var displayName: String
    public var language: String?

    public init(id: Int, displayName: String, language: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.language = language
    }
}

public struct SubtitleTrack: Sendable, Equatable, Identifiable {
    public let id: Int
    public var displayName: String
    public var language: String?
    public var isExternal: Bool

    public init(id: Int, displayName: String, language: String? = nil, isExternal: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.isExternal = isExternal
    }
}

// MARK: - AVFoundation adapter (primary until MPV wrapper lands)

@MainActor
@Observable
public final class AVFoundationPlayer: MediaPlayerProtocol, @unchecked Sendable {

    private let log = Telemetry.logger(category: "AVFoundationPlayer")
    public let player = AVPlayer()

    public private(set) var status: PlaybackStatus = .idle
    public private(set) var positionTicks: Int64 = 0
    public private(set) var durationTicks: Int64 = 0
    public private(set) var isBuffering: Bool = false
    public private(set) var availableAudioTracks: [AudioTrack] = []
    public private(set) var availableSubtitleTracks: [SubtitleTrack] = []
    public private(set) var selectedAudioTrackIndex: Int = 0
    public private(set) var selectedSubtitleTrackIndex: Int? = nil
    public private(set) var playbackRate: Float = 1.0

    public var state: PlayerState {
        PlayerState(status: status, positionTicks: positionTicks, durationTicks: durationTicks,
                    isBuffering: isBuffering, availableAudioTracks: availableAudioTracks,
                    availableSubtitleTracks: availableSubtitleTracks,
                    selectedAudioTrackIndex: selectedAudioTrackIndex,
                    selectedSubtitleTrackIndex: selectedSubtitleTrackIndex)
    }

    @ObservationIgnored private var timeObserverToken: Any?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var bufferObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleGroup: AVMediaSelectionGroup?

    public init() {
        // Without this, AVKit can silently re-pick an audio/subtitle track on its own
        // (e.g. after a variant change) based on system language/accessibility criteria,
        // overriding an explicit setAudioTrack/setSubtitleTrack call the user just made.
        player.appliesMediaSelectionCriteriaAutomatically = false
    }

    public func load(url: URL, startPositionTicks: Int64) async throws {
        teardownObservers()
        status = .loading
        isBuffering = true
        positionTicks = 0
        durationTicks = 0

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        log.info("Loading \(url.absoluteString)")

        do {
            let duration = try await asset.load(.duration)
            if duration.isNumeric {
                durationTicks = Int64(CMTimeGetSeconds(duration) * 10_000_000)
            }
        } catch {
            log.warning("Duration load failed: \(error.localizedDescription)")
        }

        await loadTracks(asset: asset)
        observe(item: item)

        // Without this, a broken URL (bad transcode path, unreachable server, unsupported
        // codec) would report success here — the item only surfaces .failed asynchronously
        // via KVO afterward — so load() would return, play()/reportPlaybackStart would fire,
        // and nothing would visibly happen while the server still thought playback started.
        try await waitUntilReady(item: item)

        if startPositionTicks > 0 {
            await seek(to: startPositionTicks)
        }
        status = .paused
    }

    private func waitUntilReady(item: AVPlayerItem) async throws {
        if item.status == .readyToPlay { return }
        if item.status == .failed { throw item.error ?? URLError(.cannotLoadFromNetwork) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var observation: NSKeyValueObservation?
            observation = item.observe(\.status, options: [.new]) { item, _ in
                guard item.status != .unknown else { return }
                observation?.invalidate()
                if item.status == .failed {
                    continuation.resume(throwing: item.error ?? URLError(.cannotLoadFromNetwork))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public func play() async {
        // player.play() always resets rate to 1.0 — setting .rate directly is what actually
        // starts playback at a non-default speed.
        player.rate = playbackRate
        status = .playing
    }

    public func setRate(_ rate: Float) async {
        playbackRate = rate
        if status == .playing { player.rate = rate }
    }

    public func pause() async {
        player.pause()
        status = .paused
    }

    public func seek(to positionTicks: Int64) async {
        let seconds = Double(positionTicks) / 10_000_000
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        self.positionTicks = positionTicks
    }

    public func setAudioTrack(index: Int) async {
        guard let group = audioGroup,
              let option = group.options.first(where: { $0.hash == index }) else { return }
        player.currentItem?.select(option, in: group)
        selectedAudioTrackIndex = index
    }

    public func setSubtitleTrack(index: Int?) async {
        guard let group = subtitleGroup else { return }
        guard let index, let option = group.options.first(where: { $0.hash == index }) else {
            player.currentItem?.select(nil, in: group)
            selectedSubtitleTrackIndex = nil
            return
        }
        player.currentItem?.select(option, in: group)
        selectedSubtitleTrackIndex = index
    }

    public func stop() async {
        teardownObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        status = .idle
    }

    // MARK: - Track discovery

    private func loadTracks(asset: AVURLAsset) async {
        audioGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
        subtitleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)

        availableAudioTracks = (audioGroup?.options ?? []).map { option in
            AudioTrack(id: option.hash, displayName: option.displayName, language: option.locale?.identifier)
        }
        availableSubtitleTracks = (subtitleGroup?.options ?? []).map { option in
            SubtitleTrack(id: option.hash, displayName: option.displayName, language: option.locale?.identifier, isExternal: false)
        }
        if let selected = audioGroup.flatMap({ player.currentItem?.currentMediaSelection.selectedMediaOption(in: $0) }) {
            selectedAudioTrackIndex = selected.hash
        }
    }

    // MARK: - Observation

    private func observe(item: AVPlayerItem) {
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.positionTicks = Int64(CMTimeGetSeconds(time) * 10_000_000)
            }
        }

        // .initial matters here, not just .new — a local file's isPlaybackLikelyToKeepUp is
        // often already true the instant this observer is registered (no network latency to
        // wait out), so a change-only observer would never fire and isBuffering (set true at
        // the top of load()) would stay stuck forever, leaving the spinner on indefinitely.
        bufferObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .initial]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                self?.isBuffering = !item.isPlaybackLikelyToKeepUp
            }
        }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if item.status == .failed {
                    let message = item.error?.localizedDescription ?? "Playback failed."
                    self.status = .failed(message)
                    self.log.error("AVPlayerItem failed: \(message)")
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.status = .ended
            }
        }
    }

    private func teardownObservers() {
        if let token = timeObserverToken { player.removeTimeObserver(token) }
        timeObserverToken = nil
        bufferObservation?.invalidate(); bufferObservation = nil
        itemStatusObservation?.invalidate(); itemStatusObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}

// MARK: - MPV adapter (stub — link libmpv when wrapper is available)

public final class MPVPlayer: MediaPlayerProtocol {

    private let log = Telemetry.logger(category: "MPVPlayer")
    // nonisolated(unsafe) — stub only, replaced by actor-based MPV wrapper when libmpv lands
    public nonisolated(unsafe) var state: PlayerState = .init()

    public init() {}

    public func load(url: URL, startPositionTicks: Int64) async throws {
        log.warning("MPVPlayer stub — not yet linked to libmpv")
    }

    public func play() async {}
    public func pause() async {}
    public func seek(to positionTicks: Int64) async {}
    public func setAudioTrack(index: Int) async {}
    public func setSubtitleTrack(index: Int?) async {}
    public func setRate(_ rate: Float) async {}
    public func stop() async {}
}
