// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
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

    func closePlayer() {
        closeRotatedPlayer { dismiss() }
    }

    @State var model: PlayerModel
    @State var remoteScrub = TVRemoteScrub()
    @State var remoteScrubStartTicks: Double = 0
    @FocusState var isScrubberFocused: Bool
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

    init(item: MediaItem, startPositionTicks: Int64 = 0, onPlayNext: @escaping (MediaItem) -> Void = { _ in }) {
        self.item = item
        self.startPositionTicks = startPositionTicks
        self.onPlayNext = onPlayNext
        _model = State(initialValue: PlayerModel(item: item, startPositionTicks: startPositionTicks, onPlayNext: onPlayNext,
                                                 hidesControlsByFading: true))
    }

    var body: some View {
        bodyContent.alwaysDarkPlayer()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlaybackPositionObserver(player: model.player) { model.positionChanged(from: $0, to: $1) }

            videoSurfaceLayer

            if audioOnly {
                PlayerAudioOnlyCover(item: item)
            }
            PlayerRadioCover(model: model)

            if let seekFeedback = model.seekFeedback {
                PlayerSeekFeedbackView(feedback: seekFeedback)
            }

            // .idle covers the gap between the screen appearing and setup() actually calling
            // player.load() (fetching PlaybackInfo/item detail first) — without it the screen
            // was just black with no spinner for that whole prefetch window.
            if model.errorMessage == nil, model.player.status == .idle || model.player.status == .loading || model.player.isBuffering {
                PlayerLoadingIndicator(status: model.loadingStatusText)
            }

            if let errorMessage = model.errorMessage {
                errorView(errorMessage)
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
                .opacity(model.tvControlsHidden ? 0 : 1)
                // An error's own buttons take over the remote while it's showing.
                .disabled(model.tvControlsHidden || model.errorMessage != nil)
                .allowsHitTesting(model.isControlsVisible && !CastManager.shared.isConnected)

            if tvCatcherActive {
                tvRemoteCatcher
            }

            skipButton

            if model.showUpNext, let nextEpisode = model.nextEpisode {
                upNextCard(nextEpisode)
            }

            moreLikeThisOverlay
            castPanelOverlay
            PlayerChannelListLayer(model: model)

            if model.showStillWatchingPrompt {
                stillWatchingOverlay
            }
        }
        .onAppear { ScreensaverHold.count += 1 }
        .onDisappear { ScreensaverHold.count -= 1 }
        .focusScope(tvFocusNamespace)
        .onPlayPauseCommand { if model.isScrubbing { commitTVScrub() } else { model.togglePlayPause() } }
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
            // With the controls up, left and right only move between them; running off the
            // end of a row shouldn't seek.
            guard model.tvControlsHidden else { return }
            switch direction {
            case .left where model.isLive: model.playPrevious()
            case .right where model.isLive: model.playNextEpisode()
            case .left: model.seek(by: -skipBackwardSeconds)
            case .right: model.seek(by: skipForwardSeconds)
            default: break
            }
        }
        .keepsScreenAwake(status: model.player.status)
        .onAppear {
            model.viewAppeared()
            connectModel()
        }
        .task { if !model.isAskingToResume { await model.startSetup() } }
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
            if !asking, model.resumeAnswered { Task { await model.startSetup() } }
        }
        .onDisappear {
            model.viewDisappeared { await teardown() }
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
        // These must live on a view that's always mounted, not inside the conditionally
        // -shown controlsOverlay — auto-hide removing that view from the tree while a
        // sheet/dialog was presented from it was tearing the presentation down too.
        .onChange(of: showTrackMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showQualityMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showRateMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showChapterMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .onChange(of: showInfoSheet) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .appSheet(isPresented: $showTrackMenu, title: "Audio & Subtitles", systemImage: "captions.bubble") {
            trackSelectionSheet
        }
        .confirmationDialog("Quality", isPresented: $showQualityMenu, titleVisibility: .visible) {
            qualityMenuButtons
        }
        .confirmationDialog("Playback Speed", isPresented: $showRateMenu, titleVisibility: .visible) {
            rateMenuButtons
        }
        // No presentationDetents on tvOS: it has no drag-to-dismiss, and forcing .medium/.large
        // onto its differently shaped modal container clipped the content at both edges.
        .appSheet(isPresented: $showChapterMenu, title: "Chapters", systemImage: "list.bullet.rectangle") {
            ChapterListSheet(model: model) { showChapterMenu = false }
        }
        .appSheet(item: $castPanelPerson, onDismiss: { Task { await model.player.play() } }) { person in
            NavigationStack {
                PersonDetailView(person: person)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { castPanelPerson = nil } }
                    }
            }
        }
        .appSheet(isPresented: $showInfoSheet, title: "Media Info", systemImage: "info.circle") {
            PlayerMediaInfoSheet(model: model) { showInfoSheet = false }
        }
        .onChange(of: showSyncPlayMenu) { _, isOpen in model.handleMenuVisibilityChange(isOpen) }
        .appSheet(isPresented: $showSyncPlayMenu, title: "SyncPlay", systemImage: "person.2.fill") {
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
        }
        .ignoresSafeArea()
    }

    // AVPlayerLayer hosting and SwiftVLC's plain VideoView both work fine on tvOS; only the
    // PiP-specific PiPVideoView path is iOS/macOS-only (SwiftVLC itself only compiles
    // PiPVideoView for iOS/AppKit, not tvOS).
    @ViewBuilder
    var videoSurface: some View {
        if let avPlayer = model.player as? AVFoundationPlayer {
            // "Inert to touch" (see PiPVideoView in the iOS player) doesn't mean invisible to
            // tvOS's focus engine — unlike touch hit-testing, which SwiftUI resolves to
            // whichever ZStack sibling is topmost at a point, tvOS's spatial focus resolution
            // can still treat a plain, screen-filling UIViewRepresentable-hosted view as a
            // focusable candidate in its own right, competing with (and, being enormous,
            // often winning against) the small buttons actually drawn on top of it. VLC's
            // branch already excluded itself from hit-testing on tvOS; this one hadn't.
            PlayerLayerRepresentable(player: avPlayer.player, isFillScreen: model.isFillScreen)
                .allowsHitTesting(false)
        } else if let vlcEngine = model.player as? VLCEnginePlayer {
            VideoView(vlcEngine.vlcPlayer)
                .allowsHitTesting(false)
        } else if let aetherEngine = model.player as? AetherEnginePlayer {
            // AetherEngineVideoSurface binds the engine directly (engine.bind(view:)
            // internally) — no layer/controller to hand it, unlike the AVFoundation/VLC
            // branches above.
            AetherEngineVideoSurface(player: aetherEngine)
                .allowsHitTesting(false)
        }
    }

    var trackSelectionSheet: some View {
        NavigationStack {
            TrackSelectionSheet(
                audioStreams: model.playbackInfo?.audioStreams ?? [],
                subtitleStreams: model.playbackInfo?.subtitleStreams ?? [],
                selectedAudioIndex: model.selectedAudioIndex,
                selectedSubtitleIndex: model.selectedSubtitleIndex,
                onSelectAudio: { index in
                    showTrackMenu = false
                    model.changeTrack(audioIndex: index)
                },
                onSelectSubtitle: { index in
                    showTrackMenu = false
                    model.changeTrack(subtitleIndex: .some(index))
                },
                subtitleSearchItemId: ProfileRules.shared.canManageSubtitles ? item.id : nil,
                onSubtitleDownloaded: {
                    showTrackMenu = false
                    model.adoptDownloadedSubtitle()
                },
                audioDescriptionIndices: model.audioDescriptionIndices,
                rowBackground: Color.clear,
                followsFocus: true,
                dialogueBoost: model.supportsDialogueBoost
                    ? Binding(get: { model.isDialogueBoosted }, set: { model.setDialogueBoost($0) }) : nil,
                raiseQuietAudio: model.supportsQuietAudio
                    ? Binding(get: { model.raisesQuietAudio }, set: { model.setRaiseQuietAudio($0) }) : nil,
                lineArt: model.supportsLineArt
                    ? Binding(get: { model.upscalesLineArt }, set: { model.setLineArt($0) }) : nil
            )
            // The sheet's left column has the title; Menu closes it, as in the other player sheets.
            .sheetTitle("Audio & Subtitles")
        }
        // presentationDetents is an iPhone/iPad card-sheet concept sized for a portrait
        // screen — tvOS has no drag-to-dismiss and forcing .medium onto its differently
        // shaped modal container clipped the content at both edges. Letting tvOS use its
        // own default sheet presentation instead.
    }

    @ViewBuilder
    var qualityMenuButtons: some View {
        // Don't offer a resolution the source can't actually supply (e.g. 4K for a 1080p
        // source) — Jellyfin would just upscale into a bigger, pointless transcode.
        let sourceHeight = model.playbackInfo?.videoStream?.height
        ForEach(VideoQuality.allCases.filter { q in
            guard let minHeight = q.minSourceHeight, let sourceHeight else { return true }
            return sourceHeight >= minHeight
        }) { q in
            Button(q.label + (q == model.quality ? " ✓" : "")) { model.changeQuality(to: q) }
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    var rateMenuButtons: some View {
        ForEach(PlayerModel.rateOptions, id: \.self) { rate in
            Button(model.rateLabel(rate) + (rate == model.player.playbackRate ? " ✓" : "")) {
                model.choosePlaybackRate(rate)
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Setup / teardown

    /// Hands the model this screen's environment.
    private func connectModel() {
        model.attach(authManager: authManager, mediaRepo: mediaRepo, syncPlayManager: syncPlayManager,
                     sharePlay: sharePlay, scenePhase: scenePhase)
        model.closePlayer = { closePlayer() }
    }

    private func teardown() async {
        model.stopTasks()
        model.leaveSyncPlayOnClose()
        await model.stopPlayback()
        model.detachViewSteps()
    }
}
