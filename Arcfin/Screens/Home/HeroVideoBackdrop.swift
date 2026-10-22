// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import AVFoundation

/// Muted, seamlessly-looping video behind the Home hero — the "video backdrop" idea some
/// Jellyfin hero-enhancement plugins offer, built here on stock Jellyfin local-trailer data
/// (Items/{id}/LocalTrailers, a real video file the server already has indexed) rather than
/// depending on any specific plugin's own config, which no third-party client can read
/// anyway. Falls back to nothing whenever a title has no local trailer — most won't, and
/// the static backdrop image already showing underneath just stays as-is.
#if canImport(UIKit)
import UIKit

struct HeroVideoBackdropView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }
    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
    // A .transition(.opacity) crossfade can keep the outgoing view (and this one's ARC
    // lifetime) alive well past when SwiftUI actually removes it from the hierarchy, during
    // which the incoming hero slide's own player is already starting — two players briefly
    // competing for the same audio render chain, independent of deinit timing.
    // dismantleUIView runs synchronously at removal time, not whenever ARC gets around to
    // it, so stop the player here instead of relying on deinit alone.
    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var hasFadedIn = false

    init(url: URL) {
        super.init(frame: .zero)
        let headers = CustomHTTPHeaders.current
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .clear
        // Stay invisible until playback is actually running — showing this view as soon
        // as the URL resolves means a frozen first frame sits over the hero for however
        // long the HLS transcode takes to start, which looks broken. Fade in only once
        // timeControlStatus below confirms real playback.
        alpha = 0
        self.player = player
        player.play()

        // AVPlayerLooper doesn't support HLS player items at all (an explicitly
        // documented AVFoundation limitation) — and Jellyfin serves this backdrop as an
        // HLS transcode whenever the trailer file's own codec/container isn't natively
        // playable, which is most of the time for trailers. With AVPlayerLooper in the
        // pipeline the asset never even finished loading (0 video tracks, status stuck
        // at .unknown, empty loadedTimeRanges, confirmed via direct instrumentation) —
        // that's the actual cause of the reported freeze on frame 1, not audio or a
        // buffering heuristic. Loop manually by seeking back to zero on end instead — a
        // small hitch at the loop point beats a silent decorative video never playing.
        loopObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        // isMuted only zeroes the output — the player still opens a CoreAudio HAL slot
        // for the audio track. Deselecting it outright means there's no audio render
        // pipeline at all, since this backdrop is always silent anyway.
        Task { @MainActor in
            guard let group = try? await asset.loadMediaSelectionGroup(for: .audible) else { return }
            item.select(nil, in: group)
        }

        // readyToPlay only means the asset is minimally parsed, not that enough has
        // buffered to run smoothly — re-issuing play() here (on top of the init-time
        // call) is what actually got every rotated hero item playing reliably, instead
        // of just the one that happened to be ready by the time play() was first called.
        statusObservation = item.observe(\.status, options: [.new]) { [weak player] item, _ in
            if item.status == .readyToPlay {
                player?.play()
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .playing, let self, !self.hasFadedIn else { return }
            self.hasFadedIn = true
            UIView.animate(withDuration: 0.3) { self.alpha = 1 }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Letting ARC deallocate the player without an explicit stop first is a known source
    // of CoreAudio HAL teardown races — pause and break the reference chain ourselves so
    // AVFoundation tears the audio render chain down cleanly. Also called explicitly from
    // dismantleUIView, which runs at the actual moment SwiftUI removes this view, since a
    // crossfade transition can delay this deinit well past that point.
    func stop() {
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

    // See PlayerSurfaceView's own note in PlayerSupportViews.swift — this view's own backing
    // layer IS the AVPlayerLayer (layerClass above), so suppressing implicit animation has to
    // happen at the layer-delegate hook, not by wrapping a redundant frame reassignment in
    // CATransaction.setDisableActions in layoutSubviews.
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        switch event {
        case "bounds", "position", "frame", "transform", "sublayerTransform":
            return NSNull()
        default:
            return super.action(for: layer, forKey: event)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

#elseif os(macOS)
import AppKit

// AppKit equivalent of LoopingPlayerUIView above — see PlayerSurfaceView in
// PlayerSupportViews.swift for the same layer-backing + action(for:forKey:) pattern and why
// it isn't an override here (NSView has no base implementation to call super on).
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
    private let playerLayer = AVPlayerLayer()
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var hasFadedIn = false

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        let headers = CustomHTTPHeaders.current
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
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
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Letting ARC deallocate the player without an explicit stop first is a known source
    // of CoreAudio HAL teardown races — pause and break the reference chain ourselves so
    // AVFoundation tears the audio render chain down cleanly. Also called explicitly from
    // dismantleNSView, which runs at the actual moment SwiftUI removes this view, since a
    // crossfade transition can delay this deinit well past that point.
    func stop() {
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

    override func makeBackingLayer() -> CALayer { playerLayer }

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
        playerLayer.frame = bounds
    }

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        switch event {
        case "bounds", "position", "frame", "transform", "sublayerTransform":
            return NSNull()
        default:
            return nil
        }
    }
}
#endif
