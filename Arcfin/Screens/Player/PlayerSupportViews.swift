// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVFoundation
import AVKit
import Combine
import JellyfinAPI
import MediaEngine
#if canImport(UIKit) && !os(tvOS)
import UIKit
import MediaPlayer
#elseif os(macOS)
import AppKit
#endif
#if canImport(GoogleCast)
import GoogleCast
#endif

// MARK: - Shared playback request

struct PlaybackRequest: Identifiable, Equatable {
    let id = UUID()
    let item: MediaItem
    let startTicks: Int64
}

// MARK: - Cross-platform image typealias

// TrickplayLoader, NowPlayingManager artwork, and OfflinePlayerView's trickplay cropping all
// need a concrete image type — UIImage doesn't exist on macOS, so this is the one place that
// picks the real type per platform and everything else spells `PlatformImage`.
#if canImport(UIKit)
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
public typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    var cgImageRepresentation: CGImage? {
        #if canImport(UIKit)
        return cgImage
        #elseif canImport(AppKit)
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #endif
    }

    static func from(cgImage: CGImage) -> PlatformImage {
        #if canImport(UIKit)
        return PlatformImage(cgImage: cgImage)
        #elseif canImport(AppKit)
        return PlatformImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    static func from(contentsOfFile path: String) -> PlatformImage? {
        #if canImport(UIKit)
        return PlatformImage(contentsOfFile: path)
        #elseif canImport(AppKit)
        return PlatformImage(contentsOfFile: path)
        #endif
    }
}

// MARK: - Skip interval

/// Curated so every option maps to a real SF Symbol — goforward./gobackward. numbered
/// variants only exist for these specific values, not arbitrary integers. (20 was dropped —
/// no numbered symbol exists for it, so it only ever showed the plain unnumbered glyph.)
let skipIntervalOptions = [5, 10, 15, 30, 45, 60]

/// Falls back to the plain (unnumbered) glyph for a value with no matching numbered symbol —
/// shouldn't happen via the Settings picker above, but anyone who already had 20 selected
/// before it was dropped, or a future direct-entry field, could still produce one.
func skipIconName(seconds: Int, forward: Bool) -> String {
    let base = forward ? "goforward" : "gobackward"
    guard skipIntervalOptions.contains(seconds) else { return base }
    return "\(base).\(seconds)"
}

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

// MARK: - Video surface (AVPlayerLayer) + Picture in Picture

#if canImport(UIKit)
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
    #if !os(tvOS)
    let pip: PiPCoordinator
    #endif
    var isFillScreen: Bool = false

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = isFillScreen ? .resizeAspectFill : .resizeAspect
        view.backgroundColor = .black
        #if !os(tvOS)
        pip.stashLayer(view.playerLayer)
        #endif
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = isFillScreen ? .resizeAspectFill : .resizeAspect
    }
}

#elseif os(macOS)

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
#endif

// PiPCoordinator itself is pure AVKit/AVFoundation — no UIView/NSView types — so it's shared
// by both the iOS and macOS surfaces above rather than duplicated. tvOS has no PiP at all.
#if !os(tvOS)
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
        #if os(iOS)
        controller?.canStartPictureInPictureAutomaticallyFromInline = UserDefaults.standard.bool(forKey: "autoPictureInPicture")
        #endif
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
#endif

// MARK: - Rotate button (iOS/iPadOS only — no orientation concept on macOS)

#if canImport(UIKit) && !os(tvOS)
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
#endif

/// Closes a player. When the rotate button turned it sideways while the device is held
/// upright, the screen underneath was laid out upright and would show pillarboxed until the
/// rotation caught up after the cover had gone, so the rotation goes first.
func closeRotatedPlayer(_ close: @escaping @MainActor () -> Void) {
    #if canImport(UIKit) && !os(tvOS)
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
    #else
    close()
    #endif
}

// MARK: - macOS window-level fullscreen

#if os(macOS)
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
#endif

// MARK: - AirPlay / Cast route trigger bridge

#if canImport(UIKit) && !os(tvOS)
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
/// AirPlayButton's macOS variant below.
@MainActor
final class RouteButtonBridge {
    weak var airPlayButton: UIButton?
    weak var castButton: UIButton?

    func fireAirPlay() { airPlayButton?.sendActions(for: .touchUpInside) }
    func fireCast() { castButton?.sendActions(for: .touchUpInside) }
}
#endif

// MARK: - AirPlay route picker

#if canImport(UIKit) && !os(tvOS)
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

#elseif os(macOS)
/// AVRoutePickerView exists on macOS too, but as a plain NSView with no AVAudioSession to
/// infer routing targets from — it needs the AVPlayer handed to it directly so it knows what
/// to route. Shown as a normal visible button in the controls (see the "bridge" note above
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
#endif

// MARK: - Chromecast button

#if canImport(GoogleCast)
struct CastButton: UIViewRepresentable {
    var bridge: RouteButtonBridge = RouteButtonBridge()

    func makeUIView(context: Context) -> GCKUICastButton {
        let view = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        view.tintColor = .white
        bridge.castButton = view
        return view
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
#endif

// MARK: - System volume control (swipe-to-adjust-volume support)

#if canImport(UIKit) && !os(tvOS)
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

extension View {
    /// Keeps the display on while a player is loading, buffering or playing; once paused,
    /// ended or failed the device can sleep as usual.
    func keepsScreenAwake(status: PlaybackStatus) -> some View {
        onAppear { ScreenAwake.set(true) }
            .onChange(of: status) { _, status in
                switch status {
                case .idle, .loading, .playing: ScreenAwake.set(true)
                case .paused, .ended, .failed: ScreenAwake.set(false)
                }
            }
            .onDisappear { ScreenAwake.set(false) }
    }
}

@MainActor
private enum ScreenAwake {
    #if os(macOS)
    private static var activity: NSObjectProtocol?
    #endif

    static func set(_ awake: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = awake
        #elseif os(macOS)
        if awake, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .idleDisplaySleepDisabled, reason: "Video playback")
        } else if !awake, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
        #endif
    }
}

/// The player's spinner. A start or rebuffer that runs past a couple of seconds also says what
/// it's waiting on, so a slow server or connection doesn't look like a frozen app.
struct PlayerLoadingIndicator: View {
    let status: String
    @State private var showsStatus = false

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
            if showsStatus {
                Text(status)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 32)
        .animation(.easeInOut(duration: 0.25), value: showsStatus)
        .animation(.easeInOut(duration: 0.25), value: status)
        .task {
            try? await Task.sleep(for: .seconds(2))
            showsStatus = true
        }
    }
}

/// Fills left to right over an automatic action's countdown, behind the button it belongs to.
struct CountdownFill: View {
    let countdown: PlayerView.AutoActionCountdown
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let progress = min(max(context.date.timeIntervalSince(countdown.startedAt) / countdown.seconds, 0), 1)
            GeometryReader { proxy in
                color.frame(width: proxy.size.width * progress)
            }
        }
        .allowsHitTesting(false)
    }
}
