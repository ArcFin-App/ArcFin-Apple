// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AppKit
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
    @Environment(PlaybackPresenter.self) var playbackPresenter
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.isPlayerWindow) var isPlayerWindow
    @Environment(\.dismissWindow) var dismissWindow
    @Environment(\.openWindow) var openWindow
    @Environment(\.supportsMultipleWindows) var supportsMultipleWindows

    /// SwiftUI's own dismiss only does anything for a real .sheet/.fullScreenCover
    /// presentation — on macOS this view is a plain full-window ZStack overlay in
    /// ContentView instead (see PlaybackPresenter's own doc comment for why), so closing it
    /// there means clearing the shared presenter's request, not calling dismiss at all.
    func closePlayer() {
        if isPlayerWindow {
            dismissWindow()
            return
        }
        playbackPresenter.dismiss()
    }

    @State var model: PlayerModel
    @State var showTrackMenu = false
    @State var showQualityMenu = false
    @State var showRateMenu = false
    @State var showChapterMenu = false
    @State var showInfoSheet = false
    @State var showSyncPlayMenu = false
    // Per-feature on/off toggles — Settings > Playback > Player Features.
    @AppStorage("chapterListEnabled") var chapterListEnabled = true
    @AppStorage("syncPlayEnabled") var syncPlayEnabled = true
    @AppStorage("skipForwardSeconds") var skipForwardSeconds = 10
    @AppStorage("skipBackwardSeconds") var skipBackwardSeconds = 10
    @State var showCastPanel = false
    /// A cast member picked in Cast & Characters; their page opens over the paused player.
    @State var castPanelPerson: MediaPerson?
    @State var audioOnly = false
    @AppStorage("doubleTapToSkip") var doubleTapToSkip = true

    @StateObject var pip = PiPCoordinator()
    @State var vlcPipController: SwiftVLC.PiPController?
    @State var macWindow: NSWindow?
    @State var isMacFullScreen = false
    @State var macVolume: Double = 1.0
    /// Watches for the right arrow being let go while it holds playback at speed.
    @State var arrowReleaseMonitor: Any?
    @State var macVolumeHUD: Double?
    @State var macVolumeBeforeMute: Double?
    @State var macVolumeHUDTask: Task<Void, Never>?
    @FocusState var isPlayerFocused: Bool
    @State var lastMacHoverLocation: CGPoint?

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

            videoSurfaceLayer

            if audioOnly {
                PlayerAudioOnlyCover(item: item)
            }
            PlayerRadioCover(model: model)

            if let seekFeedback = model.seekFeedback {
                PlayerSeekFeedbackView(feedback: seekFeedback)
            }

            if let macVolumeHUD {
                macVolumeIndicator(macVolumeHUD)
            }

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
            SpeedBoostBadge(model: model)

            if model.showUpNext, let nextEpisode = model.nextEpisode {
                UpNextCard(model: model, next: nextEpisode)
            }

            MoreLikeThisPanel(model: model, suggestionsAreHorizontal: true)
            CastPanel(item: item, castMembers: model.castMembers, isPresented: $showCastPanel) { openCastPanelPerson($0) }
            PlayerChannelListLayer(model: model)

            if model.showStillWatchingPrompt {
                StillWatchingPrompt(model: model)
            }

            // .sheet doesn't reliably present here — PlayerView is a raw full-window ZStack
            // overlay in ContentView (see PlaybackPresenter), not a screen reached through a
            // real NavigationStack push or .sheet/.fullScreenCover presentation, and macOS's
            // sheet machinery needs that normal presentation chain to attach to. Rendered as
            // a plain in-place overlay instead — the same mechanism the volume HUD above
            // already uses successfully in this exact context.
            if showTrackMenu {
                macMenuBackdrop { showTrackMenu = false }
                macTrackSelectionPanel
            }
            if showChapterMenu {
                macMenuBackdrop { showChapterMenu = false }
                macChapterListPanel
            }
        }
        .keepsScreenAwake(status: model.player.status)
        .onAppear { connectModel() }
        .task { if !model.isAskingToResume { await model.setup() } }
        .alert("Resume Playback?", isPresented: $model.isAskingToResume) {
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
            if !asking, model.resumeAnswered { Task { await model.setup() } }
        }
        .onDisappear {
            Task { await teardown() }
            macVolumeHUDTask?.cancel()
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
        .background(WindowAccessor { window in
            macWindow = window
            isMacFullScreen = isMacWindowFullScreen(window)
        })
        .focusable()
        .focusEffectDisabled()
        .focused($isPlayerFocused)
        .onAppear { isPlayerFocused = true }
        .onChange(of: model.isControlsVisible) { _, visible in setMacWindowToolbarVisible(macWindow, visible) }
        // The specific-key overload (.space, .leftArrow, etc.) takes a zero-argument
        // () -> KeyPress.Result closure, unlike the characters: overload below, which takes
        // (KeyPress) -> KeyPress.Result — `{ _ in ... }` only compiles for the latter.
        .onKeyPress(.space) { model.togglePlayPause(); return .handled }
        // On a channel there's nothing to seek in, so the arrows change channel.
        .onKeyPress(.leftArrow) {
            if model.isLive { model.playPrevious() } else { model.seek(by: -skipBackwardSeconds) }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if model.isLive { model.playNextEpisode() } else { macSkip(1) }
            return .handled
        }
        .onKeyPress(.upArrow) { adjustMacVolume(by: 0.05); return .handled }
        .onKeyPress(.downArrow) { adjustMacVolume(by: -0.05); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "fF")) { _ in
            toggleMacWindowFullScreen(macWindow)
            return .handled
        }
        .onKeyPress(.escape) {
            if isMacFullScreen {
                toggleMacWindowFullScreen(macWindow)
            } else {
                closePlayer()
            }
            return .handled
        }
        .focusedSceneValue(\.playerCommands, PlayerCommands(
            isPlaying: playPauseIconIsPlaying,
            togglePlay: { model.togglePlayPause() },
            skip: { macSkip($0) },
            volume: { adjustMacVolume(by: $0) },
            toggleFullScreen: { toggleMacWindowFullScreen(macWindow) },
            close: { closePlayer() },
            isMuted: macVolume == 0,
            toggleMute: { toggleMacMute() },
            hasSubtitles: !(model.playbackInfo?.subtitleStreams.isEmpty ?? true),
            subtitlesOn: model.selectedSubtitleIndex != nil,
            toggleSubtitles: { model.toggleSubtitles() },
            showTracks: { showTrackMenu = true },
            showInfo: { showInfoSheet = true },
            stepSpeed: { model.stepPlaybackRate($0) },
            resetSpeed: { model.choosePlaybackRate(1) },
            skipSegmentLabel: model.currentSkippable?.label,
            skipSegment: { model.skipToSegmentEnd() },
            next: model.nextEpisode == nil ? nil : { model.playNextEpisode() },
            previous: model.previousItem == nil ? nil : { model.playPrevious() }
        ))
        // These must live on a view that's always mounted, not inside the conditionally
        // -shown controlsOverlay — auto-hide removing that view from the tree while a
        // sheet/dialog was presented from it was tearing the presentation down too.
        .onChange(of: showTrackMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showQualityMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showRateMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showChapterMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showInfoSheet) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .confirmationDialog("Quality", isPresented: $showQualityMenu, titleVisibility: .visible) {
            qualityMenuButtons
        }
        .confirmationDialog("Playback Speed", isPresented: $showRateMenu, titleVisibility: .visible) {
            rateMenuButtons
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
    }

    var videoSurfaceLayer: some View {
        GeometryReader { proxy in
            videoSurface
                // GeometryReader only proposes its size to a child — it doesn't force
                // it. Without pinning explicitly to proxy.size, the NSViewRepresentable
                // -hosted AVPlayerLayer view is free to size itself off its own content
                // instead of the screen, which is what the "zoom" actually was: the
                // surface's bounds genuinely growing wider than the window, not an
                // animation artifact.
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                // Mouse/keyboard equivalents of the touch gestures — click
                // toggles controls the same as a tap, double-click seeks ±10s, and
                // moving the mouse re-reveals controls the way a touch tap does
                // (there's no "tap" on a pointer-driven surface, so hover is the
                // signal instead).
                .gesture(macTapGesture(width: proxy.size.width))
                // onContinuousHover fires on more than just genuine pointer movement
                // (real mouse hardware reports sub-pixel jitter even "at rest," and
                // the video surface fills the whole window) — reacting to every call
                // kept resetting the auto-hide timer nonstop, so controls (and the
                // window toolbar, which follows them) never actually hid. Only actual
                // position changes count as activity now.
                .onContinuousHover { phase in
                    guard case .active(let location) = phase, location != lastMacHoverLocation else { return }
                    lastMacHoverLocation = location
                    handleMacMouseActivity()
                }
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

    /// Hands the model this screen's environment and the steps only the Mac takes.
    private func connectModel() {
        model.attach(authManager: authManager, mediaRepo: mediaRepo, syncPlayManager: syncPlayManager,
                     sharePlay: sharePlay, scenePhase: scenePhase)
        model.closePlayer = { closePlayer() }
        model.playbackStarted = { playbackStarted() }
        model.engineReleased = { pip.detach() }
        model.replacementEngineStarting = {
            for _ in 0..<30 where model.player.status != .playing {
                try? await Task.sleep(for: .milliseconds(500))
            }
            if model.player is AVFoundationPlayer { pip.activateIfNeeded() }
        }
    }

    /// Picture in picture, once the stream is playing.
    private func playbackStarted() {
        // VLC's PiPVideoView wires PiP up itself (see videoSurface) — only AVFoundation's
        // custom PiPCoordinator needs this explicit activation step.
        if model.player is AVFoundationPlayer {
            pip.activateIfNeeded()
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

    private func teardown() async {
        model.stopTasks()
        // The window's toolbar is real window chrome, not part of this view — left hidden,
        // it would stay hidden on whatever screen is underneath once the player closes.
        setMacWindowToolbarVisible(macWindow, true)
        model.leaveSyncPlayOnClose()
        await model.stopPlayback()
        model.detachViewSteps()
    }
}
