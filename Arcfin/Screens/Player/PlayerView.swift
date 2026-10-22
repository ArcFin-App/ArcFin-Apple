// SPDX-License-Identifier: AGPL-3.0-or-later

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
    #if os(tvOS)
    // A separate flag, not reusing isControlsVisible — the latter also drives
    // allowsHitTesting below, which must stay true always on tvOS. This only ever changes
    // opacity, so hit-testing/focusability never turns off and there's never a moment with
    // nothing reachable for the remote to bring back, even while fully invisible.
    @State var tvControlsHidden = false
    #endif
    @State var hideControlsTask: Task<Void, Never>?
    @State var isScrubbing = false
    @State var scrubTicks: Double = 0
    // Separate from isScrubbing/scrubTicks: those track the local player, which is frozen
    // while casting (see castingPlaceholder).
    @State var isCastScrubbing = false
    @State var castLoadTask: Task<Void, Never>?
    @State var sleepTimerTask: Task<Void, Never>?
    @State var sleepTimerEndsAt: Date?
    @State var sleepAtEndOfItem = false
    @State var tracksAtCastStart: (audio: Int?, subtitle: Int?)?
    @State var castSubtitleTrackIDs: Set<Int> = []
    @State var castScrubTicks: Double = 0
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
    @State var lastSubtitleIndex: Int?
    /// Seconds subtitles are shifted later (+) or earlier (-) — for sources whose subtitle
    /// timing doesn't match the cut being played. Not persisted: it's per-viewing.
    @State var subtitleDelay: Double = 0
    @State var currentSubtitleText: String?
    /// Only ever non-nil on AetherEnginePlayer — a native embedded PGS/DVB bitmap track has
    /// no Jellyfin delivery URL for SubtitleLoader to fetch, so this is genuinely new
    /// capability, not a duplicate of the text-cue path above.
    @State var currentBitmapCue: NativeBitmapCue?
    @AppStorage("subtitleTextSize") var subtitleTextSize = SubtitleTextSize.medium
    @AppStorage("subtitleTextColor") var subtitleTextColor = SubtitleTextColorOption.white
    @AppStorage("subtitleBackgroundStyle") var subtitleBackgroundStyle = SubtitleBackgroundStyle.outline
    @State var trickplayLoader: TrickplayLoader?
    @State var scrubThumbnail: PlatformImage?
    @State var lastThumbnailBucket: Int?
    /// Intro, recap, credits and preview spans from the server's segment plugins.
    @State var segments = SkipSegments()
    /// Segments already skipped automatically, so seeking back into one lets it play.
    @State var autoSkipped: Set<String> = []
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
    @State var castMembers: [MediaPerson] = []
    /// The version picked for a title with several (Merge Versions); nil plays the server's first.
    @State var selectedMediaSourceId: String?
    @State var showXRay = false
    /// A cast member picked in X-Ray; their page opens over the paused player.
    @State var xRayPerson: MediaPerson?
    @State var audioOnly = false
    /// Set when the player is about to be replaced by the next title in the same cover, so
    /// the outgoing instance doesn't unlock the orientation the viewer had chosen.
    static var keepOrientationOnNextDisappear = false
    @State var moreLikeThis: [MediaItem] = []
    @State var currentLikes: Bool?
    @State var showMoreLikeThis = false
    @State var moreLikeThisDismissed = false
    @State var nextEpisode: MediaItem?
    /// The title before this one in the queue or the series, for the Previous button.
    @State var previousItem: MediaItem?
    @State var showUpNext = false
    @State var upNextDismissed = false
    @State var upNextCountdown: Task<Void, Never>?
    @AppStorage("doubleTapToSkip") var doubleTapToSkip = true
    /// Where playback starts: the resume point, or the beginning under Start Over.
    @State var resumeFrom: Int64 = 0
    /// Settings › Playback › When Resuming is Ask, and the answer isn't in yet.
    @State var isAskingToResume = false
    @State var resumeAnswered = false
    @State var showStillWatchingPrompt = false
    @State var pendingAutoAdvanceEpisode: MediaItem?
    @State var stillWatchingTimeoutTask: Task<Void, Never>?

    #if !os(tvOS)
    @StateObject var pip = PiPCoordinator()
    @State var vlcPipController: SwiftVLC.PiPController?
    #endif
    @State var nowPlayingManager = NowPlayingManager()
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
    @AppStorage("swipeGesturesEnabled") var swipeGesturesEnabled = true
    @State var routeBridge = RouteButtonBridge()
    @State var isLandscape = false
    #endif
    #if os(macOS)
    @State var macWindow: NSWindow?
    @State var isMacFullScreen = false
    @State var macVolume: Double = 1.0
    @State var macVolumeHUD: Double?
    @State var macVolumeBeforeMute: Double?
    @State var macVolumeHUDTask: Task<Void, Never>?
    @FocusState var isPlayerFocused: Bool
    @State var lastMacHoverLocation: CGPoint?
    #endif
    #if os(tvOS)
    // tvOS's focus engine doesn't reliably move focus into a newly-presented
    // .fullScreenCover on its own — a @FocusState still bound in the presenting screen
    // (e.g. TVHomeView's shelf-row focus) can keep holding the remote's actual focus target
    // even though it's now hidden behind the player, so directional/select presses land on
    // the invisible screen underneath instead of anything here. Explicitly claiming focus
    // onto a real player control once this view has appeared is what actually pulls it over.
    // Namespace for .prefersDefaultFocus below — the documented, system-driven mechanism for
    // claiming initial focus into a freshly-presented scope. A manual @FocusState + delayed
    // Task retry was tried here before (twice) and wasn't reliable; this is what Apple's own
    // tvOS focus APIs are actually built for, so the system handles the landing itself instead
    // of this code guessing at timing.
    @Namespace var tvFocusNamespace
    @Environment(\.resetFocus) var resetFocus
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
        let defaults = UserDefaults.standard
        let mobileQuality = DownloadManager.isOnMobileDataNow
            ? defaults.string(forKey: "mobileVideoQuality").flatMap(VideoQuality.init(rawValue:)) : nil
        _quality = State(initialValue: mobileQuality ?? VideoQuality(rawValue: defaults.string(forKey: "videoQuality") ?? "") ?? .max)
        let behavior = ResumeBehavior.current
        _resumeFrom = State(initialValue: behavior == .startOver ? 0 : startPositionTicks)
        _isAskingToResume = State(initialValue: behavior == .ask && startPositionTicks > 0)
    }

    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    var body: some View {
        bodyContent.alwaysDarkPlayer()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if !os(tvOS)
            if CastManager.shared.isConnected {
                // The receiver is playing the video, not this screen — leaving the last
                // local frame frozen behind the controls read as "stuck paused" rather
                // than "actively casting elsewhere", so the surface is swapped for a
                // dedicated placeholder instead.
                castingPlaceholder
            } else {
                videoSurfaceLayer
            }
            #else
            videoSurfaceLayer
            #endif

            if audioOnly {
                audioOnlyCover
            }

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

            if let currentSubtitleText, !CastManager.shared.isConnected {
                subtitleOverlay(currentSubtitleText)
            }
            if let currentBitmapCue, !CastManager.shared.isConnected {
                bitmapSubtitleOverlay(currentBitmapCue)
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
                #if os(tvOS)
                .opacity(tvControlsHidden ? 0 : 1)
                .disabled(tvControlsHidden)
                #else
                .opacity(isControlsVisible && !CastManager.shared.isConnected ? 1 : 0)
                #endif
                .allowsHitTesting(isControlsVisible && !CastManager.shared.isConnected)

            #if os(tvOS)
            if tvCatcherActive {
                tvRemoteCatcher
            }
            #endif

            skipButton

            if showUpNext, let nextEpisode {
                upNextCard(nextEpisode)
            }

            moreLikeThisOverlay
            xRayOverlay

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
        #if os(tvOS)
        .focusScope(tvFocusNamespace)
        .onPlayPauseCommand { togglePlayPause() }
        .onExitCommand { handleTVExit() }
        // Hands focus to whichever control should have it now (the catcher, play/pause, Skip,
        // Up Next) instead of leaving it on something that just disappeared.
        .onChange(of: tvFocusContext) { _, _ in resetFocus(in: tvFocusNamespace) }
        // A fallback for when the currently-focused control has no further focusable
        // neighbor in that direction (e.g. focus sitting on the leftmost/rightmost transport
        // button, or on nothing in particular right after .prefersDefaultFocus lands) — the
        // system only calls this once its own spatial focus search comes up empty, so it
        // never fires while there's a real button to move to instead. seek(by:) already
        // reveals controls via toggleControlsVisibilityOnAction(), same as every other seek
        // entry point.
        .onMoveCommand { direction in
            switch direction {
            case .left: seek(by: -skipBackwardSeconds)
            case .right: seek(by: skipForwardSeconds)
            default: break
            }
        }
        #endif
        .task { if !isAskingToResume { await setup() } }
        .confirmationDialog("Resume Playback?", isPresented: $isAskingToResume, titleVisibility: .visible) {
            Button("Resume from \(timeLabel(ticks: startPositionTicks))") {
                resumeFrom = startPositionTicks
                resumeAnswered = true
            }
            Button("Start from Beginning") {
                resumeFrom = 0
                resumeAnswered = true
            }
            Button("Cancel", role: .cancel) { closePlayer() }
        }
        .onChange(of: isAskingToResume) { _, asking in
            if !asking, resumeAnswered { Task { await setup() } }
        }
        .onDisappear {
            Task { await teardown() }
            #if canImport(UIKit) && !os(tvOS)
            if Self.keepOrientationOnNextDisappear {
                Self.keepOrientationOnNextDisappear = false
            } else {
                resetPlayerOrientation()
            }
            #elseif os(macOS)
            macVolumeHUDTask?.cancel()
            #endif
        }
        .onChange(of: subtitleDelay) { _, _ in updateSubtitleText(forTicks: player.positionTicks) }
        .onChange(of: player.positionTicks) { _, newValue in
            updateSubtitleText(forTicks: newValue)
            checkUpNextThreshold(positionTicks: newValue)
            checkMoreLikeThisThreshold(positionTicks: newValue)
            autoSkipIfNeeded(positionTicks: newValue)
            updateNowPlayingInfo()
        }
        .onChange(of: player.status) { _, newStatus in
            // The receiver is the one playing — any local resume (a load finishing, a seek
            // completing, an interruption ending) would play the same audio twice.
            if newStatus == .playing, CastManager.shared.isConnected {
                Task { await player.pause() }
            }
            handleStatusChange(newStatus)
            updateNowPlayingInfo()
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
        .focusedSceneValue(\.playerCommands, PlayerCommands(
            isPlaying: playPauseIconIsPlaying,
            togglePlay: { togglePlayPause() },
            skip: { seek(by: $0 > 0 ? skipForwardSeconds : -skipBackwardSeconds) },
            volume: { adjustMacVolume(by: $0) },
            toggleFullScreen: { toggleMacWindowFullScreen(macWindow) },
            close: { closePlayer() },
            isMuted: macVolume == 0,
            toggleMute: { toggleMacMute() },
            hasSubtitles: !(playbackInfo?.subtitleStreams.isEmpty ?? true),
            subtitlesOn: selectedSubtitleIndex != nil,
            toggleSubtitles: { toggleSubtitles() },
            showTracks: { showTrackMenu = true },
            showInfo: { showInfoSheet = true },
            stepSpeed: { stepPlaybackRate($0) },
            resetSpeed: { choosePlaybackRate(1) },
            skipSegmentLabel: currentSkippable?.label,
            skipSegment: { skipToSegmentEnd() },
            next: nextEpisode == nil ? nil : { playNextEpisode() },
            previous: previousItem == nil ? nil : { playPrevious() }
        ))
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
        .sheet(item: $xRayPerson, onDismiss: { Task { await player.play() } }) { person in
            NavigationStack {
                PersonDetailView(person: person)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { xRayPerson = nil } }
                    }
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            mediaInfoSheet
        }
        .onChange(of: showSyncPlayMenu) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        .sheet(isPresented: $showSyncPlayMenu) {
            syncPlaySheet
        }
        .onChange(of: syncPlayManager.incomingCommand) { _, command in
            guard let command else { return }
            applySyncPlayCommand(command)
        }
        #if canImport(GoogleCast)
        .onChange(of: CastManager.shared.playbackFinishedCount) { _, _ in
            // Local playback is paused for the whole cast, so the Up Next countdown (which
            // follows the local position) never fires — the receiver's end-of-item is the
            // signal instead.
            guard CastManager.shared.isConnected, nextEpisode != nil,
                  UserDefaults.standard.bool(forKey: "autoPlayNext") else { return }
            playNextEpisode(isAutomatic: true)
        }
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
    /// Covers the video with a plain screen for listening. Playback is untouched, and taps
    /// still reach the surface underneath so the controls behave as usual.
    var audioOnlyCover: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                Text(item.type == .episode ? (item.seriesName ?? item.name) : item.name)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Audio Only")
                    .font(.system(.footnote))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 32)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
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
            // "Inert to touch" (see the PiPVideoView comment below) doesn't mean invisible to
            // tvOS's focus engine — unlike touch hit-testing, which SwiftUI resolves to
            // whichever ZStack sibling is topmost at a point, tvOS's spatial focus resolution
            // can still treat a plain, screen-filling UIViewRepresentable-hosted view as a
            // focusable candidate in its own right, competing with (and, being enormous,
            // often winning against) the small buttons actually drawn on top of it. VLC's
            // branch already excluded itself from hit-testing on tvOS; this one hadn't.
            PlayerLayerRepresentable(player: avPlayer.player, isFillScreen: isFillScreen)
                .allowsHitTesting(false)
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
            PiPVideoView(vlcEngine.vlcPlayer, controller: $vlcPipController,
                         startsAutomaticallyFromInline: UserDefaults.standard.bool(forKey: "autoPictureInPicture"),
                         managesAudioSession: false)
                .allowsHitTesting(false)
            #endif
        } else if let aetherEngine = player as? AetherEnginePlayer {
            // AetherEngineVideoSurface binds the engine directly (engine.bind(view:)
            // internally) — no layer/controller to hand it, unlike the AVFoundation/VLC
            // branches above.
            AetherEngineVideoSurface(player: aetherEngine)
                .allowsHitTesting(false)
        }
    }

    /// Shared by macOS's Up/Down-arrow volume shortcuts and tvOS's remote volume commands
    /// (PlayerView+Gestures.swift) — both platforms drive the active engine's own volume
    /// directly rather than through a system volume surface, since neither has one reachable
    /// from here (macOS has no "hidden MPVolumeView" trick the way iOS does; tvOS's physical
    /// volume buttons don't reach the app at all unless wired up this way).
    func setEngineVolume(_ volume: Float) {
        if let avPlayer = player as? AVFoundationPlayer {
            avPlayer.player.volume = volume
        } else if let vlcEngine = player as? VLCEnginePlayer {
            try? vlcEngine.vlcPlayer.setAudioVolume(Volume(volume))
        } else if let aetherEngine = player as? AetherEnginePlayer {
            aetherEngine.volume = volume
        }
    }

    func applyFillScreen() {
        if let vlcEngine = player as? VLCEnginePlayer {
            vlcEngine.vlcPlayer.aspectRatio = isFillScreen ? .fill : .default
        } else if let aetherEngine = player as? AetherEnginePlayer {
            aetherEngine.isFillScreen = isFillScreen
        }
        // AVFoundation's videoGravity is driven declaratively via videoSurface's
        // isFillScreen param above — no imperative call needed for that branch.
    }

    #if !os(tvOS)
    /// Only where it works: VLC's own PiP, or AVFoundation/Aether through an AVPlayerLayer
    /// (not Aether's software route).
    var canPictureInPicture: Bool {
        player is VLCEnginePlayer ? vlcPipController != nil : pip.isSupported
    }

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
              let (data, _) = try? await URLSession.arcfin.data(from: url),
              let image = PlatformImage(data: data)
        else { return }
        // Only the current title's artwork is ever read, so a long session of back-to-back
        // episodes shouldn't keep every previous 600px poster alive in memory.
        if Self.artworkCache.count >= 8 { Self.artworkCache.removeAll() }
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
                },
                subtitleSearchItemId: ProfileRules.shared.canManageSubtitles ? item.id : nil,
                onSubtitleDownloaded: {
                    showTrackMenu = false
                    adoptDownloadedSubtitle()
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
        // presentationDetents is an iPhone/iPad card-sheet concept sized for a portrait
        // screen — tvOS has no drag-to-dismiss and forcing .medium onto its differently
        // shaped modal container clipped the content at both edges. Letting tvOS use its
        // own default sheet presentation instead.
        #if !os(tvOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        #endif
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
    static let lastRateKey = "lastPlaybackRate"

    /// Applies the last picked speed to a freshly loaded stream when Settings → Playback →
    /// Remember Playback Speed is on. The key is written on every pick so turning the
    /// setting on later starts from the speed last used.
    private func applyRememberedRate() async {
        let defaults = UserDefaults.standard
        // Otherwise Settings › Playback › Default Speed.
        let rate = defaults.bool(forKey: "rememberPlaybackSpeed")
            ? defaults.float(forKey: Self.lastRateKey)
            : Float(defaults.object(forKey: "defaultPlaybackSpeed") as? Double ?? 1)
        guard rate > 0, rate != 1 else { return }
        await player.setRate(rate)
    }

    @ViewBuilder
    private var rateMenuButtons: some View {
        ForEach(Self.rateOptions, id: \.self) { rate in
            Button(rateLabel(rate) + (rate == player.playbackRate ? " ✓" : "")) {
                choosePlaybackRate(rate)
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    func choosePlaybackRate(_ rate: Float) {
        UserDefaults.standard.set(rate, forKey: Self.lastRateKey)
        Task { await player.setRate(rate) }
    }

    /// One step along the speed menu's options, from whichever is closest to the current speed.
    func stepPlaybackRate(_ direction: Int) {
        let options = Self.rateOptions
        let current = options.indices.min { abs(options[$0] - player.playbackRate) < abs(options[$1] - player.playbackRate) } ?? 2
        choosePlaybackRate(options[min(max(current + direction, 0), options.count - 1)])
    }

    /// Off, or back to the last subtitle shown (the first one when none has been yet).
    func toggleSubtitles() {
        if let current = selectedSubtitleIndex {
            lastSubtitleIndex = current
            changeTrack(subtitleIndex: .some(nil))
        } else if let index = lastSubtitleIndex ?? playbackInfo?.subtitleStreams.first?.index {
            changeTrack(subtitleIndex: .some(index))
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "Normal" : "\(rate.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", rate) : String(format: "%.2f", rate))×"
    }

    // MARK: - Setup / teardown

    /// The AVFoundation/VLC split Auto used before Aether existed — now only reached when
    /// Aether itself fails to construct or load a source (see setup()'s runtime fallback).
    private func legacyEnginePlayer(container: String?, videoStream: JellyfinMediaStream?) -> any MediaPlayerProtocol {
        switch PlaybackEngineSelector.legacyFallback(container: container, videoStream: videoStream) {
        case .vlc: return VLCEnginePlayer()
        default: return AVFoundationPlayer()
        }
    }

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
                credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                quality: qualityCap(for: quality)
            )
            // .choose always resolves Auto down to a concrete engine — three outcomes here.
            let engine = PlaybackEngineSelector.choose(
                preference: playbackEnginePreference, container: info.container, videoStream: info.videoStream
            )
            switch engine {
            case .aether:
                if !(player is AetherEnginePlayer) {
                    // init() throws — a construction failure is just another "Aether can't
                    // serve this session" case, handled by the exact same fallback path a
                    // load() failure goes through below.
                    player = (try? AetherEnginePlayer())
                        ?? legacyEnginePlayer(container: info.container, videoStream: info.videoStream)
                }
            case .vlc:
                if !(player is VLCEnginePlayer) { player = VLCEnginePlayer() }
            case .avFoundation:
                if !(player is AVFoundationPlayer) { player = AVFoundationPlayer() }
            case .auto:
                // .choose() never actually returns .auto (it always resolves Auto down to a
                // concrete engine above) — only reachable if that invariant breaks later.
                if !(player is AetherEnginePlayer) {
                    player = (try? AetherEnginePlayer())
                        ?? legacyEnginePlayer(container: info.container, videoStream: info.videoStream)
                }
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
            // A show's own remembered choice beats the global defaults above.
            if ShowTrackMemory.isEnabled, item.type == .episode, let seriesId = item.seriesId,
               let memory = ShowTrackMemory.load(seriesID: seriesId) {
                if let language = memory.audio,
                   let match = info.audioStreams.first(where: { $0.language == language }),
                   match.index != selectedAudioIndex {
                    selectedAudioIndex = match.index
                    languagePreferenceApplied = true
                }
                if memory.subtitlesOff {
                    if selectedSubtitleIndex != nil {
                        selectedSubtitleIndex = nil
                        languagePreferenceApplied = true
                    }
                } else if let language = memory.subtitle,
                          let match = info.subtitleStreams.first(where: { $0.language == language }),
                          match.index != selectedSubtitleIndex {
                    selectedSubtitleIndex = match.index
                    languagePreferenceApplied = true
                }
            }
            // Jellyfin negotiates audio/subtitle selection server-side (see changeTrack) —
            // a language default that actually changed the pick needs the same re-fetch
            // with explicit indices before the very first play, not just a local index change.
            if languagePreferenceApplied, let reInfo = try? await client.getPlaybackInfo(
                credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
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
            castMembers = detail?.cast ?? []
            currentLikes = detail?.item.userData?.likes
            await loadSubtitleCues(from: info, credential: credential)
            lastLoadStartedAt = Date()
            // Auto's pre-flight pick can't catch everything — a runtime load failure on
            // Aether (the exact class of bug we spent real time on this session, where a
            // source's own structure breaks one engine but not another) falls back once to
            // the same AVFoundation/VLC split Auto used before Aether existed, rather than
            // surfacing a hard error over an engine that can't serve this specific source.
            do {
                try await player.load(url: info.playURL, startPositionTicks: resumeFrom)
            } catch where player is AetherEnginePlayer {
                player = legacyEnginePlayer(container: info.container, videoStream: info.videoStream)
                try await player.load(url: info.playURL, startPositionTicks: resumeFrom)
            }
            await player.play()
            await applyRememberedRate()
            // The preferred or remembered audio language, which a file played as is ignores.
            if selectedAudioIndex != nil { await selectAudioInEngine() }
            // A cast that was already running when this screen opened (autoplay moved on to
            // the next episode) never produces an isConnected change to trigger this.
            if CastManager.shared.isConnected { startCasting() }
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
            } else if let aetherPlayer = player as? AetherEnginePlayer {
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
            #endif
            setUpNowPlayingCommandsIfNeeded()
            updateNowPlayingInfo()
            Task { await fetchAndApplyNowPlayingArtwork() }
            await client.reportPlaybackStart(credential: credential, authHeader: authHeader,
                                             itemId: item.id, mediaSourceId: info.mediaSourceId,
                                             positionTicks: resumeFrom)
            startProgressReporting(mediaSourceId: info.mediaSourceId)
        } catch {
            errorMessage = "Couldn't start playback: \(error.localizedDescription)"
        }

        segments = await client.getSkipSegments(credential: credential, authHeader: authHeader, itemId: item.id)
        autoSkipped = []

        // A playlist or collection playing through goes by its own order; an episode by the
        // series' order. Next Up wasn't usable here: part-way through an episode it answers
        // with that same episode.
        if PlayQueue.contains(item.id) {
            nextEpisode = PlayQueue.item(after: item.id)
            previousItem = PlayQueue.item(before: item.id)
        } else if item.type == .episode, let seriesId = item.seriesId,
                  let episodes = try? await client.getEpisodes(
                    credential: credential, authHeader: authHeader, seriesId: seriesId, seasonId: nil) {
            // Specials sit outside the run of the show unless one is what's playing.
            let run = item.parentIndexNumber == 0 ? episodes : episodes.filter { $0.parentIndexNumber != 0 }
            if let index = run.firstIndex(where: { $0.id == item.id }) {
                nextEpisode = run.indices.contains(index + 1) ? run[index + 1] : nil
                previousItem = index > 0 ? run[index - 1] : nil
            }
        }

        // Anything with an Up Next card already has something to watch next; the rest (movies,
        // a series finale) get suggestions instead once the credits start.
        moreLikeThis = []
        showMoreLikeThis = false
        moreLikeThisDismissed = false
        if nextEpisode == nil {
            moreLikeThis = ((try? await client.getSimilarItems(
                credential: credential, authHeader: authHeader, itemId: item.id, limit: 12)) ?? [])
                .filter { $0.id != item.id }
        }
    }

    // MARK: - SyncPlay

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

    // MARK: - Chromecast

    /// A Cast session took over — the receiver plays the stream itself, so the local
    /// player pauses rather than playing the same thing twice.
    func startCasting() {
        tracksAtCastStart = (selectedAudioIndex, selectedSubtitleIndex)
        currentSubtitleText = nil
        currentBitmapCue = nil
        Task { await player.pause() }
        loadCast(startSeconds: Double(player.positionTicks) / 10_000_000)
    }

    /// (Re)loads the receiver. A newer call cancels an older in-flight one so two loads can
    /// never both reach the receiver.
    func loadCast(startSeconds: Double) {
        guard let credential, let authHeader else { return }
        castLoadTask?.cancel()
        let posterURL = mediaRepo.imageURL(for: item, type: .primary, fillWidth: 400)
        castLoadTask = Task {
            let info = try? await client.getPlaybackInfo(
                credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                quality: qualityCap(for: quality),
                audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex,
                forCast: true
            )
            guard !Task.isCancelled, let url = info?.playURL ?? playbackInfo?.playURL else { return }
            // Text subtitles go to the receiver as sidecar WebVTT tracks; image-based ones
            // have no deliveryUrl and are burned into the transcode by the server instead.
            let tracks = (info ?? playbackInfo)?.subtitleStreams.compactMap { stream -> CastManager.SubtitleTrack? in
                guard let delivery = stream.deliveryUrl,
                      let trackURL = SubtitleLoader.absoluteURL(deliveryUrl: delivery, credential: credential)
                else { return nil }
                return CastManager.SubtitleTrack(
                    id: stream.index, url: trackURL, languageCode: stream.language, name: stream.displayTitle)
            } ?? []
            castSubtitleTrackIDs = Set(tracks.map(\.id))
            CastManager.shared.loadMedia(
                streamURL: url, title: item.name, subtitle: nil, posterImageURL: posterURL,
                contentType: castContentType(for: url),
                startPositionSeconds: startSeconds,
                subtitleTracks: tracks,
                activeSubtitleTrackID: tracks.contains { $0.id == selectedSubtitleIndex } ? selectedSubtitleIndex : nil,
                isTransportStreamHLS: url.pathExtension.lowercased() == "m3u8"
            )
        }
    }

    /// Audio is baked into the transcoded stream, so a different track needs a new stream
    /// from the current live position rather than a receiver-side switch.
    func selectCastAudio(index: Int) {
        guard index != selectedAudioIndex else { return }
        selectedAudioIndex = index
        loadCast(startSeconds: CastManager.shared.lastKnownPositionSeconds ?? 0)
    }

    /// Sidecar text tracks switch instantly on the receiver; a track that isn't one (off
    /// is, image-based isn't) needs a new stream with the subtitle burned in.
    func selectCastSubtitle(index: Int?) {
        guard index != selectedSubtitleIndex else { return }
        selectedSubtitleIndex = index
        if index == nil || castSubtitleTrackIDs.contains(index!) {
            CastManager.shared.setActiveSubtitleTrack(id: index)
        } else {
            loadCast(startSeconds: CastManager.shared.lastKnownPositionSeconds ?? 0)
        }
    }

    /// The session ended — pick local playback back up from wherever the receiver had
    /// gotten to. `currentPositionSeconds()` reads the live session and is already nil by
    /// the time this runs (the session is gone), so this uses CastManager's own
    /// continuously-updated `lastKnownPositionSeconds` instead — see its doc comment.
    func resumeLocalPlaybackAfterCast() {
        castLoadTask?.cancel()
        defer { tracksAtCastStart = nil }
        // Tracks picked on the cast dashboard change selectedAudioIndex/selectedSubtitleIndex,
        // but the local player is still on the old stream — reload so it matches what the
        // viewer was just watching.
        if let before = tracksAtCastStart,
           before.audio != selectedAudioIndex || before.subtitle != selectedSubtitleIndex {
            let seconds = CastManager.shared.lastKnownPositionSeconds ?? Double(player.positionTicks) / 10_000_000
            reload(errorContext: "resume after casting", resumeTicks: Int64(seconds * 10_000_000))
            return
        }
        if let seconds = CastManager.shared.lastKnownPositionSeconds {
            Task {
                await player.seek(to: Int64(seconds * 10_000_000))
                await player.play()
            }
        } else {
            Task { await player.play() }
        }
    }

    /// Keyed off the URL, not the source container — an mkv source is served as an HLS
    /// transcode, and labelling that playlist video/mp4 leaves the receiver mis-demuxing it.
    private func castContentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "application/x-mpegurl"
        case "mov":  return "video/quicktime"
        default:     return "video/mp4"
        }
    }

    private func teardown() async {
        progressReportTask?.cancel()
        sleepTimerTask?.cancel()
        hideControlsTask?.cancel()
        stillWatchingTimeoutTask?.cancel()
        #if os(macOS)
        // The window's toolbar is real window chrome, not part of this view — left hidden,
        // it would stay hidden on whatever screen is underneath once the player closes.
        setMacWindowToolbarVisible(macWindow, true)
        #endif
        // Closing the player closes the group too — an orphaned WebSocket connection with
        // nobody watching isn't useful, and simpler than trying to keep it alive across
        // whatever the user navigates to next.
        if syncPlayManager.isInGroup, let credential = authManager.state.credential {
            syncPlayManager.leaveGroup(credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken))
        }
        #if canImport(UIKit) && !os(tvOS)
        volumeController?.teardown()
        volumeObservation?.invalidate()
        volumeEchoSuppressTask?.cancel()
        displayCriteriaMatcher.detach()
        #endif
        nowPlayingManager.clear()
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        if let credential, let authHeader, let info = playbackInfo {
            let stoppedAt = player.positionTicks
            await client.reportPlaybackStopped(credential: credential, authHeader: authHeader,
                                               itemId: item.id, mediaSourceId: info.mediaSourceId,
                                               positionTicks: stoppedAt)
            if WatchedThreshold.current.isReached(seconds: Double(stoppedAt) / 10_000_000,
                                                  duration: Double(player.durationTicks) / 10_000_000,
                                                  creditsStart: segments.credits?.lowerBound) {
                _ = try? await client.markWatched(credential: credential, authHeader: authHeader, itemId: item.id, watched: true)
            }
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
        let seconds = Double(positionTicks) / 10_000_000
        // From the moment the credits start when the server knows it, else the last 30s.
        let withinWindow = remainingSeconds > 0
            && (segments.credits.map { seconds >= $0.lowerBound } ?? (remainingSeconds <= 30))
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

    /// Shows the suggestions from the credits start (when the server knows it) or, failing
    /// that, the last four minutes; seeking back out of the credits hides them again.
    private func checkMoreLikeThisThreshold(positionTicks: Int64) {
        guard nextEpisode == nil, !moreLikeThis.isEmpty, !moreLikeThisDismissed, player.durationTicks > 0 else { return }
        let duration = Double(player.durationTicks) / 10_000_000
        let seconds = Double(positionTicks) / 10_000_000
        let start = segments.credits?.lowerBound ?? max(duration - 240, 0)
        let inCredits = seconds >= start && seconds < duration
        if inCredits != showMoreLikeThis {
            withAnimation(DT.Animation.fast) { showMoreLikeThis = inCredits }
        }
    }

    /// The Skip … Automatically settings: jumps past a segment once as playback enters it.
    private func autoSkipIfNeeded(positionTicks: Int64) {
        let seconds = Double(positionTicks) / 10_000_000
        let defaults = UserDefaults.standard
        for (kind, span, enabled) in [
            ("recap", segments.recap, defaults.bool(forKey: "skipRecap")),
            ("intro", segments.intro, defaults.bool(forKey: "skipIntro")),
            ("credits", segments.credits, defaults.bool(forKey: "skipCredits")),
        ] {
            guard enabled, let span, span.contains(seconds), !autoSkipped.contains(kind) else { continue }
            autoSkipped.insert(kind)
            skip(kind: kind, span: span)
            return
        }
    }

    /// Past the end of a segment. Credits and previews at the very end move on to the next
    /// title, or finish; credits followed by more of the film (a mid-credits scene) seek to it.
    func skip(kind: String, span: ClosedRange<Double>) {
        let duration = Double(player.durationTicks) / 10_000_000
        let endsTitle = (kind == "credits" || kind == "preview") && (duration == 0 || span.upperBound >= duration - 5)
        if endsTitle {
            if nextEpisode != nil { playNextEpisode() } else { Task { await finishPlayback() } }
        } else {
            Task { await player.seek(to: Int64(span.upperBound * 10_000_000)) }
        }
        HapticManager.impact(.light)
    }

    /// Thumbs rating for what's playing, set from the credits panel; choosing the current
    /// rating again clears it.
    func rateCurrentItem(_ value: Bool) {
        guard let credential, let authHeader else { return }
        let newValue: Bool? = currentLikes == value ? nil : value
        currentLikes = newValue
        HapticManager.impact(.light)
        let id = item.id
        Task { try? await client.setRating(credential: credential, authHeader: authHeader, itemId: id, likes: newValue) }
    }

    private func startUpNextCountdown() {
        upNextCountdown?.cancel()
        upNextCountdown = Task {
            try? await Task.sleep(for: .seconds(UserDefaults.standard.object(forKey: "upNextCountdownSeconds") as? Int ?? 8))
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
        if isAutomatic, sleepAtEndOfItem {
            sleepAtEndOfItem = false
            showUpNext = false
            pauseForSleepTimer()
            return
        }
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

    // MARK: - Sleep timer

    /// nil minutes = "end of this video": nothing is scheduled, playNextEpisode just
    /// declines to auto-advance once. Picking again replaces whatever was set before.
    func setSleepTimer(minutes: Int?, atEndOfItem: Bool = false) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndsAt = nil
        sleepAtEndOfItem = atEndOfItem
        guard let minutes else { return }
        sleepTimerEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimerTask = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            sleepTimerEndsAt = nil
            pauseForSleepTimer()
        }
    }

    private func pauseForSleepTimer() {
        if CastManager.shared.isConnected { CastManager.shared.pause() }
        Task { await player.pause() }
        networkToast = "Sleep timer — playback paused"
        Task {
            try? await Task.sleep(for: .seconds(3))
            networkToast = nil
        }
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

    func playPrevious() {
        guard let previousItem else { return }
        upNextCountdown?.cancel()
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        onPlayNext(previousItem)
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
        let previousSubtitle = selectedSubtitleIndex
        if let audioIndex { selectedAudioIndex = audioIndex }
        if let subtitleIndex { selectedSubtitleIndex = subtitleIndex }
        rememberTracks(audioChanged: audioIndex != nil, subtitleChanged: subtitleIndex != nil)
        if audioIndex != nil, subtitleIndex == nil, !CastManager.shared.isConnected,
           playbackInfo?.playMethod == .directPlay {
            Task {
                if await !selectAudioInEngine() { reload(errorContext: "switch track") }
            }
            return
        }
        if audioIndex == nil, let subtitleIndex, !CastManager.shared.isConnected,
           drawsSubtitleHere(previousSubtitle), drawsSubtitleHere(subtitleIndex),
           let credential, let info = playbackInfo {
            Task {
                await loadSubtitleCues(from: info, credential: credential)
                updateSubtitleText(forTicks: player.positionTicks)
            }
            return
        }
        reload(errorContext: "switch track")
    }

    /// A file played as is carries every audio track: the server's audio choice only shapes a
    /// transcode, so here the engine switches tracks itself, without a new stream. Jellyfin's
    /// embedded audio streams and the engine's tracks are both in the file's order; when the
    /// counts don't line up it's left to a reload. Returns whether it was done.
    @discardableResult
    private func selectAudioInEngine() async -> Bool {
        guard let info = playbackInfo, info.playMethod == .directPlay, let index = selectedAudioIndex else { return false }
        let embedded = info.audioStreams.filter { !$0.isExternal }.sorted { $0.index < $1.index }
        guard let ordinal = embedded.firstIndex(where: { $0.index == index }) else { return false }
        // Engines list tracks a moment after the file opens.
        for _ in 0..<20 where player.availableAudioTracks.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard player.availableAudioTracks.count == embedded.count else { return false }
        let track = player.availableAudioTracks[ordinal]
        if track.id != player.selectedAudioTrackIndex { await player.setAudioTrack(index: track.id) }
        return true
    }

    /// Text subtitles come as their own file (WebVTT) the app draws over the video, so moving
    /// between them, or turning them off, leaves the stream as it is. Only one the server has
    /// to burn into the picture (an image format being transcoded) needs a new stream.
    private func drawsSubtitleHere(_ index: Int?) -> Bool {
        guard let index else { return true }
        return playbackInfo?.subtitleStreams.first(where: { $0.index == index })?.deliveryUrl != nil
    }

    func changeVersion(_ id: String) {
        guard id != playbackInfo?.mediaSourceId else { return }
        selectedMediaSourceId = id
        // Track indexes belong to a version; the new one picks its own defaults.
        selectedAudioIndex = nil
        selectedSubtitleIndex = nil
        reload(errorContext: "switch version")
    }

    /// Switches to a subtitle the server just fetched from a provider. The server adds it to
    /// the item in the background, so the new track can take a few seconds to be listed.
    func adoptDownloadedSubtitle() {
        guard let credential, let authHeader else { return }
        let known = Set(playbackInfo?.subtitleStreams.map(\.index) ?? [])
        networkToast = "Adding subtitles…"
        Task {
            for _ in 0..<5 {
                if let info = try? await client.getPlaybackInfo(
                    credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                    quality: qualityCap(for: quality),
                    audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex),
                   let added = info.subtitleStreams.first(where: { !known.contains($0.index) }) {
                    networkToast = nil
                    changeTrack(subtitleIndex: .some(added.index))
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
            networkToast = "Subtitles were saved on the server. Reopen the title to use them."
            try? await Task.sleep(for: .seconds(4))
            networkToast = nil
        }
    }

    /// Stores the language of a track the viewer just picked, for the rest of the show.
    private func rememberTracks(audioChanged: Bool, subtitleChanged: Bool) {
        guard ShowTrackMemory.isEnabled, item.type == .episode, let seriesId = item.seriesId,
              let info = playbackInfo
        else { return }
        var entry = ShowTrackMemory.load(seriesID: seriesId) ?? .init()
        if audioChanged, let index = selectedAudioIndex,
           let language = info.audioStreams.first(where: { $0.index == index })?.language {
            entry.audio = language
        }
        if subtitleChanged {
            if let index = selectedSubtitleIndex {
                if let language = info.subtitleStreams.first(where: { $0.index == index })?.language {
                    entry.subtitle = language
                    entry.subtitlesOff = false
                }
            } else {
                entry.subtitlesOff = true
            }
        }
        ShowTrackMemory.save(entry, seriesID: seriesId)
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
        guard !CastManager.shared.isConnected else {
            currentSubtitleText = nil
            currentBitmapCue = nil
            return
        }
        let seconds = Double(ticks) / 10_000_000 - subtitleDelay
        if subtitleCues.isEmpty {
            currentSubtitleText = nil
        } else {
            currentSubtitleText = SubtitleLoader.cue(at: seconds, in: subtitleCues)
        }
        if let aetherPlayer = player as? AetherEnginePlayer, !aetherPlayer.nativeBitmapCues.isEmpty {
            currentBitmapCue = aetherPlayer.nativeBitmapCues.first {
                seconds >= $0.startTime && seconds < $0.endTime
            }
        } else {
            currentBitmapCue = nil
        }
    }

    private func reload(errorContext: String, resumeTicks overrideTicks: Int64? = nil) {
        guard let credential, let authHeader else { return }
        let resumeTicks = overrideTicks ?? player.positionTicks
        Task {
            do {
                let info = try await client.getPlaybackInfo(
                    credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                    quality: qualityCap(for: quality),
                    audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex
                )
                playbackInfo = info
                await loadSubtitleCues(from: info, credential: credential)
                lastLoadStartedAt = Date()
                try await player.load(url: info.playURL, startPositionTicks: resumeTicks)
                await player.play()
                if selectedAudioIndex != nil { await selectAudioInEngine() }
                await applyRememberedRate()
                #if !os(tvOS) && !os(macOS)
                if let avPlayer = player as? AVFoundationPlayer {
                    avPlayer.player.currentItem?.externalMetadata = airPlayExternalMetadata()
                }
                #endif
                updateNowPlayingInfo()
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
        // A genuine hide via isControlsVisible/allowsHitTesting (same mechanism the other
        // platforms use below) was tried here before and reverted — allowsHitTesting=false
        // made every control genuinely unfocusable, and tvOS's focus engine doesn't reliably
        // migrate focus to a fallback once that happens; unlike iOS there's also no tap
        // gesture on the video surface to bring a hidden overlay back. tvControlsHidden only
        // ever drives opacity, never allowsHitTesting (see body's controlsOverlay modifiers
        // and toggleControlsVisibilityOnAction) — every control stays genuinely focusable the
        // whole time even at opacity 0, so the remote can never end up with nothing reachable,
        // even though visually nothing is on screen until the next interaction.
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, player.status == .playing else { return }
            withAnimation(DT.Animation.fast) { tvControlsHidden = true }
        }
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
