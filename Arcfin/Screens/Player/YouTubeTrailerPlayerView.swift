import SwiftUI
#if canImport(UIKit) && !os(tvOS)
import WebKit
import UIKit

/// Fallback when a title has no local trailer indexed on the server but does have a
/// RemoteTrailer link (almost always YouTube, attached by a metadata provider) — plays it
/// in-app via YouTube's own iframe embed, same approach most third-party apps use since it
/// needs no API key, no sign-in, and no SDK: the video is public, embeddable playback only.
struct YouTubeTrailerPlayerView: View {
    let embedURL: URL
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            YouTubeEmbedWebView(url: embedURL)
                .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding(.top, 16)
            .padding(.leading, 16)
        }
        .statusBarHidden()
    }
}

private struct YouTubeEmbedWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
