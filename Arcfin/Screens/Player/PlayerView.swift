import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import AVFoundation
import AVKit
import AuthCore
import JellyfinAPI
import MediaEngine
import SwiftVLC
import CastKit

struct PlayerView: View {
    let item: MediaItem
    let startPositionTicks: Int64
    let onPlayNext: (MediaItem) -> Void

    @Environment(AuthManager.self) var authManager
    @Environment(MediaRepository.self) var mediaRepo
    @Environment(SyncPlayManager.self) var syncPlayManager
    @Environment(PlaybackPresenter.self) var playbackPresenter
    @Environment(\.dismiss) var dismiss

    /// SwiftUI's own dismiss only does anything for a real .sheet/.fullScreenCover
    /// presentation — on macOS this view is a plain full-window ZStack overlay in
    /// ContentView instead (see PlaybackPresenter's own doc comment for why), so closing it
    /// there means clearing the shared presenter's request, not calling dismiss at all.
    func closePlayer() {
        #if os(macOS)
        playbackPresenter.dismiss()
        #else
        dismiss()
        #endif
    }

    @State var player: any MediaPlayerProtocol = AVFoundationPlayer()
    @AppStorage("playbackEngine") var playbackEnginePreference = PlaybackEngineKind.auto
    @State var playbackInfo: JellyfinPlaybackInfo?
    @State var errorMessage: String?
    @State var isControlsVisible = true
    @State var hideControlsTask: Task<Void, Never>?
    @State var isScrubbing = false
    @State var scrubTicks: Double = 0
    @State var showTrackMenu = false
    @State var showQualityMenu = false
    @State var showRateMenu = false
    @State var showChapterMenu = false
    @State var showInfoSheet = false
    @State var showSyncPlayMenu = false
    @State var syncPlayGroupNameInput = ""
    @State var isSyncPlayBusy = false
    // Per-feature on/off toggles — Settings > Playback > Player Features.
    @AppStorage("chapterListEnabled") var chapterListEnabled = true
    @AppStorage("syncPlayEnabled") var syncPlayEnabled = true
    @AppStorage("castEnabled") var castEnabled = true
    @AppStorage("stillWatchingPromptEnabled") var stillWatchingPromptEnabled = true
    @AppStorage("skipForwardSeconds") var skipForwardSeconds = 10
    @AppStorage("skipBackwardSeconds") var skipBackwardSeconds = 10
    @State var quality: VideoQuality
    @State var selectedAudioIndex: Int?
    @State var selectedSubtitleIndex: Int?
    @State var subtitleCues: [SubtitleCue] = []
    @State var currentSubtitleText: String?
    @AppStorage("subtitleTextSize") var subtitleTextSize = SubtitleTextSize.medium
    @AppStorage("subtitleTextColor") var subtitleTextColor = SubtitleTextColorOption.white
    @AppStorage("subtitleBackgroundStyle") var subtitleBackgroundStyle = SubtitleBackgroundStyle.outline
    @State var trickplayLoader: TrickplayLoader?
    @State var scrubThumbnail: PlatformImage?
    @State var lastThumbnailBucket: Int?
    @State var introEnd: Double?
    @State var creditsStart: Double?
    @State var recapEnd: Double?
    @State var progressReportTask: Task<Void, Never>?
    @State var seekFeedback: SeekFeedback?
    /// Optimistic target of the most recent seek request — player.positionTicks only
    /// updates once the AVPlayer seek actually completes, which lags behind on a slow
    /// server. Rapid skip taps must accumulate on this, not on the stale confirmed
    /// position, or they collapse into far less than the sum requested.
    @State var pendingSeekTargetTicks: Int64?
    @State var stallObserver: NSObjectProtocol?
    /// Index into `Self.autoBitrateLadder`, nil = uncapped. Only meaningful while
    /// `quality == .auto` — a manual pick never touches this.
    @State var autoLadderIndex: Int?
    @State var lastStallHandledAt: Date?
    @State var recentStallTimestamps: [Date] = []
    @State var lastLoadStartedAt: Date?
    @State var networkToast: String?
    @State var chapters: [MediaChapter] = []
    @State var nextEpisode: MediaItem?
    @State var showUpNext = false
    @State var upNextDismissed = false
    @State var upNextCountdown: Task<Void, Never>?
    @State var showStillWatchingPrompt = false
    @State var pendingAutoAdvanceEpisode: MediaItem?
    @State var stillWatchingTimeoutTask: Task<Void, Never>?

    #if !os(tvOS)
    @StateObject var pip = PiPCoordinator()
    @State var vlcPipController: SwiftVLC.PiPController?
    @State var isPiPSupported = AVPictureInPictureController.isPictureInPictureSupported()
    @State var nowPlayingManager = NowPlayingManager()
    #endif
    // Not PiP-specific — used by videoSurface's own aspect-fill toggle, which is
    // meaningful on tvOS too even though PiP itself isn't available there.
    @State var isFillScreen = false
    #if canImport(UIKit) && !os(tvOS)
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
    @State var routeBridge = RouteButtonBridge()
    @State var isLandscape = false
    #endif
    #if os(macOS)
    @State var macWindow: NSWindow?
    @State var isMacFullScreen = false
    @State var macVolume: Double = 1.0
    @State var macVolumeHUD: Double?
    @State var macVolumeHUDTask: Task<Void, Never>?
    @FocusState var isPlayerFocused: Bool
    @State var lastMacHoverLocation: CGPoint?
    #endif

