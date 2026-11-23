// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UIKit
import AVFoundation
import AVKit
import AuthCore
import JellyfinAPI
import MediaEngine
import Persistence
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
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled

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
    /// The AirPlay device the video is on, while it's on one.
    @State var airPlayRoute: String?
    @State var airPlayScrubTicks: Double?
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
    @AppStorage("ignoreEdgeSwipes") var ignoreEdgeSwipes = true
    @State var routeBridge = RouteButtonBridge()
    @State var isLandscape = false

    enum DragAxis { case brightness, volume, seek }

    init(item: MediaItem, startPositionTicks: Int64 = 0, source: (any PlaybackSource)? = nil,
         onPlayNext: @escaping (MediaItem) -> Void = { _ in }) {
        self.item = item
        self.startPositionTicks = startPositionTicks
        self.onPlayNext = onPlayNext
        _model = State(initialValue: PlayerModel(item: item, startPositionTicks: startPositionTicks, onPlayNext: onPlayNext,
                                                 source: source))
    }

    /// A download, played from its file with the details saved beside it. Up Next and
    /// Previous move between the show's downloaded episodes.
    init(download: DownloadedItem, startPositionOverride: Int64? = nil, onPlayNext: @escaping (DownloadedItem) -> Void = { _ in }) {
        let source = DownloadPlaybackSource(downloadedItem: download, startPositionOverride: startPositionOverride)
        self.init(item: source.item, source: source) { next in
            if let nextDownload = source.download(for: next.id) { onPlayNext(nextDownload) }
        }
    }

    /// A video picked from Files.
    init(fileURL: URL) {
        let source = FilePlaybackSource(url: fileURL)
        self.init(item: source.item, source: source)
    }

    var body: some View {
        bodyContent.alwaysDarkPlayer()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlaybackPositionObserver(player: model.player) { model.positionChanged(from: $0, to: $1) }

            if model.isCasting {
                // The receiver is playing the video, not this screen — leaving the last
                // local frame frozen behind the controls read as "stuck paused" rather
                // than "actively casting elsewhere", so the surface is swapped for a
                // dedicated placeholder instead.
                castingPlaceholder
            } else {
                videoSurfaceLayer
                // The video is on an AirPlay device: a controller for it here, as when
                // casting, instead of controls over a blank video area.
                if let airPlayRoute {
                    airPlayScreen(route: airPlayRoute)
                }
            }

            if audioOnly {
                PlayerAudioOnlyCover(item: item)
            }
            PlayerRadioCover(model: model)

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
                PlayerErrorView(message: errorMessage, retry: model.retry,
                                nextChannel: model.isLive && model.nextEpisode != nil ? { model.playNextEpisode() } : nil) {
                    closePlayer()
                }
            }

            if let networkToast = model.networkToast {
                PlayerNetworkToast(text: networkToast)
            }

            if let currentSubtitleText = model.currentSubtitleText, !model.isCasting {
                PlayerSubtitleOverlay(text: currentSubtitleText, isControlsVisible: model.isControlsVisible)
            }
            if let currentBitmapCue = model.currentBitmapCue, !model.isCasting {
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
                .opacity(model.isControlsVisible && !model.isCasting && airPlayRoute == nil ? 1 : 0)
                .allowsHitTesting(model.isControlsVisible && !model.isCasting && airPlayRoute == nil)

            SkipSegmentButton(model: model, controlsShown: model.isControlsVisible && !model.isCasting && airPlayRoute == nil)
            SpeedBoostBadge(model: model)

            if model.showUpNext, let nextEpisode = model.nextEpisode {
                UpNextCard(model: model, next: nextEpisode)
            }

            MoreLikeThisPanel(model: model, suggestionsAreHorizontal: isLandscape)
            CastPanel(item: item, castMembers: model.castMembers, isPresented: $showCastPanel,
                      photoURL: model.localCastPhotoURL,
                      onSelect: model.capabilities.personPages ? { openCastPanelPerson($0) } : nil)
            PlayerChannelListLayer(model: model)

            if model.showStillWatchingPrompt {
                StillWatchingPrompt(model: model)
            }
        }
        .task { await watchAirPlay() }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // With swipes allowed right to the edges, the player's swipes come before Control
        // Center, Notification Center and the Home gesture, which then take a second swipe.
        .defersSystemGestures(on: swipeGesturesEnabled && !ignoreEdgeSwipes ? .vertical : [])
        .keepsScreenAwake(status: model.player.status)
        .onAppear {
            model.viewAppeared()
            connectModel()
            applyOpeningOrientation()
        }
        .task {
            if model.handOffToDefaultPlayer() { closePlayer(); return }
            await model.resolveStartPosition()
            guard !Task.isCancelled else { return }
            if !model.isAskingToResume { await setup() }
        }
        .alert("Resume Playback?", isPresented: $model.isAskingToResume) {
            Button("Resume from \(model.timeLabel(ticks: model.startPositionTicks))") {
                model.resumeFrom = model.startPositionTicks
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
            model.viewDisappeared { await teardown() }
            if Self.keepOrientationOnNextDisappear {
                Self.keepOrientationOnNextDisappear = false
            } else {
                resetPlayerOrientation()
            }
        }
        .onChange(of: model.subtitleDelay) { _, _ in model.updateSubtitleText(forTicks: model.player.positionTicks) }
        .onChange(of: model.player.status) { _, newStatus in
            model.statusChanged(to: newStatus)
        }
        .onChange(of: model.player.isBuffering) { _, isBuffering in
            model.bufferingChanged(isBuffering)
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(to: phase)
        }
        .onChange(of: model.isFillScreen) { _, _ in model.applyFillScreen() }
        .onChange(of: voiceOverEnabled, initial: true) { _, enabled in model.keepsControlsVisible = enabled }
        .accessibilityAction(.magicTap) { model.togglePlayPause() }
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
        .onChange(of: RemoteControl.shared.command) { _, command in
            guard let command else { return }
            if command.kind == .stop { closePlayer() } else { model.applyRemoteCommand(command.kind) }
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
            guard model.capabilities.casting else { return }
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
                .simultaneousGesture(dragGesture(size: proxy.size))
                .simultaneousGesture(holdForSpeedGesture)
                // The gestures above have no VoiceOver equivalent of their own.
                .accessibilityElement()
                .accessibilityLabel("Show playback controls")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.toggleControlsVisibilityOnAction() }
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
        // The AirPlay receiver's card follows a channel onto its next programme.
        model.liveProgramChanged = {
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
        // AVAudioSession's setCategory/setActive are synchronous, blocking calls — Xcode's
        // Hang Risk diagnostic flags calling them on the main thread. The async activate()
        // API needs iOS 27 (min target here is 26), so instead this just runs the same
        // synchronous calls off the main actor via a detached task.
        await activateAudioSession()
        // Closed meanwhile: the teardown has already run, so nothing would remove the observer.
        guard !Task.isCancelled, !model.isClosed else { return }
        // The hidden MPVolumeView used to set volume programmatically also silently
        // suppresses the system's own volume HUD — observe outputVolume so physical
        // button presses still get a visible indicator via our own overlay. The gesture in
        // dragGesture(width:) drives the SAME outputVolume through volumeController, so
        // without the isDraggingVolume guard this observer's own echo of that call kept
        // overwriting dragValue mid-drag with a quantized, async-delayed system value —
        // the touch tracked smoothly but the displayed % randomly jumped away from it.
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.old, .new]) { _, change in
            guard let newValue = change.newValue else { return }
            let wasMuted = (change.oldValue ?? 1) < 0.01, isMuted = newValue < 0.01
            Task { @MainActor in
                if wasMuted != isMuted { model.soundMutedChanged(isMuted) }
                guard !isDraggingVolume else { return }
                dragAxis = .volume
                dragValue = CGFloat(newValue)
                try? await Task.sleep(for: .seconds(1.2))
                if dragAxis == .volume { dragAxis = nil }
            }
        }
        await model.startSetup()
        // Opened with the sound already off: the observer above only hears changes.
        if AVAudioSession.sharedInstance().outputVolume < 0.01 { model.soundMutedChanged(true) }
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
        // The stop reports can take seconds, by when the next title (or another window's
        // player) may be playing in the same session; deactivating it would stop its sound.
        if !model.handedOver, !PlayerActivity.shared.isPlayerOpen { await deactivateAudioSession() }
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

