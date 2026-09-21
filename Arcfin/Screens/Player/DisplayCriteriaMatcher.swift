// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
#if canImport(UIKit) && !os(tvOS)
import UIKit
import AVKit

/// Matches the display's refresh rate to the content's frame rate (e.g. 23.976fps film plays
/// without 3:2 pulldown judder on a ProMotion display) — AVFoundation only exposes this
/// through AVPlayerViewController's own display manager, so this keeps one alive purely for
/// that side effect. Its view is added to the window but stays zero-size and non-interactive;
/// PlayerSurfaceView renders the actual picture, same as always.
@MainActor
final class DisplayCriteriaMatcher {
    private let controller = AVPlayerViewController()
    private var attachedWindow: UIWindow?

    func attach(player: AVPlayer) {
        controller.player = player
        controller.view.frame = .zero
        controller.view.alpha = 0
        controller.view.isUserInteractionEnabled = false
        controller.showsPlaybackControls = false
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first })
            .first
        else { return }
        window.addSubview(controller.view)
        attachedWindow = window
    }

    func detach() {
        controller.player = nil
        controller.view.removeFromSuperview()
        attachedWindow = nil
    }
}
#endif
