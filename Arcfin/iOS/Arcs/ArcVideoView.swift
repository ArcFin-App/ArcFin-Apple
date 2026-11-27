// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// A clip's picture, filling the page as Settings › Arcs › Framing says: cropped to fill, the
/// whole picture over a blurred copy of itself, or the whole picture on black.
struct ArcVideoView: UIViewRepresentable {
    let playback: ArcPlayback
    let framing: ArcsFraming
    let isCurrent: Bool
    /// Bumped to ask for Picture in Picture on the clip on screen. Every page sees the count,
    /// so one coming into view later doesn't take an old request as new.
    var pictureInPictureRequest = 0

    func makeUIView(context: Context) -> ArcVideoUIView {
        ArcVideoUIView(player: playback.player, framing: framing)
    }

    func updateUIView(_ view: ArcVideoUIView, context: Context) {
        view.setFraming(framing)
        if pictureInPictureRequest != context.coordinator.lastRequest {
            context.coordinator.lastRequest = pictureInPictureRequest
            if isCurrent { view.startPictureInPicture() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(lastRequest: pictureInPictureRequest) }

    final class Coordinator {
        var lastRequest: Int
        init(lastRequest: Int) { self.lastRequest = lastRequest }
    }
}

final class ArcVideoUIView: UIView {
    private let backdrop = AVPlayerLayer()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let picture = AVPlayerLayer()
    private var pip: AVPictureInPictureController?
    private var framing: ArcsFraming

    init(player: AVPlayer, framing: ArcsFraming) {
        self.framing = framing
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        backdrop.player = player
        backdrop.videoGravity = .resizeAspectFill
        picture.player = player
        layer.addSublayer(backdrop)
        addSubview(blur)
        layer.addSublayer(picture)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer: picture)
        }
        apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setFraming(_ framing: ArcsFraming) {
        guard framing != self.framing else { return }
        self.framing = framing
        apply()
    }

    func startPictureInPicture() {
        pip?.startPictureInPicture()
    }

    private func apply() {
        backdrop.isHidden = framing != .blur
        blur.isHidden = framing != .blur
        picture.videoGravity = framing == .fill ? .resizeAspectFill : .resizeAspect
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds.insetBy(dx: -40, dy: -40)
        picture.frame = bounds
        CATransaction.commit()
        blur.frame = bounds
    }
}