extension PlayerView {
    /// Whether the video went to an AirPlay device, and which. AVFoundation sends the video
    /// itself, and so does Aether on its native route, through an AVPlayer of its own; its
    /// software route and VLC keep the picture here and send only the sound.
    func watchAirPlay() async {
        var toldPictureStaysHere = false
        while !Task.isCancelled {
            let aether = model.player as? AetherEnginePlayer
            let avPlayer = (model.player as? AVFoundationPlayer)?.player ?? aether?.nativePlayerLayer?.player
            let external = avPlayer?.isExternalPlaybackActive ?? false
            let name = AVAudioSession.sharedInstance().currentRoute.outputs
                .first { $0.portType == .airPlay }?.portName
            // AirPlay picked from the video player is taken as a screen. Left unsaid, Aether keeps
            // Dolby Vision with an enhancement layer and interlaced video here and sends the sound.
            aether?.setAirPlayReceiverShowsVideo(name != nil)
            let route = external ? (name ?? String(localized: "AirPlay")) : nil
            if route != airPlayRoute { withAnimation(DT.Animation.fast) { airPlayRoute = route } }
            // Decoded in software: nothing can send this picture, so say why the TV shows none.
            let staysHere = aether?.airPlayPictureStaysLocal ?? false
            if staysHere, !toldPictureStaysHere {
                model.showSharePlayNotice(String(localized: "AirPlay is playing the sound only. This video is decoded on this device, so its picture can’t be sent."))
            }
            toldPictureStaysHere = staysHere
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
