// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Telemetry
import os

/// A cached image that logs, with its context, an image that couldn't be loaded. The retries
/// (once on a dropped connection, or at the original size for Jellyfin's empty resized
/// images) are ImageCache.load's alone: retrying here as well stacked up to about fourteen
/// requests for one broken poster.
struct RetryingAsyncImage<I: View, P: View>: View {
    let url: URL?
    var logCategory: String = "RetryingAsyncImage"
    var logContext: String = ""
    @ViewBuilder var content: (Image) -> I
    @ViewBuilder var placeholder: () -> P

    var body: some View {
        if let url {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    content(img)
                case .failure(let error):
                    placeholder()
                        .task(id: url) {
                            let nsError = error as NSError
                            Telemetry.logger(category: logCategory).error(
                                "image load failed: \(logContext, privacy: .public) path=\(url.path, privacy: .public) domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
                            )
                        }
                default:
                    placeholder()
                }
            }
        } else {
            placeholder()
        }
    }
}
