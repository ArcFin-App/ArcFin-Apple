// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import MediaEngine
import AuthCore
import Persistence
import SwiftVLC

/// Playback of a DownloadedItem from its local file. Simpler than PlayerView by design: no
/// quality/transcode menu (there's exactly one file). Position is saved to the local
/// SwiftData record and handed to the server as soon as it's reachable (OfflineProgressSync);
/// when it's reachable at the start, a newer resume point from another device is used.
struct OfflinePlayerView: View {
    let downloadedItem: DownloadedItem
    /// Overrides the saved resume position — nil (the default) resumes from
    /// downloadedItem.playbackPositionTicks as before; 0 is how "Start Over" is expressed.
    var startPositionOverride: Int64?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(AuthManager.self) private var authManager
    @AppStorage("playbackEngine") private var playbackEnginePreference = PlaybackEngineKind.auto
    @AppStorage("deleteDownloadsAfterWatching") private var deleteAfterWatching = false

    @State private var model: OfflinePlayerModel
    @State private var vlcPipController: SwiftVLC.PiPController?
    /// Aether's native routes play through an AVPlayerLayer, which PiP can take over.
    @StateObject private var pip = PiPCoordinator()

    init(downloadedItem: DownloadedItem, startPositionOverride: Int64? = nil) {
        self.downloadedItem = downloadedItem
        self.startPositionOverride = startPositionOverride
        _model = State(initialValue: OfflinePlayerModel(downloadedItem: downloadedItem))
    }

    var body: some View {
        bodyContent.alwaysDarkPlayer()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlaybackPositionObserver(player: model.player) { model.positionChanged(to: $1) }

            GeometryReader { proxy in
                // PiPVideoView's native drawable is itself interactive (unlike AVFoundation's
                // inert surface) and was swallowing the tap before onTapGesture below saw it.
                // The gesture lives on this separate wrapping ZStack, not on PiPVideoView
                // itself, so disabling hit-testing on the surface can't also disable it.
                ZStack {
                    if let vlcEngine = model.player as? VLCEnginePlayer {
                        PiPVideoView(vlcEngine.vlcPlayer, controller: $vlcPipController,
                                     startsAutomaticallyFromInline: UserDefaults.standard.bool(forKey: "autoPictureInPicture"),
                                     managesAudioSession: false)
                            .allowsHitTesting(false)
                    } else if let aetherEngine = model.player as? AetherEnginePlayer {
                        AetherEngineVideoSurface(player: aetherEngine)
                            .allowsHitTesting(false)
                    }
                }
                // See PlayerView's own note — GeometryReader only proposes its size, it
                // doesn't force it, so the video surface needs pinning to proxy.size explicitly
                // or it's free to size itself off its own content instead of the screen.
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .onTapGesture { model.toggleControls() }
            }
            .ignoresSafeArea()

            // .idle covers the gap between the screen appearing and setup() actually calling
            // player.load() — without it the screen was just black with no spinner there.
            if model.player.status == .idle || model.player.status == .loading || model.player.isBuffering {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if let currentSubtitleText = model.currentSubtitleText {
                OfflineSubtitleOverlay(text: currentSubtitleText, isControlsVisible: model.isControlsVisible)
            }

            // Always mounted — see PlayerView's own note on why conditionally mounting this
            // (mount/unmount on every tap) was the real cause of the video+UI zoom glitch.
            controlsOverlay
                .opacity(model.isControlsVisible ? 1 : 0)
                .allowsHitTesting(model.isControlsVisible)

            // Outside the controls, so a segment can be skipped while they're hidden.
            VStack {
                Spacer()
                OfflinePlayerSkipButton(model: model)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .keepsScreenAwake(status: model.player.status)
        .task { await setup() }
        .onChange(of: RemoteControl.shared.command) { _, command in
            if let command { model.applyRemoteCommand(command.kind) }
        }
        .alert("Resume Playback?", isPresented: $model.isAskingToResume) {
            Button("Resume from \(OfflinePlayerModel.timeText(model.askedResumeTicks))") { model.resumeAnswer = model.askedResumeTicks }
            Button("Start from Beginning") { model.resumeAnswer = 0 }
            Button("Cancel", role: .cancel) { dismiss() }
        }
        .onChange(of: model.isAskingToResume) { _, asking in
            if !asking, let resumeAnswer = model.resumeAnswer { Task { await startPlayback(from: resumeAnswer) } }
        }
        .onDisappear {
            // Nothing played when the resume question was cancelled.
            if model.player.status != .idle { model.savePosition(final: true) }
            // Dismissing (back chevron, Escape) previously left VLC playing in the
            // background with no way to stop it short of killing the app — the player
            // was never actually told to stop, just visually torn down.
            Task {
                await model.player.stop()
                await deactivateAudioSession()
            }
            resetPlayerOrientation()
        }
        .onChange(of: model.player.status) { _, status in
            model.statusChanged(to: status, deleteAfterWatching: deleteAfterWatching, downloadManager: downloadManager)
        }
        .onChange(of: model.isFillScreen) { _, _ in
            model.applyFillScreen()
        }
        .sheet(isPresented: $model.showTrackMenu) {
            OfflineSubtitleSheet(model: model)
        }
    }

    // MARK: - Setup

    private func setup() async {
        model.attach(modelContext: modelContext, authManager: authManager)
        model.closePlayer = { closeRotatedPlayer { dismiss() } }
        await activateAudioSession()
        guard let startTicks = await model.startTicks(startPositionOverride: startPositionOverride) else { return }
        await startPlayback(from: startTicks)
    }

    private func startPlayback(from startTicks: Int64) async {
        await model.loadAndPlay(from: startTicks, enginePreference: playbackEnginePreference)
        if let aether = model.player as? AetherEnginePlayer, let layer = aether.nativePlayerLayer {
            pip.stashLayer(layer)
            pip.activateIfNeeded()
        }
        model.startProgressSaving()
    }

    /// Only where it works: VLC's own PiP, or Aether playing through an AVPlayerLayer.
    private var canPictureInPicture: Bool {
        model.player is VLCEnginePlayer ? vlcPipController != nil : pip.isSupported
    }

    private func togglePictureInPicture() {
        if model.player is VLCEnginePlayer { vlcPipController?.toggle() } else { pip.toggle() }
    }

    // Off the main thread — AVAudioSession's synchronous setActive can block long enough
    // to trip Xcode's "Hang Risk" instrument when called directly from the main actor.
    private func activateAudioSession() async {
        await Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }.value
    }

    private func deactivateAudioSession() async {
        await Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }.value
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            OfflinePlayerBottomBar(model: model)
        }
        .background(LocalPlayerScrim())
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { closeRotatedPlayer { dismiss() } } label: {
                Image(systemName: "chevron.down")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close player")
            VStack(alignment: .leading, spacing: 2) {
                Text(downloadedItem.name)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Downloaded")
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
            }
            Spacer()
            AirPlayButton().frame(width: 44, height: 44)
            if !downloadedItem.subtitleFileNames.isEmpty || model.player.availableAudioTracks.count > 1 {
                Button { model.showTrackMenu = true } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Audio and subtitles")
            }
            Menu {
                if canPictureInPicture {
                    Button { togglePictureInPicture() } label: {
                        Label("Picture in Picture", systemImage: "pip.enter")
                    }
                }
                Button { togglePlayerOrientation() } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                Button { model.isFillScreen.toggle() } label: {
                    Label(model.isFillScreen ? "Fit to Screen" : "Fill Screen",
                          systemImage: model.isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
    }
}
