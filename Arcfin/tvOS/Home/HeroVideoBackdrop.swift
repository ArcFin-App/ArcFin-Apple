// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import AVFoundation
import UIKit

/// Muted, seamlessly-looping video behind the Home hero — the "video backdrop" idea some
/// Jellyfin hero-enhancement plugins offer, built here on stock Jellyfin local-trailer data
/// (Items/{id}/LocalTrailers, a real video file the server already has indexed) rather than
/// depending on any specific plugin's own config, which no third-party client can read
/// anyway. Falls back to nothing whenever a title has no local trailer — most won't, and
/// the static backdrop image already showing underneath just stays as-is.
struct HeroVideoBackdropView: UIViewRepresentable {
    let url: URL
    var loops = true
    var muted = true
    /// Called once, when the video is actually playing and has faded in.
    var onStart: (() -> Void)? = nil
    /// Called when a trailer that doesn't loop reaches its end.
    var onEnd: (() -> Void)? = nil

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url, loops: loops, muted: muted, onStart: onStart, onEnd: onEnd)
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
    private let loops: Bool
    private let onStart: (() -> Void)?
    private let onEnd: (() -> Void)?

    init(url: URL, loops: Bool, muted: Bool, onStart: (() -> Void)?, onEnd: (() -> Void)?) {
        self.loops = loops
        self.onStart = onStart
        self.onEnd = onEnd
        super.init(frame: .zero)
        let headers = CustomHTTPHeaders.headers(for: url)
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted
        // A backdrop: never sent to AirPlay, where it would take over from music or a video.
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = loops ? .none : .pause
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
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidEnd() }
        }

        // isMuted only zeroes the output — the player still opens a CoreAudio HAL slot
        // for the audio track. Deselecting it outright means there's no audio render
        // pipeline at all when the backdrop is silent.
        if muted {
            Task { @MainActor in
                guard let group = try? await asset.loadMediaSelectionGroup(for: .audible) else { return }
                item.select(nil, in: group)
            }
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
            Task { @MainActor [weak self] in self?.onStart?() }
        }
    }

    private func itemDidEnd() {
        guard loops else {
            onEnd?()
            return
        }
        player?.seek(to: .zero)
        player?.play()
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
