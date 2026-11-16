// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import YouTubePlayerKit

/// Fallback when a title has no local trailer indexed on the server but does have a
/// RemoteTrailer link (almost always YouTube, attached by a metadata provider). Uses
/// YouTubePlayerKit (MIT, SvenTiigi/YouTubePlayerKit) rather than a hand-rolled WKWebView —
/// a Terms of Service-compliant embed has real origin/config validation to get right, which
/// a maintained package already does correctly instead of reimplementing it by hand.
struct YouTubeTrailerPlayerView: View {
    let videoID: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: YouTubePlayer

    init(videoID: String, title: String) {
        self.videoID = videoID
        self.title = title
        _player = State(initialValue: YouTubePlayer(
            source: .video(id: videoID),
            parameters: .init(autoPlay: true, showControls: true),
            // Without this, YouTube's embedded player gets a persistent WKWebsiteDataStore —
            // cookies it sets survive across app launches, giving it a standing identifier to
            // link repeat trailer plays back to this device. A non-persistent (ephemeral, like
            // Private Browsing) store means every trailer starts clean with nothing carried
            // over from the last one.
            configuration: .init(useNonPersistentWebsiteDataStore: true)
        ))
    }

    var body: some View {
        bodyContent
            .alwaysDarkPlayer()
            .onAppear { AppServices.music.yieldToVideo() }
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            YouTubePlayerView(player) { state in
                switch state {
                case .idle:
                    ProgressView().tint(.white)
                case .ready:
                    EmptyView()
                case .error:
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(.title))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("This trailer can't be played")
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .ignoresSafeArea()

            // YouTube's own title/channel overlay bar sits top-leading when controls are
            // visible — top-trailing avoids colliding with it, plus a solid background and
            // a border so it stays legible against any video frame.
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close trailer")
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
    }
}
