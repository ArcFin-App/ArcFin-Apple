// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Telemetry
import os

/// Drop-in AsyncImage replacement that retries a failed load before giving up, with a
/// final fallback to the original (unscaled) image.
///
/// Root cause confirmed by direct curl testing against the Jellyfin server: certain
/// fillWidth values return `HTTP 200` with `Content-Length: 0` and `Cache-Control:
/// immutable` — Jellyfin's own on-demand resize cache has a corrupted/empty entry for
/// that exact size+tag, server-side, which no client-side retry of the same size can
/// ever work around. Requesting the item's original, unscaled image (no fillWidth/
/// fillHeight/quality params) bypasses that resize cache entirely and reliably returns
/// the real file, confirmed the same way. AsyncImage already scales whatever it gets to
/// fit its frame, so falling back to the original is visually seamless, just a larger
/// download.
struct RetryingAsyncImage<I: View, P: View>: View {
    let url: URL?
    var logCategory: String = "RetryingAsyncImage"
    var logContext: String = ""
    var maxRetries: Int = 2
    @ViewBuilder var content: (Image) -> I
    @ViewBuilder var placeholder: () -> P

    @State private var attempt = 0

    private func requestURL(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if attempt > maxRetries {
            // Final fallback: strip the resize params entirely to request the original.
            comps.queryItems = comps.queryItems?.filter {
                $0.name != "fillWidth" && $0.name != "fillHeight" && $0.name != "quality"
            }
        } else if attempt > 0 {
            // A retry that re-requests the exact same URL hits URLCache's existing entry
            // for it. Cache-busting forces a genuinely new fetch for these in-between
            // attempts (harmless even though the real cause turned out to be server-side).
            var items = comps.queryItems ?? []
            items.append(URLQueryItem(name: "_retry", value: "\(attempt)"))
            comps.queryItems = items
        }
        return comps.url ?? url
    }

    var body: some View {
        if let url {
            CachedAsyncImage(url: requestURL(url)) { phase in
                switch phase {
                case .success(let img):
                    content(img)
                case .failure(let error):
                    placeholder()
                        .task(id: attempt) {
                            guard attempt <= maxRetries else {
                                let nsError = error as NSError
                                let _ = Telemetry.logger(category: logCategory).error(
                                    "image load gave up after \(maxRetries, privacy: .public) retries + original-size fallback: \(logContext, privacy: .public) path=\(url.path, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
                                )
                                return
                            }
                            try? await Task.sleep(nanoseconds: 500_000_000 * UInt64(attempt + 1))
                            if !Task.isCancelled { attempt += 1 }
                        }
                default:
                    placeholder()
                }
            }
            // Forces AsyncImage to tear down and re-issue the request on each attempt — it
            // has no built-in way to retry the same identity once it's reached .failure.
            .id(attempt)
        } else {
            placeholder()
        }
    }
}
