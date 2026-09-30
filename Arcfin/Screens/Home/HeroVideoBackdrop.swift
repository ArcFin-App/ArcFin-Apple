// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
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
}

final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    // AVPlayerLooper needs its player/item kept alive for as long as looping should
    // continue — both held here, not just handed to the layer.
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .clear
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        player.play()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Letting ARC deallocate queuePlayer/looper without an explicit stop first is a known
    // source of CoreAudio HAL teardown races — pause and break the reference chain
    // ourselves so AVFoundation tears the audio render chain down cleanly.
    deinit {
        queuePlayer?.pause()
        looper = nil
        queuePlayer = nil
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
}

final class LoopingPlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        player.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Letting ARC deallocate queuePlayer/looper without an explicit stop first is a known
    // source of CoreAudio HAL teardown races — pause and break the reference chain
    // ourselves so AVFoundation tears the audio render chain down cleanly. macOS's HAL is
    // stricter about clean teardown sequencing than iOS, matching the reported crash signature
    // (HALC_ProxyIOContext start failures right after a hero slide/video backdrop changes).
    deinit {
        queuePlayer?.pause()
        looper = nil
        queuePlayer = nil
    }

    override func makeBackingLayer() -> CALayer { playerLayer }

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
