// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVFoundation
import AVKit
import Combine
import JellyfinAPI
import MediaEngine
import UIKit
import MediaPlayer
import GoogleCast

// MARK: - Cross-platform image typealias

// TrickplayLoader, NowPlayingManager artwork, and OfflinePlayerView's trickplay cropping all
// need a concrete image type — UIImage doesn't exist on macOS, so this is the one place that
// picks the real type per platform and everything else spells `PlatformImage`.
public typealias PlatformImage = UIImage

extension PlatformImage {
    var cgImageRepresentation: CGImage? {
        return cgImage
    }

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

// MARK: - Video surface (AVPlayerLayer) + Picture in Picture

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
        controller?.canStartPictureInPictureAutomaticallyFromInline = UserDefaults.standard.bool(forKey: "autoPictureInPicture")
        self.controller = controller
        isSupported = controller != nil
    }

    /// Lets go of a player that's been swapped out, so the one replacing it can take PiP.
    func detach() {
        controller?.stopPictureInPicture()
        controller = nil
        pendingLayer = nil
        isSupported = false
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

// MARK: - Rotate button

/// Settings › Player Features › Open Videos In, on iPhone.
enum PlayerOpeningOrientation: String, CaseIterable, Identifiable {
    case followDevice, landscape, portrait
    static let key = "playerOpeningOrientation"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .followDevice: String(localized: "Follow Device")
        case .landscape: String(localized: "Landscape")
        case .portrait: String(localized: "Portrait")
        }
    }

    static var current: PlayerOpeningOrientation {
        UserDefaults.standard.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .followDevice
    }
}

/// Turns the player to the orientation Open Videos In asks for, on iPhone, until the rotate
/// button changes it or the player closes (resetPlayerOrientation). A player taking over from
/// the last one in the same cover keeps whatever orientation that one was left in.
///
/// A request made while the player's full-screen cover is still coming up is dropped, so it
/// waits for the cover to settle, then asks again once if the first didn't take.
func applyOpeningOrientation() {
    let wanted = PlayerOpeningOrientation.current
    guard wanted != .followDevice, UIDevice.current.userInterfaceIdiom == .phone else { return }
    Task { @MainActor in
        for delay in [0.35, 0.6] {
            try? await Task.sleep(for: .seconds(delay))
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
            let isLandscape = scene.effectiveGeometry.interfaceOrientation.isLandscape
            if (wanted == .landscape) == isLandscape { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: wanted == .landscape ? .landscapeRight : .portrait)) { _ in }
        }
    }
}

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

/// requestGeometryUpdate's mask sticks app-wide until something else calls it again — without
/// this, using the rotate button and then leaving the player (any dismiss path) locks the
/// whole app in landscape. Called unconditionally on player teardown, not just when the user
/// actually tapped rotate, so it self-heals regardless of how the button was left.
func resetPlayerOrientation() {
    guard let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    else { return }
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .all)) { _ in }
}

/// Closes a player. When the rotate button turned it sideways while the device is held
/// upright, the screen underneath was laid out upright and would show pillarboxed until the
/// rotation caught up after the cover had gone, so the rotation goes first.
func closeRotatedPlayer(_ close: @escaping @MainActor () -> Void) {
    guard let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
          scene.effectiveGeometry.interfaceOrientation.isLandscape,
          !UIDevice.current.orientation.isLandscape
    else { close(); return }
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    Task {
        let deadline = ContinuousClock.now + .seconds(1)
        while scene.effectiveGeometry.interfaceOrientation.isLandscape, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(30))
        }
        // The geometry flips as the rotation starts; let it finish before the cover animates.
        try? await Task.sleep(for: .milliseconds(400))
        close()
    }
}

// MARK: - AirPlay / Cast route trigger bridge

/// Cast and AirPlay are native system widgets (AVRoutePickerView, GCKUICastButton) that
/// present their own picker UI internally on tap — they can't be dropped into a SwiftUI
/// `Menu`'s content as a plain row. Instead both are mounted off-screen (see
/// PlayerView+Controls' routeButtonHost) and this bridge fires their real tap target
/// programmatically from an ordinary Menu button. GCKUICastButton IS a UIButton subclass,
/// so sendActions is plain public UIKit API for it; AVRoutePickerView wraps a single
/// internal UIButton it forwards taps to — reaching into its subviews to trigger that same
/// button is a widely used, stable pattern (the view has had exactly that one-button
/// internal structure since AVRoutePickerView shipped in iOS 11).
///
/// AVRoutePickerView's internal view hierarchy on AppKit is not the same one-UIButton
/// structure (and reaching into private AppKit control internals is a much less
/// well-established pattern than the iOS one) — macOS instead shows the AirPlay button
/// directly, visible in the controls, rather than hiding it behind this bridge. See
/// AirPlayButton in the macOS player.
@MainActor
final class RouteButtonBridge {
    weak var airPlayButton: UIButton?
    weak var castButton: UIButton?

    func fireAirPlay() { airPlayButton?.sendActions(for: .touchUpInside) }
    func fireCast() { castButton?.sendActions(for: .touchUpInside) }
}

// MARK: - AirPlay route picker

struct AirPlayButton: UIViewRepresentable {
    // Defaulted so existing call sites that show this as a plain visible button (Library,
    // OfflinePlayerView) don't need a bridge — only PlayerView's hidden/triggered mount does.
    var bridge: RouteButtonBridge = RouteButtonBridge()

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(DT.Color.accent)
        view.prioritizesVideoDevices = true
        bridge.airPlayButton = view.subviews.compactMap { $0 as? UIButton }.first
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        if bridge.airPlayButton == nil {
            bridge.airPlayButton = uiView.subviews.compactMap { $0 as? UIButton }.first
        }
    }
}

// MARK: - Chromecast button

struct CastButton: UIViewRepresentable {
    var bridge: RouteButtonBridge = RouteButtonBridge()

    func makeUIView(context: Context) -> GCKUICastButton {
        let view = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        // Only mounted hidden, fired from the More menu.
        view.tintColor = .clear
        bridge.castButton = view
        return view
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
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

/// Keeps the display on or lets it sleep; see keepsScreenAwake.
@MainActor
enum ScreenAwake {
    static func set(_ awake: Bool) {
        UIApplication.shared.isIdleTimerDisabled = awake
    }
}
