import SwiftUI
import AVFoundation
import AVKit
import Combine
#if canImport(UIKit) && !os(tvOS)
import UIKit
import MediaPlayer
#endif

// MARK: - Video surface (AVPlayerLayer) + Picture in Picture

#if !os(tvOS)
final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class PiPCoordinator: NSObject, AVPictureInPictureControllerDelegate, ObservableObject {
    @Published var isActive = false
    private var controller: AVPictureInPictureController?

    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported(), controller == nil else { return }
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.delegate = self
        self.controller = controller
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    var isSupported: Bool { controller != nil }

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

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        pip.attach(to: view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
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
