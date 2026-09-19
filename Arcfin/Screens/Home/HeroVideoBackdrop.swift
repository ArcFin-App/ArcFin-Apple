import SwiftUI
import AVFoundation

#if canImport(UIKit) && !os(tvOS)
import UIKit

/// Muted, seamlessly-looping video behind the Home hero — the "video backdrop" idea some
/// Jellyfin hero-enhancement plugins offer, built here on stock Jellyfin local-trailer data
/// (Items/{id}/LocalTrailers, a real video file the server already has indexed) rather than
/// depending on any specific plugin's own config, which no third-party client can read
/// anyway. Falls back to nothing whenever a title has no local trailer — most won't, and
/// the static backdrop image already showing underneath just stays as-is.
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
#endif
