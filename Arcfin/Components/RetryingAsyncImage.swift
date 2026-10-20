// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Telemetry
import os

/// Drop-in AsyncImage replacement that retries a failed load a bounded number of times
/// before giving up. Plain AsyncImage never retries — one dropped connection on a flaky
/// network fails the image permanently for the lifetime of the view, which is what was
/// happening to MediaDetailView's poster/backdrop/cast images while Home's already-cached
/// poster for the same title kept rendering fine.
struct RetryingAsyncImage<I: View, P: View>: View {
    let url: URL?
    var logCategory: String = "RetryingAsyncImage"
    var logContext: String = ""
    var maxRetries: Int = 2
    @ViewBuilder var content: (Image) -> I
    @ViewBuilder var placeholder: () -> P

    @State private var retryCount = 0

    // A retry that re-requests the exact same URL hits URLCache's existing entry for it —
    // if that entry is itself stale/corrupt (as it reproducibly was here), every "retry"
    // just re-reads the same bad cached response instead of ever reaching the network
    // again. Appending a cache-busting query item on retry > 0 forces a genuinely new
    // cache key, and therefore a real fresh fetch.
    private func requestURL(_ url: URL) -> URL {
        guard retryCount > 0,
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "_retry", value: "\(retryCount)"))
        comps.queryItems = items
        return comps.url ?? url
    }

    var body: some View {
        if let url {
            AsyncImage(url: requestURL(url)) { phase in
                switch phase {
                case .success(let img):
                    content(img)
                case .failure(let error):
                    placeholder()
                        .task(id: retryCount) {
                            guard retryCount < maxRetries else {
                                let nsError = error as NSError
                                let _ = Telemetry.logger(category: logCategory).error(
                                    "image load gave up after \(maxRetries, privacy: .public) retries: \(logContext, privacy: .public) url=\(url.absoluteString, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
                                )
                                return
                            }
                            try? await Task.sleep(nanoseconds: 500_000_000 * UInt64(retryCount + 1))
                            if !Task.isCancelled { retryCount += 1 }
                        }
                default:
                    placeholder()
                }
            }
            // Forces AsyncImage to tear down and re-issue the request on retry — it has no
            // built-in way to retry the same identity once it's reached .failure.
            .id(retryCount)
        } else {
            placeholder()
        }
    }
}
