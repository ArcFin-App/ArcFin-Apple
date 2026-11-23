// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVFoundation
import AVKit
import Combine
import JellyfinAPI
import MediaEngine

// MARK: - Cross-platform image typealias

// TrickplayLoader (server and downloaded tiles) and NowPlayingManager artwork all
// need a concrete image type — UIImage doesn't exist on macOS, so this is the one place that
// picks the real type per platform and everything else spells `PlatformImage`.
public typealias PlatformImage = UIImage

extension PlatformImage {
    static func from(cgImage: CGImage) -> PlatformImage {
        return PlatformImage(cgImage: cgImage)
    }

    static func from(contentsOfFile path: String) -> PlatformImage? {
        return PlatformImage(contentsOfFile: path)
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

// MARK: - Video surface (AVPlayerLayer)

final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    // Because layerClass makes this view's own backing layer the AVPlayerLayer, any ambient
    // animation active when the hosting view gets resized (e.g. toggleControls()'s
    // withAnimation, fired by an unrelated tap elsewhere in the tree) implicitly animates
    // this layer's bounds/position too — the whole video visibly zooms in and settles back,
    // or now gets stuck mid-transition looking permanently zoomed. Wrapping the redundant
    // `playerLayer.frame = bounds` reassignment below in CATransaction.setDisableActions
    // doesn't reach this: UIKit sets the frame directly (not through that reassignment) as
    // part of the ambient transaction already in flight by the time layoutSubviews runs, so
    // the implicit action is already queued. Overriding the layer-delegate action hook
    // instead suppresses it unconditionally, regardless of what transaction is ambient.
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

struct PlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer
    // PiP isn't available on tvOS at all (no PiPCoordinator there) — the video surface
    // itself works identically otherwise, so only this one piece is excluded.
    var isFillScreen: Bool = false

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = isFillScreen ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = isFillScreen ? .resizeAspectFill : .resizeAspect
    }
}

/// Closes a player. When the rotate button turned it sideways while the device is held
/// upright, the screen underneath was laid out upright and would show pillarboxed until the
/// rotation caught up after the cover had gone, so the rotation goes first.
func closeRotatedPlayer(_ close: @escaping @MainActor () -> Void) {
    close()
}

/// Keeps the display on or lets it sleep; see keepsScreenAwake.
@MainActor
enum ScreenAwake {
    static func set(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }
}
