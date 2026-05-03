import Foundation
import AVFoundation
import Telemetry

// MARK: - Player protocol

public protocol MediaPlayerProtocol: AnyObject, Sendable {
    var state: PlayerState { get }
    func load(url: URL, startPositionTicks: Int64) async throws
    func play() async
    func pause() async
    func seek(to positionTicks: Int64) async
    func setAudioTrack(index: Int) async
    func setSubtitleTrack(index: Int?) async
    func stop() async
}

// MARK: - Player state

public struct PlayerState: Sendable, Equatable {
    public var status: PlaybackStatus = .idle
    public var positionTicks: Int64 = 0
    public var durationTicks: Int64 = 0
    public var availableAudioTracks: [AudioTrack] = []
    public var availableSubtitleTracks: [SubtitleTrack] = []
    public var selectedAudioTrackIndex: Int = 0
    public var selectedSubtitleTrackIndex: Int? = nil

    public init() {}
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

public final class AVFoundationPlayer: MediaPlayerProtocol {

    private let log = Telemetry.logger(category: "AVFoundationPlayer")
    private let _player = AVPlayer()
    private let _state = PlayerStateBox()

    public var state: PlayerState { _state.value }

    public init() {}

    public func load(url: URL, startPositionTicks: Int64) async throws {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        await MainActor.run { _player.replaceCurrentItem(with: item) }
        _state.value.status = .loading
        log.info("Loading \(url.lastPathComponent)")
    }

    public func play() async {
        await MainActor.run { _player.play() }
        _state.value.status = .playing
    }

    public func pause() async {
        await MainActor.run { _player.pause() }
        _state.value.status = .paused
    }

    public func seek(to positionTicks: Int64) async {
        let seconds = Double(positionTicks) / 10_000_000
        let time = CMTime(seconds: seconds, preferredTimescale: 1000)
        await _player.seek(to: time)
    }

    public func setAudioTrack(index: Int) async {
        _state.value.selectedAudioTrackIndex = index
    }

    public func setSubtitleTrack(index: Int?) async {
        _state.value.selectedSubtitleTrackIndex = index
    }

    public func stop() async {
        await MainActor.run {
            _player.pause()
            _player.replaceCurrentItem(with: nil)
        }
        _state.value.status = .idle
    }
}

// Thread-safe box for PlayerState mutations outside of actors
final class PlayerStateBox: @unchecked Sendable {
    var value = PlayerState()
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
    public func stop() async {}
}
