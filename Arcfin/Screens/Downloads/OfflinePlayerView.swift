// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import MediaEngine
import Persistence
import SwiftVLC
#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Fully offline playback of a DownloadedItem — no network calls of any kind. Simpler than
/// PlayerView by design: no quality/transcode menu (there's exactly one file), no server
/// progress reporting (position is saved to the local SwiftData record instead).
struct OfflinePlayerView: View {
    let downloadedItem: DownloadedItem
    /// Overrides the saved resume position — nil (the default) resumes from
    /// downloadedItem.playbackPositionTicks as before; 0 is how "Start Over" is expressed.
    var startPositionOverride: Int64? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloadManager
    @AppStorage("deleteDownloadsAfterWatching") private var deleteAfterWatching = false

    // Aether first, same as the online PlayerView — handles whatever container/codec the
    // server has, including what used to force VLC here (AVFoundation's mkv/HEVC-tag
    // limitations). Falls back to VLC if Aether itself can't construct or open this file
    // (see setup()); VLC stays the fallback rather than AVFoundation for the same reason the
    // comment this replaced gave — a downloaded file's container/codec can be anything.
    @State private var player: any MediaPlayerProtocol = (try? AetherEnginePlayer()) ?? VLCEnginePlayer()
    @State private var isControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubTicks: Double = 0
    @State private var subtitleCues: [SubtitleCue] = []
    @State private var currentSubtitleText: String?
    @State private var selectedSubtitleIndex: Int?
    @State private var showTrackMenu = false
    @AppStorage("subtitleTextSize") private var subtitleTextSize = SubtitleTextSize.medium
    @AppStorage("subtitleTextColor") private var subtitleTextColor = SubtitleTextColorOption.white
    @AppStorage("subtitleBackgroundStyle") private var subtitleBackgroundStyle = SubtitleBackgroundStyle.outline
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 10
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 10
    @State private var progressSaveTask: Task<Void, Never>?
    #if !os(tvOS)
    @State private var vlcPipController: SwiftVLC.PiPController?
    @State private var isFillScreen = false
    #endif
    #if os(macOS)
    @State private var macWindow: NSWindow?
    @State private var isMacFullScreen = false
    @State private var macVolume: Double = 1.0
    @State private var macVolumeHUD: Double?
    @State private var macVolumeHUDTask: Task<Void, Never>?
    @FocusState private var isPlayerFocused: Bool
    @State private var lastMacHoverLocation: CGPoint?
    #endif

