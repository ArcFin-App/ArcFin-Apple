// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import AVFoundation
import AuthCore
import Combine
import JellyfinAPI
import SwiftUI
import Telemetry
import UIKit
import YouTubePlayerKit
import os

/// Long-pressing a poster opens this: the title's local trailer playing muted, a button to
/// unmute, and a tap on the video that continues the trailer full screen from the same spot.
/// Titles with no local trailer fall back to their YouTube trailer, when they have one, or
/// just the backdrop.
@MainActor
@Observable
final class TrailerPreviewModel {
    /// What the preview is showing, best source first.
    enum Source: Equatable {
        case none
        case localTrailer(MediaItem)
        case youTube(String)
        /// A short stretch from the middle of the movie or episode itself.
        case clip
    }

    private(set) var player: AVPlayer?
    private(set) var youTubePlayer: YouTubePlayer?
    private(set) var source: Source = .none
    private(set) var isPlaying = false
    private(set) var isLoading = true
    var isMuted = true {
        didSet {
            player?.isMuted = isMuted
            if let youTubePlayer {
                let muted = isMuted
                Task { if muted { try? await youTubePlayer.mute() } else { try? await youTubePlayer.unmute() } }
            }
        }
    }
    var hasMedia: Bool { player != nil || youTubePlayer != nil }

    @ObservationIgnored private var cancellable: AnyCancellable?
    @ObservationIgnored private var loopObserver: NSObjectProtocol?

    var currentTicks: Int64 {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
        return Int64(seconds * 10_000_000)
    }

