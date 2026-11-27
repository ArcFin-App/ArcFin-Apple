// SPDX-License-Identifier: AGPL-3.0-or-later

import JellyfinAPI
import SwiftUI
import YouTubePlayerKit

/// A title that isn't on the server yet, in the feed: its trailer, what it is, and Request.
struct ArcsRequestPage: View {
    let clip: ArcClip
    let model: ArcsModel
    let isCurrent: Bool
    let bottomInset: Double
    let actions: ArcClipActions

    @State private var player: YouTubePlayer?
    @State private var descriptionOpen = false
    /// The trailer is actually playing: until then the poster stays, hiding YouTube's own thumbnail and play button.
    @State private var trailerPlaying = false

    private var playing: Bool { isCurrent && model.isVisible && !model.isPaused }

    var body: some View {
        ZStack {
            // Sized by the page: a fill-scaled image left to size itself would widen the page and
            // push its text and buttons past the screen's edges.
            Color.black.overlay {
                CachedAsyncImage(url: ArcsClient.tmdbImageURL(clip.backdropPath ?? clip.posterPath)) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { Color.black }
                }
                .blur(radius: 30)
                .overlay(Color.black.opacity(0.45))
            }
            .clipped()
            if !model.trailersAllowed || clip.trailerYouTubeKey == nil { poster }
            trailer
            ArcTapSurface(onTap: { model.isPaused.toggle() }, onDoubleTap: { _ in }, onHold: { _ in })
            overlay
        }
        .clipped()
        .task(id: isCurrent) {
            if isCurrent, player == nil, model.trailersAllowed, let key = clip.trailerYouTubeKey {
                // Looping is done here, not by YouTube: its loop is a one-video playlist, which shows
                // next and previous buttons.
                player = YouTubePlayer(source: .video(id: key),
                                       parameters: .init(autoPlay: false, loopEnabled: false, showControls: false,
                                                         showFullscreenButton: false, keyboardControlsDisabled: true,
                                                         showCaptions: false, restrictRelatedVideosToSameChannel: true),
                                       // As the app's other trailers: nothing kept between plays.
                                       configuration: .init(useNonPersistentWebsiteDataStore: true))
            }
            await sync()
        }
        .onChange(of: playing) { Task { await sync() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: clip.name))
    }

    /// The trailer, drawn a little larger than its 16:9 frame so YouTube's title bar and logo fall
    /// outside it, and shown only once it's playing.
    @ViewBuilder
    private var trailer: some View {
        if let player {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    YouTubePlayerView(player)
                        .scaleEffect(1.32)
                        .allowsHitTesting(false)
                }
                .clipped()
                .opacity(trailerPlaying ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: trailerPlaying)
                .onReceive(player.playbackStatePublisher) { state in
                    trailerPlaying = state == .playing || state == .buffering && trailerPlaying
                    if state == .ended, playing {
                        Task {
                            try? await player.seek(to: Measurement(value: 0, unit: .seconds))
                            try? await player.play()
                        }
                    }
                }
                .accessibilityHidden(true)
            if isCurrent, !trailerPlaying, playing { ProgressView().tint(.white) }
        }
    }

    /// With trailers off: the title's poster, sharp, where the trailer would play.
    private var poster: some View {
        CachedAsyncImage(url: ArcsClient.tmdbImageURL(clip.posterPath ?? clip.backdropPath)) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFit() } else { Color.clear }
        }
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 20)
        .padding(.horizontal, 48)
        .padding(.bottom, 200)
        .accessibilityHidden(true)
    }

    private func sync() async {
        guard let player else { return }
        if playing { try? await player.play() } else { try? await player.pause() }
    }

    private var overlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Not on Your Server Yet", systemImage: "sparkle.magnifyingglass")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                    Text(verbatim: clip.name)
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                    if let line = [clip.year.map(String.init), clip.genres.prefix(2).joined(separator: ", ")].compactMap({ $0 }).filter({ !$0.isEmpty }).nilIfEmpty {
                        Text(verbatim: line.joined(separator: " · ")).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                    }
                    if model.showsReasons, let reason = ArcText.reason(clip) {
                        Label { Text(reason) } icon: { Image(systemName: "sparkles") }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    if let overview = clip.overview, !overview.isEmpty {
                        ArcDescription(text: overview, isOpen: $descriptionOpen)
                    }
                    HStack(spacing: 6) {
                        Button { actions.request(clip) } label: {
                            Label("Request", systemImage: "plus").font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glassProminent)
                        .tint(DT.Color.accent)
                        .foregroundStyle(DT.Color.onAccent)
                        Button { actions.requestDetails(clip) } label: {
                            Label("Details", systemImage: "info.circle").font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 12) {
                    ArcRailButton(icon: "hand.thumbsdown", title: String(localized: "Not for Me"), tint: .white, label: "Not for Me") {
                        model.keepOut(clip, .notNow)
                    }
                }
                .frame(width: 52)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6 + 22 + bottomInset)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .frame(height: 320)
                .allowsHitTesting(false)
        }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}
