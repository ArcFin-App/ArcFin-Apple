// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import AVFoundation
import AuthCore
import Combine
import JellyfinAPI
import SwiftUI
import Telemetry
import UIKit
import os

/// Long-pressing a poster opens this: the title's local trailer playing muted, a button to
/// unmute, and a tap on the video that continues the trailer full screen from the same spot.
/// Titles with no local trailer fall back to their YouTube trailer, when they have one, or
/// just the backdrop.
@MainActor
@Observable
final class TrailerPreviewModel {
    private(set) var player: AVPlayer?
    private(set) var trailer: MediaItem?
    private(set) var youTubeID: String?
    private(set) var isPlaying = false
    private(set) var isLoading = true
    var isMuted = true {
        didSet { player?.isMuted = isMuted }
    }

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
            trailer = local
            start(url: info.playURL)
            return
        }
        let detail = try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: item.id)
        youTubeID = detail?.remoteTrailers.first { $0.youTubeVideoID != nil }?.youTubeVideoID
    }

    private func start(url: URL) {
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
        player.play()
    }

    func toggleMute() {
        isMuted.toggle()
        if !isMuted {
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    func pause() { player?.pause() }
    func resume() { player?.play() }

    func stop() {
        player?.pause()
        player = nil
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

struct TrailerPreviewSheet: View {
    let item: MediaItem
    let onDetails: (MediaItem) -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.dismiss) private var dismiss
    @State private var model = TrailerPreviewModel()
    @State private var trailerPlayback: PlaybackRequest?
    @State private var showYouTube = false
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
                    ItemQuickActions(item: item)
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
        .fullScreenCover(isPresented: $showYouTube) {
            if let id = model.youTubeID {
                YouTubeTrailerPlayerView(videoID: id, title: item.name)
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

            if model.isLoading {
                ProgressView().tint(.white)
            } else if model.player == nil, model.youTubeID != nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openTrailer() }
        .overlay(alignment: .bottomTrailing) {
            if model.player != nil {
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
        .accessibilityHint("Opens the trailer full screen")
    }

    /// Continues the trailer full screen from where the preview currently is.
    private func openTrailer() {
        if let trailer = model.trailer {
            let start = model.currentTicks
            model.pause()
            trailerPlayback = PlaybackRequest(item: trailer, startTicks: start)
        } else if model.youTubeID != nil {
            showYouTube = true
        }
    }
}
#endif
