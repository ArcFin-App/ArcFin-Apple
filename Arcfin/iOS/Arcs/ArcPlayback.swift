// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import AuthCore
import Observation

/// One clip's player. The feed keeps the one on screen and its neighbours, so a swipe starts
/// the next clip without waiting; only the one on screen plays.
@MainActor @Observable
final class ArcPlayback {
    let clipID: String
    let player: AVPlayer
    private(set) var isReady = false
    private(set) var failed = false
    private(set) var isPlaying = false
    /// Seconds into the clip, and its length once the video says.
    private(set) var elapsed: Double = 0
    private(set) var duration: Double
    /// Times it played to the end and started again.
    private(set) var loops = 0
    /// The furthest it got, for the view event: a rewind doesn't make it look skipped.
    private(set) var furthest: Double = 0

    @ObservationIgnored var onEnd: (() -> Void)?
    @ObservationIgnored var loopsAtEnd = true
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var controlObservation: NSKeyValueObservation?

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let headers: [String: String]
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var wantsPlay = false

    init(clipID: String, url: URL, authHeader: String, expectedSeconds: Double) {
        self.clipID = clipID
        self.url = url
        // A stream that's still being made has no length yet: the clip's own length stands in.
        duration = expectedSeconds
        var headers = CustomHTTPHeaders.headers(for: url)
        headers["Authorization"] = authHeader
        self.headers = headers
        player = AVPlayer()
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in self?.isPlaying = playing }
        }
        load()
    }

    private func load() {
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        // A short clip: a few seconds ahead is all it needs, and the neighbours stay light.
        item.preferredForwardBufferDuration = 6
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let seconds = item.duration.seconds
            Task { @MainActor [weak self] in
                guard let self else { return }
                if status == .readyToPlay {
                    self.isReady = true
                    self.failed = false
                    if seconds.isFinite, seconds > 0 { self.duration = seconds }
                } else if status == .failed {
                    self.retryOrFail()
                }
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnd() }
        }
        player.replaceCurrentItem(with: item)
        if wantsPlay { player.play() }
    }

    /// The server says to come back when the scene is still starting to be made (or it was
    /// cleared from its cache): a few tries, two seconds apart, before giving up.
    private func retryOrFail() {
        guard retries < 4 else {
            failed = true
            return
        }
        retries += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            // Stopped meanwhile: let go for good.
            guard let self, self.retries != .max else { return }
            self.load()
        }
    }

    var progress: Double { duration > 0 ? min(1, elapsed / duration) : 0 }

    func play() {
        wantsPlay = true
        startObservingTime()
        player.play()
    }

    func pause() {
        wantsPlay = false
        player.pause()
    }

    /// Held down: twice as fast until let go.
    func setFast(_ fast: Bool) {
        guard player.timeControlStatus != .paused else { return }
        player.rate = fast ? 2 : 1
    }

    func seek(to fraction: Double) {
        let target = CMTime(seconds: max(0, min(1, fraction)) * duration, preferredTimescale: 600)
        elapsed = target.seconds
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Off screen: back to the start and quiet, so it's ready if it comes back.
    func reset() {
        wantsPlay = false
        player.pause()
        stopObservingTime()
        player.seek(to: .zero)
        elapsed = 0
    }

    func stop() {
        wantsPlay = false
        retries = .max
        player.pause()
        stopObservingTime()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation?.invalidate()
        controlObservation?.invalidate()
        player.replaceCurrentItem(with: nil)
    }

    private func didEnd() {
        furthest = duration
        loops += 1
        if loopsAtEnd {
            player.seek(to: .zero)
            player.play()
        } else {
            onEnd?()
        }
    }

    private func startObservingTime() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = time.seconds
                self.furthest = max(self.furthest, time.seconds)
            }
        }
    }

    private func stopObservingTime() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }
}
