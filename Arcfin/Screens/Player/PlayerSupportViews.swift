import SwiftUI
import AVFoundation
import AVKit
import Combine
#if canImport(UIKit) && !os(tvOS)
import UIKit
import MediaPlayer
#endif
#if canImport(GoogleCast)
import GoogleCast
#endif

// MARK: - Video surface (AVPlayerLayer) + Picture in Picture

#if canImport(UIKit) && !os(tvOS)
final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    // layerClass normally keeps layer.bounds synced to the view automatically, but the
    // XPC-based "video receiver" rendering path some HLS streams take
    // (FigUseVideoReceiverForCALayer, seen throughout the no-video logs) may not pick up
    // layout changes the same way — force it explicitly rather than trust that path.
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

final class PiPCoordinator: NSObject, AVPictureInPictureControllerDelegate, ObservableObject {
    @Published var isActive = false
    // Was previously a computed property derived from `controller`, which isn't @Published —
    // SwiftUI never observed it flipping true after the async attach() call, so the PiP
    // button could never actually appear even on devices that support it.
    @Published var isSupported = false
    private var controller: AVPictureInPictureController?
    private var pendingLayer: AVPlayerLayer?

    /// Just remembers the layer — doesn't create the controller yet. Creating an
    /// AVPictureInPictureController switches the layer into a "video receiver" rendering
    /// mode internally; doing that before the layer has any content set up (i.e. right when
    /// the view appears, before the stream has loaded) is the likely cause of some HLS
    /// streams never actually rendering video afterward.
    ///
    /// Named `stashLayer` rather than `captureLayer` — the latter nearly matched the
    /// selector of `AVPictureInPictureControllerDelegate`'s optional `pictureInPictureController`
    /// requirement closely enough that the compiler warned about accidental-override risk.
    func stashLayer(_ layer: AVPlayerLayer) {
        pendingLayer = layer
    }

    /// Call once playback has actually started — see stashLayer's note on why this isn't
    /// done any earlier.
    func activateIfNeeded() {
        guard controller == nil, let layer = pendingLayer,
              AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        self.controller = controller
        isSupported = controller != nil
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
    }
}

struct PlayerLayerRepresentable: UIViewRepresentable {
    let player: AVPlayer
    let pip: PiPCoordinator
    var isFillScreen: Bool = false

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = isFillScreen ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        pip.stashLayer(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = isFillScreen ? .resizeAspectFill : .resizeAspect
    }
}

// MARK: - Rotate button (shared by online + offline players)

/// Flips between portrait and forced landscape — iPad/iPhone with multiple orientations
/// enabled don't always rotate on their own for a video sheet, so this is a manual override.
func togglePlayerOrientation() {
    guard let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    else { return }
    let isLandscape = scene.effectiveGeometry.interfaceOrientation.isLandscape
    let targetMask: UIInterfaceOrientationMask = isLandscape ? .portrait : .landscapeRight
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: targetMask)) { _ in }
}

// MARK: - AirPlay route picker

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(DT.Color.accent)
        view.prioritizesVideoDevices = true
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Chromecast button

#if canImport(GoogleCast)
struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let view = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        view.tintColor = .white
        return view
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
#endif

// MARK: - System volume control (swipe-to-adjust-volume support)

/// Programmatic system-volume changes are only possible through MPVolumeView's
/// hidden slider — there is no public AVAudioSession API for it.
@MainActor
final class SystemVolumeController {
    private let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    private weak var slider: UISlider?

    init() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first })
            .first else { return }
        window.addSubview(volumeView)
        slider = volumeView.subviews.first { $0 is UISlider } as? UISlider
    }

    var currentVolume: Float { AVAudioSession.sharedInstance().outputVolume }

    func setVolume(_ value: Float) {
        slider?.value = min(max(value, 0), 1)
    }

    func teardown() {
        volumeView.removeFromSuperview()
    }
}
#endif
