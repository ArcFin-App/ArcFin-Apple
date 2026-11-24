// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import AVFoundation
import AppKit

/// Muted, seamlessly-looping video behind the Home hero — the "video backdrop" idea some
/// Jellyfin hero-enhancement plugins offer, built here on stock Jellyfin local-trailer data
/// (Items/{id}/LocalTrailers, a real video file the server already has indexed) rather than
/// depending on any specific plugin's own config, which no third-party client can read
/// anyway. Falls back to nothing whenever a title has no local trailer — most won't, and
/// the static backdrop image already showing underneath just stays as-is.
///
/// AppKit equivalent of LoopingPlayerUIView in the iOS version.
struct HeroVideoBackdropView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingPlayerNSView {
        LoopingPlayerNSView(url: url)
    }
    func updateNSView(_ nsView: LoopingPlayerNSView, context: Context) {}
    // See the matching note on HeroVideoBackdropView's UIKit dismantleUIView above — a
    // .transition(.opacity) crossfade can keep this view (and its ARC lifetime) alive past
    // when SwiftUI actually removes it, while the next hero slide's own player is already
    // starting. dismantleNSView runs synchronously at removal time, so stop the player here
    // rather than relying on deinit timing.
    static func dismantleNSView(_ nsView: LoopingPlayerNSView, coordinator: ()) {
        nsView.stop()
    }
}

final class LoopingPlayerNSView: NSView {
    // A sublayer rather than the view's own layer, so it can grow past the view's edges to
    // crop black bars baked into the trailer (see measureLetterbox).
    private let playerLayer = AVPlayerLayer()
    private let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    private var picture = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var letterboxTask: Task<Void, Never>?
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var hasFadedIn = false

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        let headers = CustomHTTPHeaders.headers(for: url)
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.add(videoOutput)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        // A backdrop: never sent to AirPlay, where it would take over from music or a video.
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
        layer?.masksToBounds = true
        // See LoopingPlayerUIView's matching note above — stay invisible until
        // timeControlStatus confirms real playback, instead of showing a frozen first
        // frame while the HLS transcode spins up.
        alphaValue = 0
        self.player = player
        // Calling play() here can be a no-op on macOS — the diagnostic snapshot showed a
        // fully healthy player (status .readyToPlay, buffer non-empty, isReadyForDisplay
        // true, tens of seconds already loaded) stuck at rate 0 regardless. This NSView
        // isn't attached to a window yet at init time (SwiftUI calls makeNSView before
        // inserting it into the hierarchy), and AVPlayerLayer's clock can fail to start
        // when play() is requested before that attachment. viewDidMoveToWindow below
        // retries once the view is actually on screen; this call stays as a fallback for
        // cases where the window is already set.
        player.play()

        // See LoopingPlayerUIView's matching note above — AVPlayerLooper doesn't support
        // HLS player items, and this backdrop is served as an HLS transcode whenever the
        // trailer's own codec/container isn't natively playable. That's the confirmed
        // cause of the freeze on frame 1 (0 video tracks, status stuck at .unknown).
        // Loop manually via seek-to-zero instead.
        loopObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        // See LoopingPlayerUIView's matching note above — isMuted alone doesn't stop the
        // player from opening a CoreAudio HAL slot for the audio track. Deselect it
        // outright since this backdrop is always silent anyway.
        Task { @MainActor in
            guard let group = try? await asset.loadMediaSelectionGroup(for: .audible) else { return }
            item.select(nil, in: group)
        }

        // readyToPlay only means the asset is minimally parsed, not that enough has
        // buffered to run smoothly — re-issuing play() here (on top of the init-time
        // call and the viewDidMoveToWindow retry below) is what actually got every
        // rotated hero item playing reliably, instead of just whichever one happened to
        // already be ready by the time an earlier play() call landed.
        statusObservation = item.observe(\.status, options: [.new]) { [weak player] item, _ in
            if item.status == .readyToPlay {
                player?.play()
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .playing, let self, !self.hasFadedIn else { return }
            self.hasFadedIn = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.animator().alphaValue = 1
            }
            Task { @MainActor [weak self] in self?.measureLetterbox() }
        }
    }

    /// See LoopingPlayerUIView.measureLetterbox in the iOS version.
    private func measureLetterbox() {
        // Off the main thread, timed by the output's own clock: the item's currentTime() waits
        // on AVFoundation's lock, which a stalling transcode can hold for seconds (#747).
        let output = videoOutput
        letterboxTask = Task.detached(priority: .utility) { [weak self] in
            var previous: CGRect?
            var found: CGRect?
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                let time = output.itemTime(forHostTime: CACurrentMediaTime())
                guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
                      let picture = TrailerLetterbox.pictureRect(in: buffer) else { continue }
                if let previous, TrailerLetterbox.matches(previous, picture) {
                    found = picture
                    break
                }
                previous = picture
            }
            await MainActor.run { [weak self, found] in
                guard let self else { return }
                self.player?.currentItem?.remove(output)
                guard let found else { return }
                self.picture = found
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.4)
                self.playerLayer.frame = self.videoFrame()
                CATransaction.commit()
            }
        }
    }

    private func videoFrame() -> CGRect {
        guard let size = player?.currentItem?.presentationSize, size != .zero else { return bounds }
        return TrailerLetterbox.frame(videoSize: size, picture: picture, filling: bounds.size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Letting ARC deallocate the player without an explicit stop first is a known source
    // of CoreAudio HAL teardown races — pause and break the reference chain ourselves so
    // AVFoundation tears the audio render chain down cleanly. Also called explicitly from
    // dismantleNSView, which runs at the actual moment SwiftUI removes this view, since a
    // crossfade transition can delay this deinit well past that point.
    func stop() {
        letterboxTask?.cancel()
        letterboxTask = nil
        player?.pause()
        player = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
    }

    deinit {
        stop()
    }

    // play() requested back in init can land before this view is actually attached to a
    // window (SwiftUI calls makeNSView off-hierarchy first) — retry once it's really on
    // screen, since that's the one state transition the diagnostic snapshot couldn't
    // rule out (everything else about the player was already healthy: ready, buffered,
    // isReadyForDisplay true, just rate stuck at 0).
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let player, player.rate == 0 {
            player.play()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = videoFrame()
        CATransaction.commit()
    }
}