    let client = JellyfinMediaClient()

    enum DragAxis { case brightness, volume }
    struct SeekFeedback: Identifiable, Equatable {
        let id = UUID()
        let forward: Bool
        /// Which side of the screen was actually tapped — kept separate from `forward` so the
        /// indicator's on-screen position is driven by where the tap landed, not by which
        /// direction that tap happens to seek.
        let onRight: Bool
        /// Forward and backward can be configured to different skip amounts (Settings >
        /// Playback), so the indicator has to show whichever one this particular tap used.
        let seconds: Int
    }

    init(item: MediaItem, startPositionTicks: Int64 = 0, onPlayNext: @escaping (MediaItem) -> Void = { _ in }) {
        self.item = item
        self.startPositionTicks = startPositionTicks
        self.onPlayNext = onPlayNext
        _quality = State(initialValue: VideoQuality(rawValue: UserDefaults.standard.string(forKey: "videoQuality") ?? "") ?? .max)
    }

    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if !os(tvOS)
            if CastManager.shared.isConnected {
                // The receiver is playing the video, not this screen — leaving the last
                // local frame frozen behind the controls read as "stuck paused" rather
                // than "actively casting elsewhere", so the surface is swapped for a
                // dedicated placeholder instead.
                castingPlaceholder
                    .ignoresSafeArea()
            } else {
                videoSurfaceLayer
            }
            #else
            videoSurfaceLayer
            #endif

            if let seekFeedback {
                seekFeedbackView(seekFeedback)
            }

            #if canImport(UIKit) && !os(tvOS)
            dragAxisIndicator
            #elseif os(macOS)
            if let macVolumeHUD {
                macVolumeIndicator(macVolumeHUD)
            }
            #endif

            // .idle covers the gap between the screen appearing and setup() actually calling
            // player.load() (fetching PlaybackInfo/item detail first) — without it the screen
            // was just black with no spinner for that whole prefetch window.
            if errorMessage == nil, player.status == .idle || player.status == .loading || player.isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            if let errorMessage {
                errorView(errorMessage)
            }

            if let networkToast {
                networkToastView(networkToast)
            }

