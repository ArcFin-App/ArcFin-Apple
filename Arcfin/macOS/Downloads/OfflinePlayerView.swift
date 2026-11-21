// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import AppKit
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
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 10
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 10

    @State private var model: OfflinePlayerModel
    @State private var vlcPipController: SwiftVLC.PiPController?
    /// Aether's native routes play through an AVPlayerLayer, which PiP can take over.
    @StateObject private var pip = PiPCoordinator()
    @State private var macWindow: NSWindow?
    @State private var isMacFullScreen = false
    @State private var macVolume: Double = 1.0
    @State private var macVolumeHUD: Double?
    @State private var macVolumeHUDTask: Task<Void, Never>?
    @FocusState private var isPlayerFocused: Bool
    @State private var lastMacHoverLocation: CGPoint?

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
                .gesture(macOfflineTapGesture(width: proxy.size.width))
                // See PlayerView's own note — onContinuousHover fires on more than genuine
                // pointer movement, which kept resetting the auto-hide timer nonstop.
                .onContinuousHover { phase in
                    guard case .active(let location) = phase, location != lastMacHoverLocation else { return }
                    lastMacHoverLocation = location
                    model.revealControls()
                }
            }
            .ignoresSafeArea()

            // .idle covers the gap between the screen appearing and setup() actually calling
            // player.load() — without it the screen was just black with no spinner there.
            if !model.hasFailed, model.player.status == .idle || model.player.status == .loading || model.player.isBuffering {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if model.hasFailed {
                PlayerErrorView(message: String(localized: "This download couldn't be played. The file may be missing or damaged."),
                                onClose: { closeRotatedPlayer { dismiss() } })
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

            if let macVolumeHUD {
                macOfflineVolumeIndicator(macVolumeHUD)
            }
        }
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
            model.close()
            // Dismissing (back chevron, Escape) previously left VLC playing in the
            // background with no way to stop it short of killing the app — the player
            // was never actually told to stop, just visually torn down.
            Task {
                await model.player.stop()
            }
            macVolumeHUDTask?.cancel()
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
        .background(WindowAccessor { window in
            macWindow = window
            isMacFullScreen = isMacWindowFullScreen(window)
        })
        .focusable()
        .focusEffectDisabled()
        .focused($isPlayerFocused)
        .onAppear { isPlayerFocused = true }
        // The specific-key overload (.space, .leftArrow, etc.) takes a zero-argument
        // () -> KeyPress.Result closure, unlike the characters: overload below, which takes
        // (KeyPress) -> KeyPress.Result — `{ _ in ... }` only compiles for the latter.
        .onKeyPress(.space) { model.togglePlayPause(); return .handled }
        .onKeyPress(.leftArrow) { model.seek(by: -skipBackwardSeconds); return .handled }
        .onKeyPress(.rightArrow) { model.seek(by: skipForwardSeconds); return .handled }
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
                closeRotatedPlayer { dismiss() }
            }
            return .handled
        }
    }

    // MARK: - Setup

    private func setup() async {
        model.attach(modelContext: modelContext, authManager: authManager)
        model.closePlayer = { closeRotatedPlayer { dismiss() } }
        guard let startTicks = await model.startTicks(startPositionOverride: startPositionOverride) else { return }
        await startPlayback(from: startTicks)
    }

    private func startPlayback(from startTicks: Int64) async {
        guard await model.loadAndPlay(from: startTicks, enginePreference: playbackEnginePreference) else { return }
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
            // No macOS AirPlayButton here — unlike PlayerView's AVFoundation engine,
            // AVRoutePickerView on macOS needs a real AVPlayer instance to route (see
            // AirPlayButton's macOS variant), and offline playback is VLC-only with no
            // AVPlayer to hand it. Not something VLC's macOS backend bridges either — a
            // genuine gap, not an oversight.
            if !downloadedItem.subtitleFileNames.isEmpty || model.player.availableAudioTracks.count > 1 {
                Button { model.showTrackMenu = true } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Audio and subtitles")
            }
            HStack(spacing: 14) {
                Button { model.isFillScreen.toggle() } label: {
                    Image(systemName: model.isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(model.isFillScreen ? "Fit to screen" : "Fill screen")
                .buttonStyle(.plain)
                Button { toggleMacWindowFullScreen(macWindow) } label: {
                    Image(systemName: isMacFullScreen ? "arrow.down.right.and.arrow.up.left.circle" : "arrow.up.left.and.arrow.down.right.circle")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Toggle full screen")
                .buttonStyle(.plain)
                if canPictureInPicture {
                    Button { togglePictureInPicture() } label: {
                        Image(systemName: "pip.enter")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Picture in Picture")
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
    }

    // MARK: - Mouse and keyboard

    /// Mirrors PlayerView+Gestures' macTapGesture (click toggles controls, double-click seeks
    /// ±10s) — kept local rather than shared since that extension is scoped to PlayerView,
    /// not this view. Takes the surface's width from the caller's GeometryReader, same as
    /// PlayerView's own version does.
    private func macOfflineTapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let forward = value.location.x > width / 2
                model.seek(by: forward ? 10 : -10)
            }
            .exclusively(before:
                SpatialTapGesture(count: 1)
                    .onEnded { _ in model.toggleControls() }
            )
    }

    private func adjustMacVolume(by delta: Double) {
        macVolume = min(max(macVolume + delta, 0), 1)
        if let vlcEngine = model.player as? VLCEnginePlayer {
            try? vlcEngine.vlcPlayer.setAudioVolume(Volume(Float(macVolume)))
        } else if let aetherEngine = model.player as? AetherEnginePlayer {
            aetherEngine.volume = Float(macVolume)
        }
        macVolumeHUD = macVolume
        macVolumeHUDTask?.cancel()
        macVolumeHUDTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            macVolumeHUD = nil
        }
    }

    private func macOfflineVolumeIndicator(_ volume: Double) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: volume < 0.01 ? "speaker.slash.fill" : volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                    .font(.system(.title3))
                    .foregroundStyle(.white)
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.2)).frame(width: 6, height: 90)
                    Capsule().fill(.white).frame(width: 6, height: 90 * volume)
                }
                Text(Double(volume), format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: volume)
            }
            .padding(14)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: DT.Radius.lg))
        }
        .padding(.horizontal, 32)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
