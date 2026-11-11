// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AVFoundation
import AuthCore
import AVKit
import Observation
import Telemetry

// MARK: - Player protocol

/// Individual properties are required (not just the aggregate `state`) so a view can bind
/// to `player.status`/`player.positionTicks`/etc. directly through an `any MediaPlayerProtocol`
/// existential and still get correct SwiftUI/Observation tracking — matches how
/// `AVFoundationPlayer` already exposed these before a second engine existed.
@MainActor
public protocol MediaPlayerProtocol: AnyObject, Sendable {
    var state: PlayerState { get }
    var status: PlaybackStatus { get }
    var positionTicks: Int64 { get }
    var durationTicks: Int64 { get }
    var isBuffering: Bool { get }
    var availableAudioTracks: [AudioTrack] { get }
    var availableSubtitleTracks: [SubtitleTrack] { get }
    var selectedAudioTrackIndex: Int { get }
    var selectedSubtitleTrackIndex: Int? { get }
    var playbackRate: Float { get }
    func load(url: URL, startPositionTicks: Int64) async throws
    func play() async
    func pause() async
    func seek(to positionTicks: Int64) async
    func setAudioTrack(index: Int) async
    func setSubtitleTrack(index: Int?) async
    func setRate(_ rate: Float) async
    func stop() async
}

/// A live stream the player keeps some of, so it can be paused and gone back into. Seconds are
/// on the player's own timeline for the stream.
@MainActor
public protocol LiveRewindable: AnyObject {
    /// What can be gone back into so far, up to the live edge; nil before anything is kept.
    var liveWindow: ClosedRange<Double>? { get }
    /// How far behind live playback is, in seconds.
    var secondsBehindLive: Double { get }
    func seekLive(toSeconds seconds: Double) async
    func goToLiveEdge() async
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
    /// A narrator describing the picture, for blind and low-vision viewers. Only Aether reads it.
    public var isAudioDescription: Bool

    public init(id: Int, displayName: String, language: String? = nil, isAudioDescription: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.isAudioDescription = isAudioDescription
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

/// Races a one-shot seekableTimeRanges read against a timeout — same lock-guarded
/// resume-once pattern as MediaRepository's PathWait, for a KVO callback with no bounded
/// completion time of its own (a stream that never covers the target shouldn't hang load()).
private final class SeekableRangeWait: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Void, Never>
    private var observation: NSKeyValueObservation?

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func start(item: AVPlayerItem, targetSeconds: Double, timeoutSeconds: Double) {
        if Self.covers(item.seekableTimeRanges, targetSeconds) {
            finish()
            return
        }
        observation = item.observe(\.seekableTimeRanges, options: [.new]) { [weak self] item, _ in
            guard Self.covers(item.seekableTimeRanges, targetSeconds) else { return }
            self?.finish()
        }
        Task {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            self.finish()
        }
    }

    private static func covers(_ ranges: [NSValue], _ targetSeconds: Double) -> Bool {
        ranges.contains { value in
            let range = value.timeRangeValue
            let start = CMTimeGetSeconds(range.start)
            let end = CMTimeGetSeconds(CMTimeAdd(range.start, range.duration))
            return targetSeconds >= start && targetSeconds <= end
        }
    }

    private func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        observation?.invalidate()
        continuation.resume()
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
    #if !os(macOS)
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    /// Only true when handleInterruption itself paused playback — distinguishes that from
    /// the user having already paused before the interruption began, so .ended doesn't
    /// resume something the user deliberately stopped.
    @ObservationIgnored private var pausedByInterruption = false
    #endif
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleGroup: AVMediaSelectionGroup?

    public init() {
        // Without this, AVKit can silently re-pick an audio/subtitle track on its own
        // (e.g. after a variant change) based on system language/accessibility criteria,
        // overriding an explicit setAudioTrack/setSubtitleTrack call the user just made.
        player.appliesMediaSelectionCriteriaAutomatically = false
        #if !os(macOS)
        // `status` here is a plain flag this class owns, only ever set by its own play()/
        // pause() calls — it doesn't track player.rate or timeControlStatus. System UI that
        // briefly takes audio focus (Notification Center / Control Center appearing over the
        // app is a known trigger, not just phone calls/Siri) interrupts the session and
        // silently drops actual playback without going through pause() — so `status` was
        // left stuck on .playing while the video sat genuinely paused, and the first tap on
        // play/pause just resynced the flag instead of resuming anything. This keeps status
        // truthful and, per Apple's documented interruption-handling pattern, auto-resumes
        // when the interruption ends with the system's own shouldResume hint.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Notification isn't Sendable (its userInfo is [AnyHashable: Any]) — pulling the
            // plain Sendable values (UInt type/options) out here, in this nonisolated
            // @Sendable callback, and passing only those across into the MainActor-isolated
            // block below is what actually avoids the data race, not just silencing it.
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated {
                self?.handleInterruption(type: type, optionsValue: optionsValue)
            }
        }
        #endif
    }

