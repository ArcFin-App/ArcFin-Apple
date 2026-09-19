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
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            YouTubeEmbedWebView(embedURL: embedURL)
                .ignoresSafeArea()

            // YouTube's own title/channel overlay bar sits top-leading when controls are
            // visible, which used to sit right behind this button (barely visible against
            // it) when this was in that same corner — top-trailing avoids that entirely,
            // plus a solid background and a border so it stands out against any video frame.
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .statusBarHidden()
    }
}

private struct YouTubeEmbedWebView: UIViewRepresentable {
    let embedURL: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        // Loading the embed URL directly as the top-level page (webView.load(URLRequest))
        // is a different, unsupported context to YouTube's player than being hosted inside
        // an actual <iframe> — that mismatch is what "video player configuration error"
        // (error 153) actually means. Wrapping it in a minimal HTML document fixes that.
        // baseURL here must be https://www.youtube.com, matching the embed URL's own
        // `origin` query param (see youTubeEmbedURL) — this is the exact pattern Google's
        // own official youtube-ios-player-helper library uses. A nil baseURL gives the
        // iframe's requests an Origin of "null", which YouTube's player rejects with the
        // same error 153 for a different reason (no matching/valid origin at all).
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden;}
        iframe{position:fixed;top:0;left:0;width:100%;height:100%;border:0;}</style>
        </head><body>
        <iframe src="\(embedURL.absoluteString)" frameborder="0" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