    func load(for item: MediaItem, credential: ServerCredential, authHeader: String) async {
        let client = JellyfinMediaClient()
        defer { isLoading = false }
        if let local = try? await client.getTrailers(
            credential: credential, authHeader: authHeader, itemId: item.id, limit: 1).first,
           let info = try? await client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: local.id) {
            source = .localTrailer(local)
            start(url: info.playURL)
            return
        }
        let detail = try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: item.id)
        if let id = detail?.remoteTrailers.first(where: { $0.youTubeVideoID != nil })?.youTubeVideoID {
            source = .youTube(id)
            youTubePlayer = YouTubePlayer(
                source: .video(id: id),
                parameters: .init(autoPlay: false, loopEnabled: true, showControls: false),
                configuration: .init(useNonPersistentWebsiteDataStore: true))
            return
        }
        // No trailer anywhere: preview the title itself, a few minutes in, when it can be played.
        if item.type == .movie || item.type == .episode,
           let info = try? await client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: item.id) {
            source = .clip
            let runtime = detail?.runTimeTicks ?? 0
            let startSeconds = runtime > 0 ? Double(runtime) / 10_000_000 * 0.2 : 300
            start(url: info.playURL, at: startSeconds)
        }
    }

    /// Called once the YouTube embed reports ready: muted first, then play, so no sound
    /// escapes before the mute takes effect.
    func youTubeReady() async {
        guard let youTubePlayer else { return }
        try? await youTubePlayer.mute()
        try? await youTubePlayer.play()
    }

    /// Where the YouTube preview currently is, in seconds.
    func youTubeSeconds() async -> Double {
        guard let youTubePlayer, let time = try? await youTubePlayer.getCurrentTime() else { return 0 }
        return time.converted(to: .seconds).value
    }

    private func start(url: URL, at seconds: Double = 0) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.actionAtItemEnd = .none
        self.player = player
        cancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = status == .playing }
        loopObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        if seconds > 0 {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        }
        player.play()
    }

    func toggleMute() {
        isMuted.toggle()
        if !isMuted {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    func pause() {
        player?.pause()
        if let youTubePlayer { Task { try? await youTubePlayer.pause() } }
    }
    func resume() {
        player?.play()
        if let youTubePlayer { Task { try? await youTubePlayer.play() } }
    }

    func stop() {
        player?.pause()
        player = nil
        if let youTubePlayer { Task { try? await youTubePlayer.pause() } }
        youTubePlayer = nil
        cancellable = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
    }
}

private struct PreviewVideoView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PreviewPlayerUIView {
        let view = PreviewPlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewPlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PreviewPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct TrailerPreviewSheet<Actions: View>: View {
    let item: MediaItem
    let onDetails: (MediaItem) -> Void
    /// The full set of quick actions for the item, supplied by the screen that opened this
    /// so it matches what the old context menu offered there.
    @ViewBuilder let actions: () -> Actions

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.dismiss) private var dismiss
    @State private var model = TrailerPreviewModel()
    @State private var trailerPlayback: PlaybackRequest?
    @State private var youTubeStart: Double?
    @State private var showPlayer = false

    private var resumeTicks: Int64 {
        guard let data = item.userData, !data.played else { return 0 }
        return data.playbackPositionTicks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            videoArea
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.type == .episode ? (item.seriesName ?? item.name) : item.name)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                HStack(spacing: 8) {
                    if let year = item.productionYear { Text(String(year)) }
                    if let rating = item.communityRating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
                }
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(4)
                }
            }

            HStack(spacing: 12) {
                // Series and collections aren't directly playable; their detail screen
                // picks the right episode or title.
                if item.type == .movie || item.type == .episode {
                Button { showPlayer = true } label: {
                    Label(resumeTicks > 0 ? "Resume" : "Play", systemImage: "play.fill")
                        .font(.system(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white, in: RoundedRectangle(cornerRadius: DT.Radius.md))
                        .foregroundStyle(.black)
                }
                }
                Button {
                    dismiss()
                    onDetails(item)
                } label: {
                    Label("Details", systemImage: "info.circle")
                        .font(.system(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: DT.Radius.md))
                        .foregroundStyle(.white)
                }
                Menu {
                    actions()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(.body, weight: .semibold))
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.14), in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("More actions")
            }
            Spacer(minLength: 0)
        }
        .padding(DT.Spacing.pagePad)
        .background(DT.Color.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .task {
            guard let credential = authManager.state.credential else { return }
            let header = authManager.authClient.authHeader(token: credential.accessToken)
            await model.load(for: item, credential: credential, authHeader: header)
        }
        .onDisappear { model.stop() }
        .fullScreenCover(item: $trailerPlayback, onDismiss: { model.resume() }) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks)
        }
        .fullScreenCover(isPresented: Binding(
            get: { youTubeStart != nil }, set: { if !$0 { youTubeStart = nil; model.resume() } }
        )) {
            if case .youTube(let id) = model.source {
                YouTubeTrailerPlayerView(videoID: id, title: item.name, startSeconds: youTubeStart)
            }
        }
        .fullScreenCover(isPresented: $showPlayer, onDismiss: { model.resume() }) {
            PlayerView(item: item, startPositionTicks: resumeTicks)
        }
        .onChange(of: showPlayer) { _, isShown in if isShown { model.pause() } }
    }

    @ViewBuilder
    private var videoArea: some View {
        ZStack {
            if let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 800)
                ?? mediaRepo.imageURL(for: item, type: .primary, fillWidth: 800) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        DT.Color.backgroundSecondary
                    }
                }
            } else {
                DT.Color.backgroundSecondary
            }

            if let player = model.player {
                PreviewVideoView(player: player)
                    .opacity(model.isPlaying ? 1 : 0)
                    .animation(.easeIn(duration: 0.3), value: model.isPlaying)
            }

            if let youTube = model.youTubePlayer {
                YouTubePlayerView(youTube) { state in
                    switch state {
                    case .idle:
                        ProgressView().tint(.white)
                    case .ready:
                        Color.clear.task { await model.youTubeReady() }
                    case .error:
                        EmptyView()
                    }
                }
                .allowsHitTesting(false)
            }

            if model.isLoading {
                ProgressView().tint(.white)
            } else if !model.hasMedia {
                VStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 28))
                    Text("No trailer available")
                        .font(.system(.footnote, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(10)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: DT.Radius.md))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openTrailer() }
        .overlay(alignment: .bottomTrailing) {
            if model.hasMedia {
                Button { model.toggleMute() } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                }
                .accessibilityLabel(model.isMuted ? "Unmute" : "Mute")
                .padding(10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Trailer for \(item.name)")
        .accessibilityHint(model.hasMedia ? "Opens the trailer full screen" : "")
    }

    /// Continues the trailer full screen from where the preview currently is.
    private func openTrailer() {
        switch model.source {
        case .localTrailer(let trailer):
            let start = model.currentTicks
            model.pause()
            trailerPlayback = PlaybackRequest(item: trailer, startTicks: start)
        case .clip:
            let start = model.currentTicks
            model.pause()
            trailerPlayback = PlaybackRequest(item: item, startTicks: start)
        case .youTube:
            Task {
                let seconds = await model.youTubeSeconds()
                model.pause()
                youTubeStart = seconds
            }
        case .none:
            break
        }
    }
}
#endif
