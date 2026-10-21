// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import AuthCore
import JellyfinAPI
import SwiftUI

/// "Play Trailer" from a poster's long-press menu: finds the title's local trailer (or its
/// YouTube trailer) and plays it full screen. Closes itself when there is none.
struct TrailerLauncher: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    private enum Source {
        case loading
        case local(MediaItem)
        case youTube(String)
        case none
    }

    @State private var source: Source = .loading

    var body: some View {
        Group {
            switch source {
            case .loading:
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            case .local(let trailer):
                PlayerView(item: trailer)
            case .youTube(let id):
                YouTubeTrailerPlayerView(videoID: id, title: item.name)
            case .none:
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: "film")
                            .font(.system(size: 34))
                        Text("No trailer available")
                            .font(.system(.headline))
                        Button("Close") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .task {
            guard let credential = authManager.state.credential else { source = .none; return }
            let header = authManager.authClient.authHeader(token: credential.accessToken)
            let client = JellyfinMediaClient()
            if let local = try? await client.getTrailers(
                credential: credential, authHeader: header, itemId: item.id, limit: 1).first {
                source = .local(local)
                return
            }
            let detail = try? await client.getItemDetail(credential: credential, authHeader: header, itemId: item.id)
            if let id = detail?.remoteTrailers.first(where: { $0.youTubeVideoID != nil })?.youTubeVideoID {
                source = .youTube(id)
            } else {
                source = .none
            }
        }
    }
}
#endif