    #if !os(macOS)
    private func handleInterruption(type: AVAudioSession.InterruptionType, optionsValue: UInt?) {
        switch type {
        case .began:
            if status == .playing {
                status = .paused
                pausedByInterruption = true
            }
        case .ended:
            defer { pausedByInterruption = false }
            guard pausedByInterruption, let optionsValue else { return }
            if AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                player.rate = playbackRate
                status = .playing
            }
        @unknown default:
            break
        }
    }
    #endif

    public func load(url: URL, startPositionTicks: Int64) async throws {
        teardownObservers()
        status = .loading
        isBuffering = true
        positionTicks = 0
        durationTicks = 0

        let headers = CustomHTTPHeaders.current
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        // Left at 0, AVPlayer keeps a short lead chosen for it. Asking for three minutes lets it
        // keep loading ahead, paused too, while the connection has room, so scrubbing nearby and
        // a dip in bandwidth play from what's already here.
        item.preferredForwardBufferDuration = 180
        player.replaceCurrentItem(with: item)
        log.notice("Loading \(url.absoluteString)")

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
            // .readyToPlay doesn't mean seekableTimeRanges covers startPositionTicks yet —
            // for a Jellyfin HLS transcode (switching audio/subtitle tracks reloads via a
            // fresh transcode, see PlayerView.reload) the manifest/segment map streams in
            // progressively, so seeking here before it catches up gets silently clamped
            // back toward 0 instead of landing at the resume position. Direct-play files
            // know their full range immediately, which is why this only ever showed up
            // "sometimes" and specifically around a track change.
            await waitUntilSeekable(item: item, targetSeconds: Double(startPositionTicks) / 10_000_000)
            await seek(to: startPositionTicks)
        }
        status = .paused
    }

    private func waitUntilSeekable(item: AVPlayerItem, targetSeconds: Double, timeoutSeconds: Double = 5) async {
        await withCheckedContinuation { continuation in
            SeekableRangeWait(continuation: continuation)
                .start(item: item, targetSeconds: targetSeconds, timeoutSeconds: timeoutSeconds)
        }
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
        #if !os(macOS)
        pausedByInterruption = false
        #endif
    }

    public func setRate(_ rate: Float) async {
        playbackRate = rate
        if status == .playing { player.rate = rate }
    }

    public func pause() async {
        player.pause()
        status = .paused
        #if !os(macOS)
        pausedByInterruption = false
        #endif
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
        // interruptionObserver is deliberately not torn down here — teardownObservers()
        // runs at the top of every load()/reload(), not just final stop(), and an
        // interruption can legitimately happen mid-reload. It lives for this player
        // instance's whole lifetime instead; NotificationCenter auto-unregisters a stored
        // observer token when it's deallocated, so no explicit deinit is needed for it.
    }
}

extension AVFoundationPlayer: LiveRewindable {
    public var liveWindow: ClosedRange<Double>? {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return nil }
        let start = CMTimeGetSeconds(range.start), end = CMTimeGetSeconds(range.end)
        guard start.isFinite, end.isFinite, end > start else { return nil }
        return start...end
    }

    public var secondsBehindLive: Double {
        guard let window = liveWindow else { return 0 }
        return max(window.upperBound - CMTimeGetSeconds(player.currentTime()), 0)
    }

    public func seekLive(toSeconds seconds: Double) async {
        await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    public func goToLiveEdge() async {
        guard let window = liveWindow else { return }
        await player.seek(to: CMTime(seconds: window.upperBound, preferredTimescale: 600))
        if player.timeControlStatus != .playing { player.play() }
    }
}
