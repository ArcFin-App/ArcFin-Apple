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
    @State var subtitleCues: [SubtitleCue] = []
    @State var currentSubtitleText: String?
    @State var trickplayLoader: TrickplayLoader?
    @State var scrubThumbnail: UIImage?
    @State var lastThumbnailBucket: Int?
    @State var introEnd: Double?
    @State var creditsStart: Double?
    @State var progressReportTask: Task<Void, Never>?
    @State var seekFeedback: SeekFeedback?
    @State var stallObserver: NSObjectProtocol?
    @State var autoDowngradeTier = 0
    @State var lastStallHandledAt: Date?
    @State var recentStallTimestamps: [Date] = []
    @State var lastLoadStartedAt: Date?
    @State var networkToast: String?

    #if !os(tvOS)
    @StateObject var pip = PiPCoordinator()
    @State var volumeController: SystemVolumeController?
    @State var dragAxis: DragAxis?
    @State var dragBaseline: CGFloat = 0
    @State var dragValue: CGFloat = 0
    @State var lastHapticStep: Int?
    @State var volumeObservation: NSKeyValueObservation?
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

            if let networkToast {
                networkToastView(networkToast)
            }

            if let currentSubtitleText {
                subtitleOverlay(currentSubtitleText)
            }

            if isControlsVisible {
                controlsOverlay
                    .transition(.opacity)
            }

            skipButton
        }
        #if !os(tvOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .task { await setup() }
        .onDisappear { Task { await teardown() } }
        .onChange(of: player.positionTicks) { _, newValue in
            updateSubtitleText(forTicks: newValue)
        }
        .onChange(of: player.status) { _, newStatus in handleStatusChange(newStatus) }
        // These must live on a view that's always mounted, not inside the conditionally
        // -shown controlsOverlay — auto-hide removing that view from the tree while a
        // sheet/dialog was presented from it was tearing the presentation down too.
        .onChange(of: showTrackMenu) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        .onChange(of: showQualityMenu) { _, isOpen in handleMenuVisibilityChange(isOpen) }
        .sheet(isPresented: $showTrackMenu) {
            trackSelectionSheet
        }
        .confirmationDialog("Quality", isPresented: $showQualityMenu, titleVisibility: .visible) {
            qualityMenuButtons
        }
    }

    private func handleStatusChange(_ newStatus: PlaybackStatus) {
        if newStatus == .playing { scheduleAutoHide() }
        if newStatus == .ended { Task { await finishPlayback() } }
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    @ViewBuilder
    private var qualityMenuButtons: some View {
        ForEach(VideoQuality.allCases.filter { $0 != .auto }) { q in
            Button(q.label + (q == quality ? " ✓" : "")) { changeQuality(to: q) }
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Setup / teardown

    private func setup() async {
        #if !os(tvOS)
        volumeController = SystemVolumeController()
        // Playback stalling (buffer underrun) is the standard signal for "network can't
        // keep up" — auto-step quality down when the user hasn't manually picked one.
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in handlePlaybackStall() }
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            // The async activate() API needs iOS 27 — this project's min target is 26, so
            // the synchronous call (and its one-time "may block main thread" advisory,
            // harmless for a single per-session call) stays until the target moves up.
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Not fatal — playback still works, just without the routing/background
            // guarantees .playback gives (this is also what PiP relies on being correct).
        }
        // The hidden MPVolumeView used to set volume programmatically also silently
        // suppresses the system's own volume HUD — observe outputVolume so physical
        // button presses still get a visible indicator via our own overlay.
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor in
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
            await loadSubtitleCues(from: info, credential: credential)
            lastLoadStartedAt = Date()
            try await player.load(url: info.playURL, startPositionTicks: startPositionTicks)
            await player.play()
            #if !os(tvOS)
            pip.activateIfNeeded()
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
        }
    }

    private func teardown() async {
        progressReportTask?.cancel()
        hideControlsTask?.cancel()
        #if !os(tvOS)
        volumeController?.teardown()
        volumeObservation?.invalidate()
        #endif
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
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
        // No forceTranscode — a picked quality is a cap, not a demand to re-encode.
        // If the source already qualifies for direct play under that cap, it should stay
        // direct play (forcing a transcode there was wasteful and confusing: Jellyfin's own
        // dashboard correctly said Direct Play while this app's badge said Transcoding).
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

    /// Only acts when the user hasn't manually picked a quality — a deliberate pick is
    /// never silently overridden by this.
    ///
    /// AVPlayerItemPlaybackStalled fires for plenty of non-network reasons too (seeking,
    /// a reload's own startup buffering, backgrounding) — a single stall is not a reliable
    /// "network can't keep up" signal on its own, and reacting to one caused a reload loop
    /// twice (each reload's startup buffering looked like another stall). Now requires
    /// several stalls clustered in a short window, which normal one-off blips don't produce.
    func handlePlaybackStall() {
        guard quality == .auto || quality == .max else { return }
        if let lastLoad = lastLoadStartedAt, Date().timeIntervalSince(lastLoad) < 12 { return }

        let now = Date()
        recentStallTimestamps.append(now)
        recentStallTimestamps.removeAll { now.timeIntervalSince($0) > 15 }
        guard recentStallTimestamps.count >= 3 else { return }
        recentStallTimestamps.removeAll()

        if let last = lastStallHandledAt, now.timeIntervalSince(last) < 30 { return }
        let tiers: [VideoQuality] = [.p1080, .p720, .p480]
        guard autoDowngradeTier < tiers.count else { return }
        lastStallHandledAt = now
        let next = tiers[autoDowngradeTier]
        autoDowngradeTier += 1
        quality = next
        reload(errorContext: "adjust quality")
        networkToast = "Lowered to \(next.label) — your connection can't keep up"
        Task {
            try? await Task.sleep(for: .seconds(3))
            networkToast = nil
        }
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
