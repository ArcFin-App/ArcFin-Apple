import SwiftUI
import SwiftData
import AVFoundation
import AVKit
import MediaEngine
import Persistence
import SwiftVLC
#if canImport(UIKit)
import UIKit
#endif

/// Fully offline playback of a DownloadedItem — no network calls of any kind. Simpler than
/// PlayerView by design: no quality/transcode menu (there's exactly one file), no server
/// progress reporting (position is saved to the local SwiftData record instead).
struct OfflinePlayerView: View {
    let downloadedItem: DownloadedItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Always VLC, not AVFoundation — a downloaded file's container/codec can be anything the
    // server has, and VLC plays that natively without AVFoundation's mkv/HEVC-tag limitations.
    @State private var player = VLCEnginePlayer()
    @State private var isControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubTicks: Double = 0
    @State private var subtitleCues: [SubtitleCue] = []
    @State private var currentSubtitleText: String?
    @State private var selectedSubtitleIndex: Int?
    @State private var showTrackMenu = false
    @State private var progressSaveTask: Task<Void, Never>?
    #if canImport(UIKit) && !os(tvOS)
    @State private var vlcPipController: SwiftVLC.PiPController?
    #endif

    private var dir: URL { DownloadStore.directory(for: downloadedItem.itemId) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if canImport(UIKit) && !os(tvOS)
            GeometryReader { proxy in
                PiPVideoView(player.vlcPlayer, controller: $vlcPipController, managesAudioSession: false)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
            }
            .ignoresSafeArea()
            #endif

            if player.status == .loading || player.isBuffering {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if let currentSubtitleText {
                VStack {
                    Spacer()
                    Text(currentSubtitleText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 24)
                        .padding(.bottom, isControlsVisible ? 110 : 32)
                }
                .allowsHitTesting(false)
            }

            if isControlsVisible {
                controlsOverlay.transition(.opacity)
            }
        }
        #if canImport(UIKit) && !os(tvOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .task { await setup() }
        .onDisappear { savePosition(final: true) }
        .onChange(of: player.positionTicks) { _, newValue in
            updateSubtitleText(forTicks: newValue)
        }
        .onChange(of: player.status) { _, status in
            if status == .playing { scheduleAutoHide() }
            if status == .ended { savePosition(final: true); dismiss() }
        }
        .sheet(isPresented: $showTrackMenu) {
            subtitleSheet
        }
    }

    // MARK: - Setup

    private func setup() async {
        #if canImport(UIKit) && !os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let videoURL = dir.appendingPathComponent(downloadedItem.videoFileName)
        do {
            try await player.load(url: videoURL, startPositionTicks: downloadedItem.playbackPositionTicks)
            await player.play()
        } catch {
            // Nothing more to fall back to offline — surfaced via the stalled/failed state
            // the controls overlay already reflects through player.status.
        }
        startProgressSaving()
    }

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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(downloadedItem.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Downloaded")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
            }
            Spacer()
            #if canImport(UIKit) && !os(tvOS)
            AirPlayButton().frame(width: 30, height: 30)
            if AVPictureInPictureController.isPictureInPictureSupported() {
                Button { vlcPipController?.toggle() } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
            }
            #endif
            if !downloadedItem.subtitleFileNames.isEmpty {
                Button { showTrackMenu = true } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
            }
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
                        Text(label).font(.system(size: 14, weight: .semibold))
                        Image(systemName: "forward.fill").font(.system(size: 12))
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
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 28) {
                    Button { seek(by: -10) } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 20)).foregroundStyle(.white)
                    }
                    Button { togglePlayPause() } label: {
                        Image(systemName: player.status == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    Button { seek(by: 10) } label: {
                        Image(systemName: "goforward.10").font(.system(size: 20)).foregroundStyle(.white)
                    }
                }
                Spacer()
                Text(remainingLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
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
            #if canImport(UIKit) && !os(tvOS)
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
    }

    private var trickplayPreview: some View {
        Group {
            #if canImport(UIKit)
            if let image = trickplayImage(forTicks: Int64(scrubTicks)) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
            #else
            Color.black
            #endif
        }
        .frame(width: 140, height: 79)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 1))
        .shadow(radius: 8)
        .allowsHitTesting(false)
    }

    #if canImport(UIKit)
    private func trickplayImage(forTicks ticks: Int64) -> UIImage? {
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
              let tileImage = UIImage(contentsOfFile: dir.appendingPathComponent(downloadedItem.trickplayFileNames[tileIndex]).path),
              let cgTile = tileImage.cgImage
        else { return nil }
        let cropRect = CGRect(x: col * width, y: row * height, width: width, height: height)
        guard let cropped = cgTile.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped)
    }
    #endif

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