    private var dir: URL { DownloadStore.directory(for: downloadedItem.itemId) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if !os(tvOS)
            GeometryReader { proxy in
                // PiPVideoView's native drawable is itself interactive (unlike AVFoundation's
                // inert surface) and was swallowing the tap before onTapGesture below saw it.
                // The gesture lives on this separate wrapping ZStack, not on PiPVideoView
                // itself, so disabling hit-testing on the surface can't also disable it.
                ZStack {
                    if let vlcEngine = player as? VLCEnginePlayer {
                        PiPVideoView(vlcEngine.vlcPlayer, controller: $vlcPipController, managesAudioSession: false)
                            .allowsHitTesting(false)
                    } else if let aetherEngine = player as? AetherEnginePlayer {
                        AetherEngineVideoSurface(player: aetherEngine)
                            .allowsHitTesting(false)
                    }
                }
                // See PlayerView's own note — GeometryReader only proposes its size, it
                // doesn't force it, so the video surface needs pinning to proxy.size explicitly
                // or it's free to size itself off its own content instead of the screen.
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                #if canImport(UIKit)
                .onTapGesture { toggleControls() }
                #elseif os(macOS)
                .gesture(macOfflineTapGesture(width: proxy.size.width))
                // See PlayerView's own note — onContinuousHover fires on more than genuine
                // pointer movement, which kept resetting the auto-hide timer nonstop.
                .onContinuousHover { phase in
                    guard case .active(let location) = phase, location != lastMacHoverLocation else { return }
                    lastMacHoverLocation = location
                    handleMacMouseActivity()
                }
                #endif
            }
            .ignoresSafeArea()
            #endif

            // .idle covers the gap between the screen appearing and setup() actually calling
            // player.load() — without it the screen was just black with no spinner there.
            if player.status == .idle || player.status == .loading || player.isBuffering {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if let currentSubtitleText {
                // See PlayerView+Controls.subtitleOverlay — the fixed bottom padding alone
                // isn't a substitute for the safe area; reading the real inset via
                // GeometryReader and adding it explicitly guarantees clearance from the
                // home indicator regardless of what the rest of the hierarchy is doing
                // with safe areas.
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        SubtitleText(text: currentSubtitleText, size: subtitleTextSize, color: subtitleTextColor, background: subtitleBackgroundStyle)
                            .padding(.horizontal, 24)
                            .padding(.bottom, (isControlsVisible ? 110 : 32) + proxy.safeAreaInsets.bottom)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // Always mounted — see PlayerView's own note on why conditionally mounting this
            // (mount/unmount on every tap) was the real cause of the video+UI zoom glitch.
            controlsOverlay
                .opacity(isControlsVisible ? 1 : 0)
                .allowsHitTesting(isControlsVisible)

            #if os(macOS)
            if let macVolumeHUD {
                macOfflineVolumeIndicator(macVolumeHUD)
            }
            #endif
        }
        #if canImport(UIKit) && !os(tvOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .task { await setup() }
        .onDisappear {
            savePosition(final: true)
            // Dismissing (back chevron, Escape) previously left VLC playing in the
            // background with no way to stop it short of killing the app — the player
            // was never actually told to stop, just visually torn down.
            Task {
                await player.stop()
                #if canImport(UIKit) && !os(tvOS)
                await deactivateAudioSession()
                #endif
            }
            #if canImport(UIKit) && !os(tvOS)
            resetPlayerOrientation()
            #elseif os(macOS)
            macVolumeHUDTask?.cancel()
            #endif
        }
        .onChange(of: player.positionTicks) { _, newValue in
            updateSubtitleText(forTicks: newValue)
        }
        .onChange(of: player.status) { _, status in
            if status == .playing { scheduleAutoHide() }
            if status == .ended {
                savePosition(final: true)
                if deleteAfterWatching {
                    downloadManager.markForDeletionAfterWatching(itemId: downloadedItem.itemId)
                }
                dismiss()
            }
        }
        #if !os(tvOS)
        .onChange(of: isFillScreen) { _, newValue in
            if let vlcEngine = player as? VLCEnginePlayer {
                vlcEngine.vlcPlayer.aspectRatio = newValue ? .fill : .default
            } else if let aetherEngine = player as? AetherEnginePlayer {
                aetherEngine.isFillScreen = newValue
            }
        }
        #endif
        .sheet(isPresented: $showTrackMenu) {
            subtitleSheet
        }
        #if os(macOS)
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
                dismiss()
            }
            return .handled
        }
        #endif
    }

    // MARK: - Setup

    private func setup() async {
        #if canImport(UIKit) && !os(tvOS)
        await activateAudioSession()
        #endif
        let videoURL = dir.appendingPathComponent(downloadedItem.videoFileName)
        let startTicks = startPositionOverride ?? downloadedItem.playbackPositionTicks
        do {
            try await player.load(url: videoURL, startPositionTicks: startTicks)
        } catch where player is AetherEnginePlayer {
            // Same runtime fallback as the online PlayerView — DownloadedItem has no stored
            // container/codec metadata to run a real pre-flight check against offline, so
            // this only ever triggers reactively, on an actual Aether load failure.
            player = VLCEnginePlayer()
            try? await player.load(url: videoURL, startPositionTicks: startTicks)
        } catch {
            // Nothing more to fall back to offline — surfaced via the stalled/failed state
            // the controls overlay already reflects through player.status.
        }
        await player.play()
        startProgressSaving()
    }

    #if canImport(UIKit) && !os(tvOS)
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
    #endif

    private func startProgressSaving() {
        progressSaveTask?.cancel()
        progressSaveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                savePosition(final: false)
            }
        }
    }

    private func savePosition(final: Bool) {
        downloadedItem.playbackPositionTicks = player.positionTicks
        if player.durationTicks > 0 {
            downloadedItem.played = Double(player.positionTicks) / Double(player.durationTicks) >= 0.9
        }
        // Picked up by OfflineProgressSync once the app's back online — this is the only
        // record that playback happened at all while offline.
        downloadedItem.needsSync = true
        try? modelContext.save()
        if final { progressSaveTask?.cancel() }
    }

    // MARK: - Subtitles

    private func loadSubtitles(index: Int?) {
        selectedSubtitleIndex = index
        guard let index, downloadedItem.subtitleFileNames.indices.contains(index) else {
            subtitleCues = []
            currentSubtitleText = nil
            return
        }
        let fileURL = dir.appendingPathComponent(downloadedItem.subtitleFileNames[index])
        subtitleCues = SubtitleLoader.loadCues(fileURL: fileURL)
    }

    private func updateSubtitleText(forTicks ticks: Int64) {
        guard !subtitleCues.isEmpty else { currentSubtitleText = nil; return }
        currentSubtitleText = SubtitleLoader.cue(at: Double(ticks) / 10_000_000, in: subtitleCues)
    }

    // MARK: - Controls

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            skipButton
            bottomBar
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.7),
                    .init(color: .black.opacity(0.65), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
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
            #if canImport(UIKit) && !os(tvOS)
            AirPlayButton().frame(width: 44, height: 44)
            #endif
            if !downloadedItem.subtitleFileNames.isEmpty {
                Button { showTrackMenu = true } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
            }
            #if canImport(UIKit) && !os(tvOS)
            Menu {
                if AVPictureInPictureController.isPictureInPictureSupported() {
                    Button { vlcPipController?.toggle() } label: {
                        Label("Picture in Picture", systemImage: "pip.enter")
                    }
                }
                Button { togglePlayerOrientation() } label: {
                    Label("Rotate", systemImage: "rotate.right")
                }
                Button { isFillScreen.toggle() } label: {
                    Label(isFillScreen ? "Fit to Screen" : "Fill Screen",
                          systemImage: isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("More options")
            #elseif os(macOS)
            HStack(spacing: 14) {
                Button { isFillScreen.toggle() } label: {
                    Image(systemName: isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(isFillScreen ? "Fit to screen" : "Fill screen")
                .buttonStyle(.plain)
                Button { toggleMacWindowFullScreen(macWindow) } label: {
                    Image(systemName: isMacFullScreen ? "arrow.down.right.and.arrow.up.left.circle" : "arrow.up.left.and.arrow.down.right.circle")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Toggle full screen")
                .buttonStyle(.plain)
                if AVPictureInPictureController.isPictureInPictureSupported() {
                    Button { vlcPipController?.toggle() } label: {
                        Image(systemName: "pip.enter")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Picture in Picture")
                    .buttonStyle(.plain)
                }
            }
            #endif
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var skipButton: some View {
        if let label = skipButtonLabel {
            HStack {
                Spacer()
                Button { skipToSegmentEnd() } label: {
                    HStack(spacing: 6) {
                        Text(label).font(.system(.footnote, design: .default, weight: .semibold))
                        Image(systemName: "forward.fill").font(.system(.caption))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                }
                .padding(.trailing, DT.Spacing.pagePad)
                .padding(.bottom, 100)
            }
        }
    }

    private var skipButtonLabel: String? {
        let seconds = Double(isScrubbing ? Int64(scrubTicks) : player.positionTicks) / 10_000_000
        if let introEnd = downloadedItem.introEndSeconds, seconds < introEnd, seconds > 0.5 {
            return "Skip Intro"
        }
        if let creditsStart = downloadedItem.creditsStartSeconds, seconds >= creditsStart {
            return "Skip Credits"
        }
        return nil
    }

    private func skipToSegmentEnd() {
        let seconds = Double(player.positionTicks) / 10_000_000
        if let introEnd = downloadedItem.introEndSeconds, seconds < introEnd {
            Task { await player.seek(to: Int64(introEnd * 10_000_000)) }
        } else if let creditsStart = downloadedItem.creditsStartSeconds, seconds >= creditsStart {
            savePosition(final: true)
            dismiss()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            scrubber
            HStack {
                Text(timeLabel(ticks: isScrubbing ? Int64(scrubTicks) : player.positionTicks))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 28) {
                    Button { seek(by: -skipBackwardSeconds) } label: {
                        Image(systemName: skipIconName(seconds: skipBackwardSeconds, forward: false))
                            .font(.system(.title3)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Skip back \(skipBackwardSeconds) seconds")
                    Button { togglePlayPause() } label: {
                        Image(systemName: player.status == .playing ? "pause.fill" : "play.fill")
                            .font(.system(.largeTitle))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(player.status == .playing ? "Pause" : "Play")
                    Button { seek(by: skipForwardSeconds) } label: {
                        Image(systemName: skipIconName(seconds: skipForwardSeconds, forward: true))
                            .font(.system(.title3)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Skip forward \(skipForwardSeconds) seconds")
                }
                Spacer()
                Text(remainingLabel)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, 24)
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            let duration = max(player.durationTicks, 1)
            let fraction = Double(isScrubbing ? Int64(scrubTicks) : player.positionTicks) / Double(duration)
            let thumbX = proxy.size.width * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                Capsule().fill(DT.Color.accent).frame(width: thumbX, height: 4)
                Circle().fill(.white)
                    .frame(width: isScrubbing ? 16 : 10, height: isScrubbing ? 16 : 10)
                    .offset(x: thumbX - (isScrubbing ? 8 : 5))

                if isScrubbing, !downloadedItem.trickplayFileNames.isEmpty {
                    trickplayPreview
                        .offset(x: min(max(thumbX - 70, 0), proxy.size.width - 140), y: -100)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            // DragGesture tracks a mouse drag on macOS the same way it tracks a touch drag —
            // no platform split needed here.
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        hideControlsTask?.cancel()
                        let fraction = min(max(value.location.x / proxy.size.width, 0), 1)
                        scrubTicks = Double(player.durationTicks) * fraction
                    }
                    .onEnded { _ in
                        Task {
                            await player.seek(to: Int64(scrubTicks))
                            isScrubbing = false
                            scheduleAutoHide()
                        }
                    }
            )
            #endif
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(timeLabel(ticks: isScrubbing ? Int64(scrubTicks) : player.positionTicks)) of \(timeLabel(ticks: player.durationTicks))")
        .accessibilityAdjustableAction { direction in
            seek(by: direction == .increment ? skipForwardSeconds : -skipBackwardSeconds)
        }
    }

    private var trickplayPreview: some View {
        Group {
            if let image = trickplayImage(forTicks: Int64(scrubTicks)) {
                Image(platformImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
        .frame(width: 140, height: 79)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 1))
        .shadow(radius: 8)
        .allowsHitTesting(false)
    }

    private func trickplayImage(forTicks ticks: Int64) -> PlatformImage? {
        guard let intervalMs = downloadedItem.trickplayIntervalMs, intervalMs > 0,
              let thumbnailCount = downloadedItem.trickplayThumbnailCount, thumbnailCount > 0,
              let tileWidth = downloadedItem.trickplayTileWidth, tileWidth > 0,
              let tileHeight = downloadedItem.trickplayTileHeight, tileHeight > 0,
              let width = downloadedItem.trickplayWidth, let height = downloadedItem.trickplayHeight
        else { return nil }
        let positionMs = Int(Double(ticks) / 10_000)
        let thumbIndex = min(max(positionMs / intervalMs, 0), thumbnailCount - 1)
        let gridSize = max(tileWidth * tileHeight, 1)
        let tileIndex = thumbIndex / gridSize
        let indexInTile = thumbIndex % gridSize
        let row = indexInTile / tileWidth
        let col = indexInTile % tileWidth
        guard downloadedItem.trickplayFileNames.indices.contains(tileIndex),
              let tileImage = PlatformImage.from(contentsOfFile: dir.appendingPathComponent(downloadedItem.trickplayFileNames[tileIndex]).path),
              let cgTile = tileImage.cgImageRepresentation
        else { return nil }
        let cropRect = CGRect(x: col * width, y: row * height, width: width, height: height)
        guard let cropped = cgTile.cropping(to: cropRect) else { return nil }
        return PlatformImage.from(cgImage: cropped)
    }

    private var subtitleSheet: some View {
        NavigationStack {
            List {
                Button {
                    loadSubtitles(index: nil)
                    showTrackMenu = false
                } label: {
                    HStack {
                        Text("Off")
                        Spacer()
                        if selectedSubtitleIndex == nil { Image(systemName: "checkmark") }
                    }
                }
                ForEach(downloadedItem.subtitleLanguages.indices, id: \.self) { index in
                    Button {
                        loadSubtitles(index: index)
                        showTrackMenu = false
                    } label: {
                        HStack {
                            Text(downloadedItem.subtitleLanguages[index])
                            Spacer()
                            if selectedSubtitleIndex == index { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            .navigationTitle("Subtitles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium])
    }

    // MARK: - macOS mouse/keyboard

    #if os(macOS)
    /// Mirrors PlayerView+Gestures' macTapGesture (click toggles controls, double-click seeks
    /// ±10s) — kept local rather than shared since that extension is scoped to PlayerView,
    /// not this view. Takes the surface's width from the caller's GeometryReader, same as
    /// PlayerView's own version does.
    private func macOfflineTapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let forward = value.location.x > width / 2
                seek(by: forward ? 10 : -10)
            }
            .exclusively(before:
                SpatialTapGesture(count: 1)
                    .onEnded { _ in toggleControls() }
            )
    }

    private func handleMacMouseActivity() {
        if !isControlsVisible {
            withAnimation(DT.Animation.fast) { isControlsVisible = true }
        }
        scheduleAutoHide()
    }

    private func adjustMacVolume(by delta: Double) {
        macVolume = min(max(macVolume + delta, 0), 1)
        if let vlcEngine = player as? VLCEnginePlayer {
            try? vlcEngine.vlcPlayer.setAudioVolume(Volume(Float(macVolume)))
        } else if let aetherEngine = player as? AetherEnginePlayer {
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
                Text("\(Int(volume * 100))%")
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
    #endif

    // MARK: - Actions

    private func togglePlayPause() {
        Task { if player.status == .playing { await player.pause() } else { await player.play() } }
        toggleControlsVisibilityOnAction()
    }

    private func seek(by seconds: Int) {
        let newTicks = max(0, player.positionTicks + Int64(seconds) * 10_000_000)
        Task { await player.seek(to: min(newTicks, player.durationTicks)) }
        toggleControlsVisibilityOnAction()
    }

    private func toggleControls() {
        withAnimation(DT.Animation.fast) { isControlsVisible.toggle() }
        if isControlsVisible { scheduleAutoHide() }
    }

    private func toggleControlsVisibilityOnAction() {
        if !isControlsVisible { withAnimation(DT.Animation.fast) { isControlsVisible = true } }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, player.status == .playing else { return }
            withAnimation(DT.Animation.fast) { isControlsVisible = false }
        }
    }

    private var remainingLabel: String {
        let remaining = max(player.durationTicks - player.positionTicks, 0)
        return "-" + timeLabel(ticks: remaining)
    }

    private func timeLabel(ticks: Int64) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
