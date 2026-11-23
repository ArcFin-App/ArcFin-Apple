// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVFoundation
import AVKit
import Combine
import JellyfinAPI
import MediaEngine
import AppKit

// MARK: - Cross-platform image typealias

// TrickplayLoader (server and downloaded tiles) and NowPlayingManager artwork all
// need a concrete image type — UIImage doesn't exist on macOS, so this is the one place that
// picks the real type per platform and everything else spells `PlatformImage`.
public typealias PlatformImage = NSImage

extension PlatformImage {
    var cgImageRepresentation: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func from(cgImage: CGImage) -> PlatformImage {
        return PlatformImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    static func from(contentsOfFile path: String) -> PlatformImage? {
        return PlatformImage(contentsOfFile: path)
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

// MARK: - Video surface (AVPlayerLayer) + Picture in Picture

// AppKit equivalent of PlayerSurfaceView above — same reasoning applies: layer-backing the
// view directly as the AVPlayerLayer (via makeBackingLayer, AppKit's analog of overriding
// layerClass) means an ambient animation on this view's own resize (e.g. toggleControls()'s
// withAnimation firing from an unrelated click elsewhere in the tree) would implicitly
// animate the layer's bounds/position too — same zoom glitch iOS had. NSView's layer
// delegate action hook is the exact same suppression mechanism as UIView's.
final class PlayerSurfaceView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func makeBackingLayer() -> CALayer { playerLayer }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    // Not an override — unlike UIView, NSView has no concrete base-class implementation of
    // this to override or call super on, only the CALayerDelegate protocol requirement
    // (optional, implicitly satisfied). Returning nil for anything not explicitly suppressed
    // tells CALayer to fall back to its own default action, same effect `super` would have
    // had on UIView.
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        switch event {
        case "bounds", "position", "frame", "transform", "sublayerTransform":
            return NSNull()
        default:
            return nil
        }
    }
}

struct PlayerLayerRepresentable: NSViewRepresentable {
    let player: AVPlayer
    let pip: PiPCoordinator
    var isFillScreen: Bool = false

    func makeNSView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = isFillScreen ? .resizeAspectFill : .resizeAspect
        view.layer?.backgroundColor = NSColor.black.cgColor
        pip.stashLayer(view.playerLayer)
        return view
    }

    func updateNSView(_ nsView: PlayerSurfaceView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        nsView.playerLayer.videoGravity = isFillScreen ? .resizeAspectFill : .resizeAspect
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

/// Closes a player. When the rotate button turned it sideways while the device is held
/// upright, the screen underneath was laid out upright and would show pillarboxed until the
/// rotation caught up after the cover had gone, so the rotation goes first.
func closeRotatedPlayer(_ close: @escaping @MainActor () -> Void) {
    close()
}

// MARK: - Window-level fullscreen

/// SwiftUI on macOS has no `.fullScreenCover` — real fullscreen is a property of the hosting
/// NSWindow. This mounts an invisible, zero-size NSView purely to read `.window` off the
/// view hierarchy once it's attached, then hands it back through a callback (there's no
/// public environment key for "the window this view is in").
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}

func toggleMacWindowFullScreen(_ window: NSWindow?) {
    window?.toggleFullScreen(nil)
}

func isMacWindowFullScreen(_ window: NSWindow?) -> Bool {
    window?.styleMask.contains(.fullScreen) ?? false
}

/// PlayerView is a full-window content overlay (see PlaybackPresenter), not a separate
/// window of its own — the real window's native toolbar (sidebar toggle, back chevron, and
/// whatever toolbar items the screen underneath contributed, e.g. MediaDetailView's favorite
/// button) sits above it and doesn't hide on its own when the player's own on-screen controls
/// fade out for an immersive look. Toggling the toolbar itself keeps both in sync.
func setMacWindowToolbarVisible(_ window: NSWindow?, _ visible: Bool) {
    window?.toolbar?.isVisible = visible
}

// MARK: - AirPlay route picker

/// AVRoutePickerView exists on macOS too, but as a plain NSView with no AVAudioSession to
/// infer routing targets from — it needs the AVPlayer handed to it directly so it knows what
/// to route. Shown as a normal visible button in the controls (see RouteButtonBridge on iOS
/// for why this isn't hidden/triggered the way the iOS one is).
struct AirPlayButton: NSViewRepresentable {
    var player: AVPlayer?

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        view.isRoutePickerButtonBordered = false
        return view
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

/// Keeps the display on or lets it sleep; see keepsScreenAwake.
@MainActor
enum ScreenAwake {
    private static var activity: NSObjectProtocol?

    static func set(_ awake: Bool) {
        if awake, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason: "Video playback")
        } else if !awake, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }
}
