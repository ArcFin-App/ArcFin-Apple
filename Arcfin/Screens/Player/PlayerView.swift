import SwiftUI
import UIKit
import AVFoundation
import AuthCore
import JellyfinAPI
import MediaEngine

struct PlayerView: View {
    let item: MediaItem
    let startPositionTicks: Int64

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) var dismiss

    @State var player = AVFoundationPlayer()
    @State var playbackInfo: JellyfinPlaybackInfo?
    @State var errorMessage: String?
    @State var isControlsVisible = true
    @State var hideControlsTask: Task<Void, Never>?
    @State var isScrubbing = false
    @State var scrubTicks: Double = 0
    @State var showTrackMenu = false
    @State var showQualityMenu = false
    @State var quality: VideoQuality
    @State var selectedAudioIndex: Int?
    @State var selectedSubtitleIndex: Int?
    @State var trickplayLoader: TrickplayLoader?
    @State var scrubThumbnail: UIImage?
    @State var lastThumbnailBucket: Int?
    @State var introEnd: Double?
    @State var creditsStart: Double?
    @State var progressReportTask: Task<Void, Never>?
    @State var seekFeedback: SeekFeedback?

    #if !os(tvOS)
    @StateObject var pip = PiPCoordinator()
    @State var volumeController: SystemVolumeController?
    @State var dragAxis: DragAxis?
    @State var dragBaseline: CGFloat = 0
    @State var dragValue: CGFloat = 0
    @State var lastHapticStep: Int?
    #endif

    let client = JellyfinMediaClient()

    enum DragAxis { case brightness, volume }
    struct SeekFeedback: Identifiable, Equatable {
        let id = UUID()
        let forward: Bool
    }

    init(item: MediaItem, startPositionTicks: Int64 = 0) {
        self.item = item
        self.startPositionTicks = startPositionTicks
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
            GeometryReader { proxy in
                PlayerLayerRepresentable(player: player.player, pip: pip)
                    .contentShape(Rectangle())
                    .gesture(tapGesture(width: proxy.size.width))
                    .simultaneousGesture(dragGesture(width: proxy.size.width))
            }
            .ignoresSafeArea()
            #endif

            if let seekFeedback {
                seekFeedbackView(seekFeedback)
            }

            #if !os(tvOS)
            dragAxisIndicator
            #endif

            if player.status == .loading || player.isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.4)
            }

            if let errorMessage {
                errorView(errorMessage)
            }

            if isControlsVisible {
                controlsOverlay
                    .transition(.opacity)
            }

            skipButton
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await setup() }
        .onDisappear { Task { await teardown() } }
        .onChange(of: player.status) { _, newStatus in
            if newStatus == .playing { scheduleAutoHide() }
            if newStatus == .ended { Task { await finishPlayback() } }
        }
    }

    // MARK: - Setup / teardown

    private func setup() async {
        #if !os(tvOS)
        volumeController = SystemVolumeController()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Not fatal — playback still works, just without the routing/background
            // guarantees .playback gives (this is also what PiP relies on being correct).
        }
        #endif
        guard let credential, let authHeader else {
            errorMessage = "Not signed in."
            return
        }
        do {
            let info = try await client.getPlaybackInfo(
                credential: credential, authHeader: authHeader, itemId: item.id,
                quality: qualityCap(for: quality)
            )
            playbackInfo = info
            selectedAudioIndex = info.defaultAudioStreamIndex
            selectedSubtitleIndex = info.defaultSubtitleStreamIndex
            if let trickplay = info.trickplay {
                trickplayLoader = TrickplayLoader(credential: credential, client: client, itemId: item.id, info: trickplay)
            }
            try await player.load(url: info.playURL, startPositionTicks: startPositionTicks)
            await player.play()
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
        }
    }

    private func teardown() async {
        progressReportTask?.cancel()
        hideControlsTask?.cancel()
        #if !os(tvOS)
        volumeController?.teardown()
        #endif
        if let credential, let authHeader, let info = playbackInfo {
            await client.reportPlaybackStopped(credential: credential, authHeader: authHeader,
                                               itemId: item.id, mediaSourceId: info.mediaSourceId,
                                               positionTicks: player.positionTicks)
        }
        await player.stop()
        #if !os(tvOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    func finishPlayback() async {
        guard let credential, let authHeader else { return }
        _ = try? await client.markWatched(credential: credential, authHeader: authHeader, itemId: item.id, watched: true)
        dismiss()
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

    private func qualityCap(for quality: VideoQuality) -> StreamQualityCap {
        switch quality {
        case .max, .auto: .auto
        case .p4k:   StreamQualityCap(maxBitrate: 100_000_000, maxWidth: 3840)
        case .p1080: StreamQualityCap(maxBitrate: 20_000_000, maxWidth: 1920)
        case .p720:  StreamQualityCap(maxBitrate: 8_000_000, maxWidth: 1280)
        case .p480:  StreamQualityCap(maxBitrate: 4_000_000, maxWidth: 854)
        }
    }

    func changeQuality(to newQuality: VideoQuality) {
        guard newQuality != quality else { return }
        quality = newQuality
        reload(errorContext: "switch quality")
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
                try await player.load(url: info.playURL, startPositionTicks: resumeTicks)
                await player.play()
                startProgressReporting(mediaSourceId: info.mediaSourceId)
            } catch {
                errorMessage = "Couldn't \(errorContext): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Controls visibility

    func scheduleAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, player.status == .playing else { return }
            withAnimation(DT.Animation.fast) { isControlsVisible = false }
        }
    }

    func toggleControls() {
        withAnimation(DT.Animation.fast) { isControlsVisible.toggle() }
        if isControlsVisible { scheduleAutoHide() }
    }
}