            if let currentSubtitleText {
                subtitleOverlay(currentSubtitleText)
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
                .opacity(isControlsVisible ? 1 : 0)
                .allowsHitTesting(isControlsVisible)

            skipButton

            if showUpNext, let nextEpisode {
                upNextCard(nextEpisode)
            }

            if showStillWatchingPrompt {
                stillWatchingOverlay
            }

            #if os(macOS)
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
            #endif
        }
        #if canImport(UIKit) && !os(tvOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .task { await setup() }
        .onDisappear {
            Task { await teardown() }
            #if canImport(UIKit) && !os(tvOS)
            resetPlayerOrientation()
            #elseif os(macOS)
            macVolumeHUDTask?.cancel()
            #endif
        }
        .onChange(of: player.positionTicks) { _, newValue in
            updateSubtitleText(forTicks: newValue)
            checkUpNextThreshold(positionTicks: newValue)
            #if !os(tvOS)
            updateNowPlayingInfo()
            #endif
        }
        .onChange(of: player.status) { _, newStatus in
            handleStatusChange(newStatus)
            #if !os(tvOS)
            updateNowPlayingInfo()
            #endif
        }
        #if !os(tvOS)
        .onChange(of: isFillScreen) { _, _ in applyFillScreen() }
        #endif
        #if os(macOS)
        .background(WindowAccessor { window in
            macWindow = window
            isMacFullScreen = isMacWindowFullScreen(window)
        })
        .focusable()
        .focusEffectDisabled()
        .focused($isPlayerFocused)
        .onAppear { isPlayerFocused = true }
        .onChange(of: isControlsVisible) { _, visible in setMacWindowToolbarVisible(macWindow, visible) }
        // The specific-key overload (.space, .leftArrow, etc.) takes a zero-argument
        // () -> KeyPress.Result closure, unlike the characters: overload below, which takes
        // (KeyPress) -> KeyPress.Result — `{ _ in ... }` only compiles for the latter.
        .onKeyPress(.space) { togglePlayPause(); return .handled }
        .onKeyPress(.leftArrow) { seek(by: -skipBackwardSeconds); return .handled }
        .onKeyPress(.rightArrow) { seek(by: skipForwardSeconds); return .handled }
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
        #endif
        // These must live on a view that's always mounted, not inside the conditionally
        // -shown controlsOverlay — auto-hide removing that view from the tree while a
        // sheet/dialog was presented from it was tearing the presentation down too.
        .onChange(of: showTrackMenu) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        .onChange(of: showQualityMenu) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        .onChange(of: showRateMenu) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        .onChange(of: showChapterMenu) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        .onChange(of: showInfoSheet) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        #if !os(macOS)
        .sheet(isPresented: $showTrackMenu) {
            trackSelectionSheet
        }
        #endif
        .confirmationDialog("Quality", isPresented: $showQualityMenu, titleVisibility: .visible) {
            qualityMenuButtons
        }
        .confirmationDialog("Playback Speed", isPresented: $showRateMenu, titleVisibility: .visible) {
            rateMenuButtons
        }
        #if !os(macOS)
        .sheet(isPresented: $showChapterMenu) {
            chapterListSheet
        }
        #endif
        .sheet(isPresented: $showInfoSheet) {
            mediaInfoSheet
        }
        #if !os(tvOS)
        .onChange(of: showSyncPlayMenu) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        .sheet(isPresented: $showSyncPlayMenu) {
            syncPlaySheet
        }
        .onChange(of: syncPlayManager.incomingCommand) { _, command in
            guard let command else { return }
            applySyncPlayCommand(command)
        }
        #endif
        #if canImport(GoogleCast)
        .onChange(of: CastManager.shared.isConnected) { wasConnected, isConnected in
            if isConnected {
                startCasting()
            } else if wasConnected {
                resumeLocalPlaybackAfterCast()
            }
        }
        #endif
    }

    // Extracted out of body so the #if !os(tvOS)/#else branches there can each reference it
    // once instead of splitting a single if/else statement's opening and closing braces
    // across two separate #if regions — that had equal open/close brace and #if/#endif
    // counts overall but still didn't compile: each #if region has to be independently
    // well-formed on its own, and an incomplete if-statement inside one region isn't, even
    // when a later, separate #if with the identical condition supplies the rest of it.
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
                #if canImport(UIKit) && !os(tvOS)
                .gesture(tapGesture(width: proxy.size.width))
                .simultaneousGesture(dragGesture(width: proxy.size.width))
                .onChange(of: proxy.size) { _, newSize in
                    isLandscape = newSize.width > newSize.height
                }
                .onAppear { isLandscape = proxy.size.width > proxy.size.height }
                #elseif os(macOS)
                // Mouse/keyboard equivalents of the touch gestures above — click
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
                #endif
        }
        .ignoresSafeArea()
    }

    // Was entirely #if !os(tvOS) before — tvOS never got a real video rendering surface
    // at all (playback "worked" in the sense that a PlayerView opened, but no video ever
    // showed). AVPlayerLayer hosting and SwiftVLC's plain VideoView both work fine on
    // tvOS; only the PiP-specific PiPVideoView path is genuinely iOS/macOS-only (SwiftVLC
    // itself only compiles PiPVideoView for #if os(iOS)/AppKit, not tvOS).
    @ViewBuilder
    var videoSurface: some View {
        if let avPlayer = player as? AVFoundationPlayer {
            #if os(tvOS)
            PlayerLayerRepresentable(player: avPlayer.player, isFillScreen: isFillScreen)
            #else
            PlayerLayerRepresentable(player: avPlayer.player, pip: pip, isFillScreen: isFillScreen)
            #endif
        } else if let vlcEngine = player as? VLCEnginePlayer {
            #if os(tvOS)
            VideoView(vlcEngine.vlcPlayer)
                .allowsHitTesting(false)
            #else
            // Unlike AVFoundation's inert PlayerSurfaceView, PiPVideoView's native drawable
            // is itself interactive and was swallowing taps before our own tapGesture saw
            // them (single tap was toggling play/pause instead of the controls overlay).
            // PiP is driven entirely through our own button, not by touching the video, so
            // hit-testing on the surface itself is safe to turn off.
            PiPVideoView(vlcEngine.vlcPlayer, controller: $vlcPipController, managesAudioSession: false)
                .allowsHitTesting(false)
            #endif
        }
    }

    func applyFillScreen() {
        if let vlcEngine = player as? VLCEnginePlayer {
            vlcEngine.vlcPlayer.aspectRatio = isFillScreen ? .fill : .default
        }
        // AVFoundation's videoGravity is driven declaratively via videoSurface's
        // isFillScreen param above — no imperative call needed for that branch.
    }

    #if !os(tvOS)
    func togglePiP() {
        if player is VLCEnginePlayer {
            vlcPipController?.toggle()
        } else {
            pip.toggle()
        }
    }
    #endif

    private func handleStatusChange(_ newStatus: PlaybackStatus) {
        if newStatus == .playing { scheduleAutoHide() }
        if newStatus == .ended { Task { await finishPlayback() } }
    }

    // MARK: - Now Playing / AirPlay metadata

    #if !os(tvOS)
    /// Reflects Cast state too — the local player stays paused for the whole cast session
    /// (see startCasting), so its own `.status` alone would show "paused" the entire time.
    var isEffectivelyPlaying: Bool {
        #if canImport(GoogleCast)
        if CastManager.shared.isConnected { return !CastManager.shared.isPaused }
        #endif
        return player.status == .playing
    }

    func nowPlayingPlay() {
        #if canImport(GoogleCast)
        if CastManager.shared.isConnected { CastManager.shared.play(); return }
        #endif
        Task { await player.play() }
    }

    func nowPlayingPause() {
        #if canImport(GoogleCast)
        if CastManager.shared.isConnected { CastManager.shared.pause(); return }
        #endif
        Task { await player.pause() }
    }

    private func setUpNowPlayingCommandsIfNeeded() {
        nowPlayingManager.configureCommands(
            isPlaying: { isEffectivelyPlaying },
            onPlay: nowPlayingPlay,
            onPause: nowPlayingPause,
            onSkip: { seconds in seek(by: seconds) },
            onSeek: { seconds in performSeek(to: Int64(seconds * 10_000_000)) },
            onNextTrack: item.type == .episode ? { playNextEpisode() } : nil
        )
    }

    private func updateNowPlayingInfo() {
        let durationSeconds = Double(player.durationTicks) / 10_000_000
        guard durationSeconds > 0 else { return }
        nowPlayingManager.update(
            title: item.name,
            artist: episodeSubtitle,
            duration: durationSeconds,
            elapsed: Double(player.positionTicks) / 10_000_000,
            rate: isEffectivelyPlaying ? player.playbackRate : 0,
            artwork: nowPlayingArtwork
        )
    }

    @MainActor private static var artworkCache: [String: PlatformImage] = [:]
    private var nowPlayingArtwork: PlatformImage? { Self.artworkCache[item.id] }

    private func fetchAndApplyNowPlayingArtwork() async {
        guard nowPlayingArtwork == nil,
              let url = mediaRepo.imageURL(for: item, type: .primary, fillWidth: 600),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = PlatformImage(data: data)
        else { return }
        Self.artworkCache[item.id] = image
        updateNowPlayingInfo()
    }

    /// AirPlay-receiving hardware (Apple TV etc.) draws its own Now Playing card straight off
    /// the AVPlayerItem's embedded metadata, not off MPNowPlayingInfoCenter — without this an
    /// AirPlayed title showed only generic/blank info on the TV side.
    private func airPlayExternalMetadata() -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = item.name as NSString
        titleItem.extendedLanguageTag = "und"
        items.append(titleItem)
        if let subtitle = episodeSubtitle {
            let artistItem = AVMutableMetadataItem()
            artistItem.identifier = .commonIdentifierArtist
            artistItem.value = subtitle as NSString
            artistItem.extendedLanguageTag = "und"
            items.append(artistItem)
        }
        return items
    }
    #endif

    private func handleMenuVisibilityChange(_ isOpen: Bool) {
        if isOpen {
            hideControlsTask?.cancel()
        } else {
            scheduleAutoHide()
        }
    }

    @ViewBuilder
    private var trackSelectionSheet: some View {
        NavigationStack {
            TrackSelectionSheet(
                audioStreams: playbackInfo?.audioStreams ?? [],
                subtitleStreams: playbackInfo?.subtitleStreams ?? [],
                selectedAudioIndex: selectedAudioIndex,
                selectedSubtitleIndex: selectedSubtitleIndex,
                onSelectAudio: { index in
                    showTrackMenu = false
                    changeTrack(audioIndex: index)
                },
                onSelectSubtitle: { index in
                    showTrackMenu = false
                    changeTrack(subtitleIndex: .some(index))
                }
            )
            .navigationTitle("Subtitles & Audio")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTrackMenu = false }
                }
            }
        }
        // Landscape sheets in .medium can render narrow enough that the drag indicator is
        // the only way to dismiss and hard to grab — an explicit Done button always works.
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    @ViewBuilder
    private var qualityMenuButtons: some View {
        // Don't offer a resolution the source can't actually supply (e.g. 4K for a 1080p
        // source) — Jellyfin would just upscale into a bigger, pointless transcode.
        let sourceHeight = playbackInfo?.videoStream?.height
        ForEach(VideoQuality.allCases.filter { q in
            guard let minHeight = q.minSourceHeight, let sourceHeight else { return true }
            return sourceHeight >= minHeight
        }) { q in
            Button(q.label + (q == quality ? " ✓" : "")) { changeQuality(to: q) }
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Playback speed

    static let rateOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    @ViewBuilder
    private var rateMenuButtons: some View {
        ForEach(Self.rateOptions, id: \.self) { rate in
            Button(rateLabel(rate) + (rate == player.playbackRate ? " ✓" : "")) {
                Task { await player.setRate(rate) }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "Normal" : "\(rate.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", rate) : String(format: "%.2f", rate))×"
    }

    // MARK: - Setup / teardown

    private func setup() async {
        #if canImport(UIKit) && !os(tvOS)
        volumeController = SystemVolumeController()
        // Playback stalling (buffer underrun) is the standard signal for "network can't
        // keep up" — auto-step quality down when the user hasn't manually picked one.
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in handlePlaybackStall() }
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
        #endif
        guard let credential, let authHeader else {
            errorMessage = "Not signed in."
            return
        }
        if quality == .auto {
            await primeAutoLadder(credential: credential, authHeader: authHeader)
        }
        do {
            var info = try await client.getPlaybackInfo(
                credential: credential, authHeader: authHeader, itemId: item.id,
                quality: qualityCap(for: quality)
            )
            // .choose always resolves Auto down to a concrete engine — only two outcomes here.
            let engine = PlaybackEngineSelector.choose(
                preference: playbackEnginePreference, container: info.container, videoCodec: info.videoStream?.codec
            )
            if engine == .vlc, !(player is VLCEnginePlayer) {
                player = VLCEnginePlayer()
            } else if engine == .avFoundation, !(player is AVFoundationPlayer) {
                player = AVFoundationPlayer()
            }
            selectedAudioIndex = info.defaultAudioStreamIndex
            // The server only marks a subtitle default when one's flagged default/forced
            // there — most libraries don't have that set, so "Show Subtitles by Default"
            // needs its own fallback to the first available track rather than staying nil.
            if let serverDefault = info.defaultSubtitleStreamIndex {
                selectedSubtitleIndex = serverDefault
            } else if UserDefaults.standard.bool(forKey: "subtitleDefault") {
                selectedSubtitleIndex = info.subtitleStreams.first?.index
            } else {
                selectedSubtitleIndex = nil
            }
            // Settings > Playback's global language defaults only steer this very first
            // pick, and only when a track in that language actually exists — a later
            // change always goes through changeTrack()/reload() instead.
            var languagePreferenceApplied = false
            let preferredAudioLang = UserDefaults.standard.string(forKey: "preferredAudioLanguage") ?? ""
            if !preferredAudioLang.isEmpty,
               let match = info.audioStreams.first(where: { $0.language == preferredAudioLang }),
               match.index != selectedAudioIndex {
                selectedAudioIndex = match.index
                languagePreferenceApplied = true
            }
            let preferredSubtitleLang = UserDefaults.standard.string(forKey: "preferredSubtitleLanguage") ?? ""
            if !preferredSubtitleLang.isEmpty,
               let match = info.subtitleStreams.first(where: { $0.language == preferredSubtitleLang }),
               match.index != selectedSubtitleIndex {
                selectedSubtitleIndex = match.index
                languagePreferenceApplied = true
            }
            // Jellyfin negotiates audio/subtitle selection server-side (see changeTrack) —
            // a language default that actually changed the pick needs the same re-fetch
            // with explicit indices before the very first play, not just a local index change.
            if languagePreferenceApplied, let reInfo = try? await client.getPlaybackInfo(
                credential: credential, authHeader: authHeader, itemId: item.id,
                quality: qualityCap(for: quality),
                audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex
            ) {
                info = reInfo
            }
            playbackInfo = info
            // PlaybackInfo's own TrickplayInfo field isn't reliably populated by Jellyfin —
            // the general item-detail endpoint's Trickplay field (keyed by MediaSourceId) is
            // what the official apps actually read it from.
            let detail = try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: item.id)
            if let trickplay = detail?.trickplay[info.mediaSourceId] ?? info.trickplay {
                trickplayLoader = TrickplayLoader(credential: credential, authHeader: authHeader, client: client, itemId: item.id, info: trickplay)
            }
            chapters = detail?.chapters ?? []
            await loadSubtitleCues(from: info, credential: credential)
            lastLoadStartedAt = Date()
            try await player.load(url: info.playURL, startPositionTicks: startPositionTicks)
            await player.play()
            #if !os(tvOS)
            // VLC's PiPVideoView wires PiP up itself (see videoSurface) — only AVFoundation's
            // custom PiPCoordinator needs this explicit activation step.
            if let avPlayer = player as? AVFoundationPlayer {
                pip.activateIfNeeded()
                #if canImport(UIKit)
                // Display-criteria (refresh rate) matching is only exposed through
                // AVPlayerViewController's display manager — no macOS equivalent.
                if matchContentFrameRate {
                    displayCriteriaMatcher.attach(player: avPlayer.player)
                }
                #endif
                #if !os(macOS)
                // Drives what an AirPlay-receiving device (Apple TV etc.) shows on its own
                // Now Playing card — separate from MPNowPlayingInfoCenter below, which
                // drives the sending device's own lock screen/Control Center.
                // AVPlayerItem.externalMetadata doesn't exist on macOS at all (iOS/iPadOS/
                // Mac Catalyst/tvOS/visionOS only, confirmed against Apple's own docs) —
                // not a priority to work around given macOS's own system-level AirPlay
                // mirroring already covers this.
                avPlayer.player.currentItem?.externalMetadata = airPlayExternalMetadata()
                #endif
            }
            setUpNowPlayingCommandsIfNeeded()
            updateNowPlayingInfo()
            Task { await fetchAndApplyNowPlayingArtwork() }
            #endif
            await client.reportPlaybackStart(credential: credential, authHeader: authHeader,
                                             itemId: item.id, mediaSourceId: info.mediaSourceId,
                                             positionTicks: startPositionTicks)
            startProgressReporting(mediaSourceId: info.mediaSourceId)
        } catch {
            errorMessage = "Couldn't start playback: \(error.localizedDescription)"
        }

        if item.type == .episode {
            let segments = await client.getSkipSegments(credential: credential, authHeader: authHeader, itemId: item.id)
            introEnd = segments.introEnd
            creditsStart = segments.creditsStart
            recapEnd = segments.recapEnd

            if let seriesId = item.seriesId {
                let upNext = try? await client.getNextUp(credential: credential, authHeader: authHeader, seriesId: seriesId, limit: 1)
                nextEpisode = upNext?.first
            }
        }
    }

    // MARK: - SyncPlay

    #if !os(tvOS)
    /// Applies a command that came back over the WebSocket — the one and only place local
    /// playback state actually changes in response to SyncPlay, whether this client sent
    /// the original request or another group member did.
    private func applySyncPlayCommand(_ command: SyncPlayCommand) {
        switch command.kind {
        case .play:
            Task { await player.play() }
        case .pause:
            Task { await player.pause() }
        case .seek, .stop:
            if let ticks = command.positionTicks {
                Task { await player.seek(to: ticks) }
            }
        }
    }
    #endif

    // MARK: - Chromecast

    #if canImport(GoogleCast)
    /// A Cast session took over — the receiver plays the stream itself, so the local
    /// player pauses rather than playing the same thing twice.
    private func startCasting() {
        guard let url = playbackInfo?.playURL else { return }
        Task { await player.pause() }
        let posterURL = mediaRepo.imageURL(for: item, type: .primary, fillWidth: 400)
        CastManager.shared.loadMedia(
            streamURL: url, title: item.name, subtitle: nil, posterImageURL: posterURL,
            contentType: castContentType(for: playbackInfo?.container),
            startPositionSeconds: Double(player.positionTicks) / 10_000_000
        )
    }

    /// The session ended — pick local playback back up from wherever the receiver had
    /// gotten to. `currentPositionSeconds()` reads the live session and is already nil by
    /// the time this runs (the session is gone), so this uses CastManager's own
    /// continuously-updated `lastKnownPositionSeconds` instead — see its doc comment.
    private func resumeLocalPlaybackAfterCast() {
        if let seconds = CastManager.shared.lastKnownPositionSeconds {
            Task {
                await player.seek(to: Int64(seconds * 10_000_000))
                await player.play()
            }
        } else {
            Task { await player.play() }
        }
    }

    private func castContentType(for container: String?) -> String {
        switch (container ?? "").lowercased() {
        case "m3u8": return "application/x-mpegurl"
        case "mov":  return "video/quicktime"
        default:     return "video/mp4"
        }
    }
    #endif

    private func teardown() async {
        progressReportTask?.cancel()
        hideControlsTask?.cancel()
        stillWatchingTimeoutTask?.cancel()
        #if os(macOS)
        // The window's toolbar is real window chrome, not part of this view — left hidden,
        // it would stay hidden on whatever screen is underneath once the player closes.
        setMacWindowToolbarVisible(macWindow, true)
        #endif
        #if !os(tvOS)
        // Closing the player closes the group too — an orphaned WebSocket connection with
        // nobody watching isn't useful, and simpler than trying to keep it alive across
        // whatever the user navigates to next.
        if syncPlayManager.isInGroup, let credential = authManager.state.credential {
            syncPlayManager.leaveGroup(credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken))
        }
        #endif
        #if canImport(UIKit) && !os(tvOS)
        volumeController?.teardown()
        volumeObservation?.invalidate()
        volumeEchoSuppressTask?.cancel()
        displayCriteriaMatcher.detach()
        #endif
        #if !os(tvOS)
        nowPlayingManager.clear()
        #endif
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        if let credential, let authHeader, let info = playbackInfo {
            await client.reportPlaybackStopped(credential: credential, authHeader: authHeader,
                                               itemId: item.id, mediaSourceId: info.mediaSourceId,
                                               positionTicks: player.positionTicks)
        }
        await player.stop()
        #if canImport(UIKit) && !os(tvOS)
        await deactivateAudioSession()
        #endif
    }

    #if canImport(UIKit) && !os(tvOS)
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
    #endif

    func finishPlayback() async {
        guard let credential, let authHeader else { return }
        _ = try? await client.markWatched(credential: credential, authHeader: authHeader, itemId: item.id, watched: true)
        closePlayer()
    }

    private func startProgressReporting(mediaSourceId: String) {
        progressReportTask?.cancel()
        progressReportTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let credential, let authHeader else { continue }
                await client.reportPlaybackProgress(
                    credential: credential, authHeader: authHeader, itemId: item.id,
                    mediaSourceId: mediaSourceId, positionTicks: player.positionTicks,
                    isPaused: player.status == .paused
                )
            }
        }
    }

    // MARK: - Quality

    /// Fine-grained fallback steps for Auto — used both as the starting point (picked from
    /// a bandwidth probe) and as the reactive stall-downgrade ladder. Deliberately finer
    /// than the manual picker's four resolution tiers so a bad connection degrades gracefully
    /// instead of jumping straight to 480p.
    static let autoBitrateLadder: [StreamQualityCap] = [
        StreamQualityCap(maxBitrate: 8_000_000, maxWidth: 1920),
        StreamQualityCap(maxBitrate: 4_000_000, maxWidth: 1280),
        StreamQualityCap(maxBitrate: 2_000_000, maxWidth: 960),
        StreamQualityCap(maxBitrate: 1_000_000, maxWidth: 720),
        StreamQualityCap(maxBitrate: 500_000, maxWidth: 480),
        StreamQualityCap(maxBitrate: 250_000, maxWidth: 426),
    ]

    private func qualityCap(for quality: VideoQuality) -> StreamQualityCap {
        // No forceTranscode — a picked quality is a cap, not a demand to re-encode.
        // If the source already qualifies for direct play under that cap, it should stay
        // direct play (forcing a transcode there was wasteful and confusing: Jellyfin's own
        // dashboard correctly said Direct Play while this app's badge said Transcoding).
        if quality == .auto {
            if let autoLadderIndex, autoLadderIndex < Self.autoBitrateLadder.count {
                return Self.autoBitrateLadder[autoLadderIndex]
            }
            return .auto
        }
        switch quality {
        case .max, .auto: return .auto
        case .p4k:   return StreamQualityCap(maxBitrate: 100_000_000, maxWidth: 3840)
        case .p1080: return StreamQualityCap(maxBitrate: 20_000_000, maxWidth: 1920)
        case .p720:  return StreamQualityCap(maxBitrate: 8_000_000, maxWidth: 1280)
        case .p480:  return StreamQualityCap(maxBitrate: 1_500_000, maxWidth: 854)
        }
    }

    /// Probes actual throughput via Jellyfin's own bandwidth-test endpoint and picks a
    /// starting ladder step from it, instead of always starting uncapped and finding out
    /// the connection is slow only after a stall-storm. A generous 25% safety margin below
    /// the measured rate covers overhead and fluctuation; a failed/timed-out probe (e.g. a
    /// genuinely poor connection) falls back to the lowest step rather than uncapped.
    private func primeAutoLadder(credential: ServerCredential, authHeader: String) async {
        guard let measuredBps = await client.testBitrate(credential: credential, authHeader: authHeader) else {
            autoLadderIndex = Self.autoBitrateLadder.count - 1
            return
        }
        let safe = Double(measuredBps) * 0.75
        // Comfortably above the ladder's top step — plenty of bandwidth, let the source's
        // real bitrate through uncapped instead of pinning it to the ladder's ceiling.
        guard let topBitrate = Self.autoBitrateLadder.first?.maxBitrate, safe < Double(topBitrate) else {
            autoLadderIndex = nil
            return
        }
        autoLadderIndex = Self.autoBitrateLadder.firstIndex { Double($0.maxBitrate ?? 0) <= safe }
    }

    func changeQuality(to newQuality: VideoQuality) {
        guard newQuality != quality else { return }
        quality = newQuality
        recentStallTimestamps.removeAll()
        lastStallHandledAt = nil
        if newQuality == .auto {
            guard let credential, let authHeader else { reload(errorContext: "switch quality"); return }
            Task {
                await primeAutoLadder(credential: credential, authHeader: authHeader)
                reload(errorContext: "switch quality")
            }
        } else {
            reload(errorContext: "switch quality")
        }
    }

    /// Only acts while on Auto — a deliberate manual pick (including "Max") is never
    /// silently overridden by this.
    ///
    /// AVPlayerItemPlaybackStalled fires for plenty of non-network reasons too (seeking,
    /// a reload's own startup buffering, backgrounding) — a single stall is not a reliable
    /// "network can't keep up" signal on its own, and reacting to one caused a reload loop
    /// twice (each reload's startup buffering looked like another stall). Now requires
    /// several stalls clustered in a short window, which normal one-off blips don't produce.
    func handlePlaybackStall() {
        guard quality == .auto else { return }
        if let lastLoad = lastLoadStartedAt, Date().timeIntervalSince(lastLoad) < 12 { return }

        let now = Date()
        recentStallTimestamps.append(now)
        recentStallTimestamps.removeAll { now.timeIntervalSince($0) > 15 }
        guard recentStallTimestamps.count >= 3 else { return }
        recentStallTimestamps.removeAll()

        if let last = lastStallHandledAt, now.timeIntervalSince(last) < 30 { return }
        let nextIndex = (autoLadderIndex ?? -1) + 1
        guard nextIndex < Self.autoBitrateLadder.count else {
            // The ladder's exhausted and it's STILL stalling repeatedly — that's not a
            // bandwidth problem a lower bitrate can fix (already tried every step), it's
            // something else entirely (a codec/output failure, a dead source, etc.). Silently
            // returning here left the video frozen on a spinner forever with zero feedback —
            // surface it instead of pretending nothing's wrong.
            lastStallHandledAt = now
            errorMessage = "Playback keeps stalling and lowering quality hasn't helped — this source may not play correctly with the current playback engine. Try Settings > Playback > Playback Engine to switch to VLC."
            return
        }
        lastStallHandledAt = now
        autoLadderIndex = nextIndex
        reload(errorContext: "adjust quality")
        let mbps = Double(Self.autoBitrateLadder[nextIndex].maxBitrate ?? 0) / 1_000_000
        networkToast = "Lowered to \(mbps >= 1 ? String(format: "%.0f Mb/s", mbps) : String(format: "%.0f Kb/s", mbps * 1000)) — your connection can't keep up"
        Task {
            try? await Task.sleep(for: .seconds(3))
            networkToast = nil
        }
    }

    // MARK: - Up Next

    private func checkUpNextThreshold(positionTicks: Int64) {
        guard nextEpisode != nil, !upNextDismissed, player.durationTicks > 0 else { return }
        let remainingSeconds = Double(player.durationTicks - positionTicks) / 10_000_000
        let withinWindow = remainingSeconds <= 30 && remainingSeconds > 0
        if withinWindow, !showUpNext {
            showUpNext = true
            if UserDefaults.standard.bool(forKey: "autoPlayNext") {
                startUpNextCountdown()
            }
        } else if !withinWindow, showUpNext {
            showUpNext = false
            upNextCountdown?.cancel()
        }
    }

    private func startUpNextCountdown() {
        upNextCountdown?.cancel()
        upNextCountdown = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            playNextEpisode(isAutomatic: true)
        }
    }

    /// `isAutomatic` distinguishes the 8s countdown silently firing from the user actually
    /// tapping Play on the Up Next card — only the former counts toward the "are you still
    /// watching" streak (a manual tap is proof someone's there, and resets it).
    func playNextEpisode(isAutomatic: Bool = false) {
        guard let nextEpisode else { return }
        upNextCountdown?.cancel()
        if isAutomatic, stillWatchingPromptEnabled {
            let streak = UserDefaults.standard.integer(forKey: Self.autoplayStreakKey) + 1
            UserDefaults.standard.set(streak, forKey: Self.autoplayStreakKey)
            if streak >= Self.stillWatchingThreshold {
                pendingAutoAdvanceEpisode = nextEpisode
                showStillWatchingPrompt = true
                Task { await player.pause() }
                scheduleStillWatchingTimeout()
                return
            }
        } else {
            UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        }
        onPlayNext(nextEpisode)
    }

    // MARK: - Are you still watching

    static let stillWatchingThreshold = 3
    static let autoplayStreakKey = "arcfin.autoplayStreak"

    /// No response within 60s reads the same as nobody being there — stop rather than
    /// leave a paused, forgotten stream open indefinitely.
    private func scheduleStillWatchingTimeout() {
        stillWatchingTimeoutTask?.cancel()
        stillWatchingTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            stopAfterStillWatchingPrompt()
        }
    }

    func continueAfterStillWatchingPrompt() {
        stillWatchingTimeoutTask?.cancel()
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        showStillWatchingPrompt = false
        if let pendingAutoAdvanceEpisode {
            onPlayNext(pendingAutoAdvanceEpisode)
        }
        pendingAutoAdvanceEpisode = nil
    }

    func stopAfterStillWatchingPrompt() {
        stillWatchingTimeoutTask?.cancel()
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        showStillWatchingPrompt = false
        pendingAutoAdvanceEpisode = nil
        closePlayer()
    }

    func dismissUpNext() {
        upNextDismissed = true
        showUpNext = false
        upNextCountdown?.cancel()
    }

    // MARK: - Audio/subtitle tracks

    /// Jellyfin negotiates audio/subtitle selection server-side (transcoded streams often
    /// carry only one audio track, external subtitles aren't muxed into the asset at all) —
    /// AVMediaSelectionGroup on the local asset can't reflect that, so a track change reloads
    /// via a fresh PlaybackInfo call with the new stream index, same as a quality change.
    func changeTrack(audioIndex: Int? = nil, subtitleIndex: Int?? = nil) {
        if let audioIndex { selectedAudioIndex = audioIndex }
        if let subtitleIndex { selectedSubtitleIndex = subtitleIndex }
        reload(errorContext: "switch track")
    }

    private func loadSubtitleCues(from info: JellyfinPlaybackInfo, credential: ServerCredential) async {
        guard let index = selectedSubtitleIndex,
              let stream = info.subtitleStreams.first(where: { $0.index == index }),
              let deliveryUrl = stream.deliveryUrl
        else {
            subtitleCues = []
            currentSubtitleText = nil
            return
        }
        subtitleCues = await SubtitleLoader.loadCues(deliveryUrl: deliveryUrl, credential: credential)
    }

    func updateSubtitleText(forTicks ticks: Int64) {
        guard !subtitleCues.isEmpty else {
            currentSubtitleText = nil
            return
        }
        currentSubtitleText = SubtitleLoader.cue(at: Double(ticks) / 10_000_000, in: subtitleCues)
    }

    private func reload(errorContext: String) {
        guard let credential, let authHeader else { return }
        let resumeTicks = player.positionTicks
        Task {
            do {
                let info = try await client.getPlaybackInfo(
                    credential: credential, authHeader: authHeader, itemId: item.id,
                    quality: qualityCap(for: quality),
                    audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex
                )
                playbackInfo = info
                await loadSubtitleCues(from: info, credential: credential)
                lastLoadStartedAt = Date()
                try await player.load(url: info.playURL, startPositionTicks: resumeTicks)
                await player.play()
                #if !os(tvOS)
                #if !os(macOS)
                if let avPlayer = player as? AVFoundationPlayer {
                    avPlayer.player.currentItem?.externalMetadata = airPlayExternalMetadata()
                }
                #endif
                updateNowPlayingInfo()
                #endif
                startProgressReporting(mediaSourceId: info.mediaSourceId)
            } catch {
                errorMessage = "Couldn't \(errorContext): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Controls visibility

    func scheduleAutoHide() {
        hideControlsTask?.cancel()
        #if os(tvOS)
        // Auto-hiding relied on the remote's directional pad landing on a fallback
        // focusable root view once every control dropped out of the focus chain — but
        // tvOS's focus engine doesn't reliably migrate focus to a "last one standing"
        // fallback just because it's still technically focusable; it can just as easily
        // leave nothing focused at all, which is indistinguishable from "the remote does
        // nothing and nothing is visibly selectable" — exactly what was reported. Simplest
        // correct fix: controls just don't auto-hide on tvOS at all, so there's never a
        // hidden state to need recovering from in the first place.
        return
        #else
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, player.status == .playing else { return }
            withAnimation(DT.Animation.fast) { isControlsVisible = false }
        }
        #endif
    }

    func toggleControls() {
        withAnimation(DT.Animation.fast) { isControlsVisible.toggle() }
        if isControlsVisible { scheduleAutoHide() }
    }
}
