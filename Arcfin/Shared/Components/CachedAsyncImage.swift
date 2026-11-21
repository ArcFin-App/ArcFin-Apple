// SPDX-License-Identifier: AGPL-3.0-or-later

import ImageCache
import SwiftUI

/// Same shape as `AsyncImage(url:) { phase in }`, but loads through the app's shared image
/// pipeline instead of a plain URLSession request. Images stay decoded in memory and on disk
/// between screens, so posters don't re-download and flash every time a shelf scrolls back
/// into view or a screen is reopened, and decoding happens off the main thread.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase
    @State private var loadedURL: URL?

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        let cached = url.flatMap(ImageCache.memoryImage(for:))
        _phase = State(initialValue: cached.map { .success(Image(platformImage: $0)) } ?? .empty)
        _loadedURL = State(initialValue: cached == nil ? nil : url)
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            phase = .empty
            loadedURL = nil
            return
        }
        guard url != loadedURL else { return }
        if let cached = ImageCache.memoryImage(for: url) {
            phase = .success(Image(platformImage: cached))
            loadedURL = url
            return
        }
        phase = .empty
        do {
            let image = try await loadRetryingOnce(url)
            guard !Task.isCancelled else { return }
            phase = .success(Image(platformImage: image))
            loadedURL = url
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failure(error)
        }
    }

    /// A failed load is final for as long as the view keeps this URL, so one that failed
    /// while the connection was still coming up gets a second go.
    private func loadRetryingOnce(_ url: URL) async throws -> ImageCache.PlatformImage {
        do {
            return try await ImageCache.load(url)
        } catch {
            try await Task.sleep(for: .seconds(1))
            return try await ImageCache.load(url)
        }
    }
}
