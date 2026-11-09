// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UIKit
import AVFoundation
import AVKit
import AuthCore
import JellyfinAPI
import MediaEngine
import SwiftVLC
import CastKit
import GroupActivities

struct PlayerView: View {
    let item: MediaItem
    let startPositionTicks: Int64
    let onPlayNext: (MediaItem) -> Void

    @Environment(AuthManager.self) var authManager
    @Environment(MediaRepository.self) var mediaRepo
    @Environment(SyncPlayManager.self) var syncPlayManager
    @Environment(SharePlayManager.self) var sharePlay
    /// Whether a FaceTime call is going, so SharePlay can start straight from the menu.
    @StateObject var groupState = GroupStateObserver()
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.isPlayerWindow) var isPlayerWindow
    @Environment(\.dismissWindow) var dismissWindow
    @Environment(\.openWindow) var openWindow
    @Environment(\.supportsMultipleWindows) var supportsMultipleWindows

    func closePlayer() {
        if isPlayerWindow {
            dismissWindow()
            return
        }
        closeRotatedPlayer { dismiss() }
    }

    @State var model: PlayerModel
    // Separate from isScrubbing/scrubTicks: those track the local player, which is frozen
    // while casting (see castingPlaceholder).
    @State var isCastScrubbing = false
    @State var castScrubTicks: Double = 0
    @State var showTrackMenu = false
    @State var showQualityMenu = false
    @State var showRateMenu = false
    @State var showChapterMenu = false
    @State var showInfoSheet = false
    @State var showSyncPlayMenu = false
    // Per-feature on/off toggles — Settings > Playback > Player Features.
    @AppStorage("chapterListEnabled") var chapterListEnabled = true
    @AppStorage("syncPlayEnabled") var syncPlayEnabled = true
    @AppStorage("castEnabled") var castEnabled = true
    @AppStorage("skipForwardSeconds") var skipForwardSeconds = 10
    @AppStorage("skipBackwardSeconds") var skipBackwardSeconds = 10
    @State var showCastPanel = false
    /// A cast member picked in Cast & Characters; their page opens over the paused player.
    @State var castPanelPerson: MediaPerson?
    @State var audioOnly = false
    @AppStorage("doubleTapToSkip") var doubleTapToSkip = true

    @StateObject var pip = PiPCoordinator()
    @State var vlcPipController: SwiftVLC.PiPController?
    @State var volumeController: SystemVolumeController?
    @State var dragAxis: DragAxis?
    @State var dragBaseline: CGFloat = 0
    @State var dragValue: CGFloat = 0
    @State var lastHapticStep: Int?
    @State var volumeObservation: NSKeyValueObservation?
    /// True while a volume drag gesture is actively driving dragValue — see the
    /// outputVolume observer in setup(), which must ignore its own echo while this is set.
    @State var isDraggingVolume = false
    @State var volumeEchoSuppressTask: Task<Void, Never>?
    @State var displayCriteriaMatcher = DisplayCriteriaMatcher()
    @AppStorage("matchContentFrameRate") var matchContentFrameRate = false
    @AppStorage("swipeGesturesEnabled") var swipeGesturesEnabled = true
    @State var routeBridge = RouteButtonBridge()
    @State var isLandscape = false

    enum DragAxis { case brightness, volume, seek }

    init(item: MediaItem, startPositionTicks: Int64 = 0, onPlayNext: @escaping (MediaItem) -> Void = { _ in }) {
        self.item = item
        self.startPositionTicks = startPositionTicks
        self.onPlayNext = onPlayNext
        _model = State(initialValue: PlayerModel(item: item, startPositionTicks: startPositionTicks, onPlayNext: onPlayNext))
    }

    var body: some View {
        bodyContent.alwaysDarkPlayer()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if CastManager.shared.isConnected {
                // The receiver is playing the video, not this screen — leaving the last
                // local frame frozen behind the controls read as "stuck paused" rather
                // than "actively casting elsewhere", so the surface is swapped for a
                // dedicated placeholder instead.
                castingPlaceholder
            } else {
                videoSurfaceLayer
            }

            if audioOnly {
                PlayerAudioOnlyCover(item: item)
            }

            if let seekFeedback = model.seekFeedback {
                PlayerSeekFeedbackView(feedback: seekFeedback)
            }

            dragAxisIndicator

            // .idle covers the gap between the screen appearing and setup() actually calling
            // player.load() (fetching PlaybackInfo/item detail first) — without it the screen
            // was just black with no spinner for that whole prefetch window.
            if model.errorMessage == nil, model.player.status == .idle || model.player.status == .loading || model.player.isBuffering {
                PlayerLoadingIndicator(status: model.loadingStatusText)
            }

            if let errorMessage = model.errorMessage {
                PlayerErrorView(message: errorMessage) { closePlayer() }
            }

            if let networkToast = model.networkToast {
                PlayerNetworkToast(text: networkToast)
            }

            if let currentSubtitleText = model.currentSubtitleText, !CastManager.shared.isConnected {
                PlayerSubtitleOverlay(text: currentSubtitleText, isControlsVisible: model.isControlsVisible)
            }
            if let currentBitmapCue = model.currentBitmapCue, !CastManager.shared.isConnected {
                PlayerBitmapSubtitleOverlay(cue: currentBitmapCue, isControlsVisible: model.isControlsVisible)
            }

            // Always mounted, visibility driven purely by opacity — this used to be `if
            // isControlsVisible { controlsOverlay }`, which mounts/unmounts a ZStack sibling
            // on every tap. SwiftUI's insertion/removal transition recomputes layout for the
            // whole ZStack while animating (not just this view), and since the video's
            // GeometryReader ignores safe areas while controlsOverlay's own padding doesn't,
            // that recompute briefly disagreed on the effective content region — which is
            // what actually looked like the whole screen (video AND the buttons/text, since
            // both are ZStack siblings sharing that region) zooming in and clipping off
            // screen on every tap. Keeping the view always mounted means there's nothing to
            // insert/remove, so there's no layout pass to get wrong.
            controlsOverlay
                .opacity(model.isControlsVisible && !CastManager.shared.isConnected ? 1 : 0)
                .allowsHitTesting(model.isControlsVisible && !CastManager.shared.isConnected)

            SkipSegmentButton(model: model)

            if model.showUpNext, let nextEpisode = model.nextEpisode {
                UpNextCard(model: model, next: nextEpisode)
            }

            MoreLikeThisPanel(model: model, suggestionsAreHorizontal: isLandscape)
            CastPanel(item: item, castMembers: model.castMembers, isPresented: $showCastPanel) { openCastPanelPerson($0) }

            if model.showStillWatchingPrompt {
                StillWatchingPrompt(model: model)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .keepsScreenAwake(status: model.player.status)
        .onAppear { connectModel() }
        .task { if !model.isAskingToResume { await setup() } }
        .confirmationDialog("Resume Playback?", isPresented: $model.isAskingToResume, titleVisibility: .visible) {
            Button("Resume from \(model.timeLabel(ticks: startPositionTicks))") {
                model.resumeFrom = startPositionTicks
                model.resumeAnswered = true
            }
            Button("Start from Beginning") {
                model.resumeFrom = 0
                model.resumeAnswered = true
            }
            Button("Cancel", role: .cancel) { closePlayer() }
        }
        .onChange(of: model.isAskingToResume) { _, asking in
            if !asking, model.resumeAnswered { Task { await setup() } }
        }
        .onDisappear {
            Task { await teardown() }
            if Self.keepOrientationOnNextDisappear {
                Self.keepOrientationOnNextDisappear = false
            } else {
                resetPlayerOrientation()
            }
        }
        .onChange(of: model.subtitleDelay) { _, _ in model.updateSubtitleText(forTicks: model.player.positionTicks) }
        .onChange(of: model.player.positionTicks) { oldValue, newValue in
            model.positionChanged(from: oldValue, to: newValue)
        }
        .onChange(of: model.player.status) { _, newStatus in
            model.statusChanged(to: newStatus)
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(to: phase)
        }
        .onChange(of: model.isFillScreen) { _, _ in model.applyFillScreen() }
        // These must live on a view that's always mounted, not inside the conditionally
        // -shown controlsOverlay — auto-hide removing that view from the tree while a
        // sheet/dialog was presented from it was tearing the presentation down too.
        .onChange(of: showTrackMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showQualityMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showRateMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showChapterMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showInfoSheet) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .sheet(isPresented: $showTrackMenu) {
            trackSelectionSheet
        }
        .confirmationDialog("Quality", isPresented: $showQualityMenu, titleVisibility: .visible) {
            qualityMenuButtons
        }
        .confirmationDialog("Playback Speed", isPresented: $showRateMenu, titleVisibility: .visible) {
            rateMenuButtons
        }
        .sheet(isPresented: $showChapterMenu) {
            ChapterListSheet(model: model) { showChapterMenu = false }
                // Landscape sheets in .medium can render narrow enough that the drag indicator is
                // the only way to dismiss and hard to grab — an explicit Done button always works.
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(item: $castPanelPerson, onDismiss: { Task { await model.player.play() } }) { person in
            NavigationStack {
                PersonDetailView(person: person)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { castPanelPerson = nil } }
                    }
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            PlayerMediaInfoSheet(model: model) { showInfoSheet = false }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: showSyncPlayMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .sheet(isPresented: $showSyncPlayMenu) {
            SyncPlaySheet(model: model) { showSyncPlayMenu = false }
        }
        .onChange(of: syncPlayManager.incomingCommand) { _, command in
            guard let command else { return }
            model.applySyncPlayCommand(command)
        }
        .onChange(of: sharePlay.incomingCommand) { _, command in
            guard let command else { return }
            model.applySharePlayCommand(command)
        }
        .onChange(of: sharePlay.activityItemId) { _, id in
            guard let id, id != item.id else { return }
            model.followSharePlay(to: id)
        }
        .onChange(of: sharePlay.notice) { _, notice in
            guard let notice else { return }
            model.showSharePlayNotice(notice)
        }
        .onChange(of: CastManager.shared.playbackFinishedCount) { _, _ in
            model.castPlaybackFinished()
        }
        .onChange(of: CastManager.shared.isConnected) { wasConnected, isConnected in
            if isConnected {
                model.startCasting()
            } else if wasConnected {
                model.resumeLocalPlaybackAfterCast()
            }
        }
    }

    var videoSurfaceLayer: some View {
        GeometryReader { proxy in
            videoSurface
                // GeometryReader only proposes its size to a child — it doesn't force
                // it. Without pinning explicitly to proxy.size, the UIViewRepresentable
                // -hosted AVPlayerLayer view is free to size itself off its own content
                // instead of the screen, which is what the "zoom" actually was: the
                // surface's bounds genuinely growing wider than the window, not an
                // animation artifact.
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(tapGesture(width: proxy.size.width))
                .simultaneousGesture(dragGesture(width: proxy.size.width))
                .onChange(of: proxy.size) { _, newSize in
                    isLandscape = newSize.width > newSize.height
                }
                .onAppear { isLandscape = proxy.size.width > proxy.size.height }
        }
        .ignoresSafeArea()
    }

    // AVPlayerLayer hosting and SwiftVLC's plain VideoView both work on every platform; only
    // the PiP-specific PiPVideoView path is iOS/macOS-only (SwiftVLC itself only compiles
    // PiPVideoView for iOS/AppKit, not tvOS).
    @ViewBuilder
    var videoSurface: some View {
        if let avPlayer = model.player as? AVFoundationPlayer {
            PlayerLayerRepresentable(player: avPlayer.player, pip: pip, isFillScreen: model.isFillScreen)
        } else if let vlcEngine = model.player as? VLCEnginePlayer {
            // Unlike AVFoundation's inert PlayerSurfaceView, PiPVideoView's native drawable
            // is itself interactive and was swallowing taps before our own tapGesture saw
            // them (single tap was toggling play/pause instead of the controls overlay).
            // PiP is driven entirely through our own button, not by touching the video, so
            // hit-testing on the surface itself is safe to turn off.
            PiPVideoView(vlcEngine.vlcPlayer, controller: $vlcPipController,
                         startsAutomaticallyFromInline: UserDefaults.standard.bool(forKey: "autoPictureInPicture"),
                         managesAudioSession: false)
                .allowsHitTesting(false)
        } else if let aetherEngine = model.player as? AetherEnginePlayer {
            // AetherEngineVideoSurface binds the engine directly (engine.bind(view:)
            // internally) — no layer/controller to hand it, unlike the AVFoundation/VLC
            // branches above.
            AetherEngineVideoSurface(player: aetherEngine)
                .allowsHitTesting(false)
        }
    }

    /// Only where it works: VLC's own PiP, or AVFoundation/Aether through an AVPlayerLayer
    /// (not Aether's software route).
    var canPictureInPicture: Bool {
        model.player is VLCEnginePlayer ? vlcPipController != nil : pip.isSupported
    }

    func togglePiP() {
        if model.player is VLCEnginePlayer {
            vlcPipController?.toggle()
        } else {
            pip.toggle()
        }
    }

    // MARK: - Setup / teardown

    /// Hands the model this screen's environment and the steps only the iPhone and iPad take.
    private func connectModel() {
        model.attach(authManager: authManager, mediaRepo: mediaRepo, syncPlayManager: syncPlayManager,
                     sharePlay: sharePlay, scenePhase: scenePhase)
        model.closePlayer = { closePlayer() }
        model.playbackStarted = { playbackStarted() }
        model.streamReloaded = {
            if let avPlayer = model.player as? AVFoundationPlayer {
                avPlayer.player.currentItem?.externalMetadata = airPlayExternalMetadata()
            }
        }
        model.engineReleased = { pip.detach() }
        model.replacementEngineStarting = {
            for _ in 0..<30 where model.player.status != .playing {
                try? await Task.sleep(for: .milliseconds(500))
            }
            if model.player is AVFoundationPlayer { pip.activateIfNeeded() }
        }
    }

    private func setup() async {
        volumeController = SystemVolumeController()
        // Playback stalling (buffer underrun) is the standard signal for "network can't
        // keep up" — auto-step quality down when the user hasn't manually picked one.
        model.stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: nil, queue: .main
        ) { [model = model] _ in
            Task { @MainActor in model.handlePlaybackStall() }
        }
        // AVAudioSession's setCategory/setActive are synchronous, blocking calls — Xcode's
        // Hang Risk diagnostic flags calling them on the main thread. The async activate()
        // API needs iOS 27 (min target here is 26), so instead this just runs the same
        // synchronous calls off the main actor via a detached task.
        await activateAudioSession()
        // The hidden MPVolumeView used to set volume programmatically also silently
        // suppresses the system's own volume HUD — observe outputVolume so physical
        // button presses still get a visible indicator via our own overlay. The gesture in
        // dragGesture(width:) drives the SAME outputVolume through volumeController, so
        // without the isDraggingVolume guard this observer's own echo of that call kept
        // overwriting dragValue mid-drag with a quantized, async-delayed system value —
        // the touch tracked smoothly but the displayed % randomly jumped away from it.
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor in
                guard !isDraggingVolume else { return }
                dragAxis = .volume
                dragValue = CGFloat(newValue)
                try? await Task.sleep(for: .seconds(1.2))
                if dragAxis == .volume { dragAxis = nil }
            }
        }
        await model.setup()
    }

    /// Picture in picture, frame-rate matching and the AirPlay receiver's Now Playing card,
    /// once the stream is playing.
    private func playbackStarted() {
        // VLC's PiPVideoView wires PiP up itself (see videoSurface) — only AVFoundation's
        // custom PiPCoordinator needs this explicit activation step.
        if let avPlayer = model.player as? AVFoundationPlayer {
            pip.activateIfNeeded()
            // Display-criteria (refresh rate) matching is only exposed through
            // AVPlayerViewController's display manager — no macOS equivalent.
            if matchContentFrameRate {
                displayCriteriaMatcher.attach(player: avPlayer.player)
            }
            // Drives what an AirPlay-receiving device (Apple TV etc.) shows on its own
            // Now Playing card — separate from MPNowPlayingInfoCenter, which
            // drives the sending device's own lock screen/Control Center.
            // AVPlayerItem.externalMetadata doesn't exist on macOS at all (iOS/iPadOS/
            // Mac Catalyst/tvOS/visionOS only, confirmed against Apple's own docs) —
            // not a priority to work around given macOS's own system-level AirPlay
            // mirroring already covers this.
            avPlayer.player.currentItem?.externalMetadata = airPlayExternalMetadata()
        } else if let aetherPlayer = model.player as? AetherEnginePlayer {
            // nativePlayerLayer only exists on Aether's .remoteBypass/.loopback routes
            // (both still ultimately AVPlayer/AVPlayerLayer under the hood) — the same
            // PiPCoordinator AVFoundationPlayer uses works unmodified against it. The
            // .software route's own softwarePiPSource (sample-buffer based, not an
            // AVPlayerLayer at all) needs a materially different AVPictureInPicture
            // ContentSource-based coordinator — deliberately not implemented here yet;
            // PiP is simply unavailable for a session that routes to software.
            if let layer = aetherPlayer.nativePlayerLayer {
                pip.stashLayer(layer)
                pip.activateIfNeeded()
            }
        }
    }

    /// AirPlay-receiving hardware (Apple TV etc.) draws its own Now Playing card straight off
    /// the AVPlayerItem's embedded metadata, not off MPNowPlayingInfoCenter — without this an
    /// AirPlayed title showed only generic/blank info on the TV side.
    private func airPlayExternalMetadata() -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = model.item.name as NSString
        titleItem.extendedLanguageTag = "und"
        items.append(titleItem)
        if let subtitle = model.episodeSubtitle {
            let artistItem = AVMutableMetadataItem()
            artistItem.identifier = .commonIdentifierArtist
            artistItem.value = subtitle as NSString
            artistItem.extendedLanguageTag = "und"
            items.append(artistItem)
        }
        return items
    }

    private func teardown() async {
        model.stopTasks()
        model.leaveSyncPlayOnClose()
        volumeController?.teardown()
        volumeObservation?.invalidate()
        volumeEchoSuppressTask?.cancel()
        displayCriteriaMatcher.detach()
        await model.stopPlayback()
        await deactivateAudioSession()
        model.detachViewSteps()
    }

    private func activateAudioSession() async {
        await Task.detached(priority: .userInitiated) {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                // Not fatal — playback still works, just without the routing/background
                // guarantees .playback gives (this is also what PiP relies on being correct).
            }
        }.value
    }

    private func deactivateAudioSession() async {
        await Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }.value
    }
}
