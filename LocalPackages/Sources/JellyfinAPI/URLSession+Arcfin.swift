// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

extension URLSession {
    /// Used everywhere in this package instead of `.shared`. The default configuration's
    /// waitsForConnectivity is false — a request fired before the network path is actually up
    /// (right at cold launch, or the very first connection to a LAN server, which can race
    /// macOS's Local Network permission resolving) fails immediately instead of waiting for
    /// it, which is exactly the "can't reach server" on launch that a manual Reload moments
    /// later fixes instantly. With this on, a per-request timeoutInterval only starts
    /// counting down once connectivity is actually available, rather than firing while still
    /// waiting for it — so the existing 8-20s per-request timeouts stay meaningful instead of
    /// racing the same startup window they're meant to bound.
    ///
    /// Carries the user's custom headers (see CustomHTTPHeaders), rebuilt when they change.
    public static var arcfin: URLSession {
        ArcfinSessionBox.standard.session(for: CustomHTTPHeaders.current)
    }

    /// The same as `arcfin`, for the few calls the server only answers once a long job is
    /// done (a backup) or that return a lot (a server log): `arcfin` caps a whole transfer at
    /// 30 s.
    public static var arcfinLongRunning: URLSession {
        ArcfinSessionBox.longRunning.session(for: CustomHTTPHeaders.current)
    }

    /// An image's bytes, or nil. Jellyfin's resize cache can answer one size of an image
    /// with an empty 200 forever, so a failed or empty resized request retries the original.
    public func imageData(from url: URL) async -> Data? {
        if let data = await nonEmptyData(from: url) { return data }
        guard let original = JellyfinMediaClient.unresizedImageURL(url) else { return nil }
        return await nonEmptyData(from: original)
    }

    private func nonEmptyData(from url: URL) async -> Data? {
        guard let (data, response) = try? await data(from: url), !data.isEmpty,
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { return nil }
        return data
    }
}

private final class ArcfinSessionBox: @unchecked Sendable {
    static let standard = ArcfinSessionBox(resourceTimeout: 30)
    static let longRunning = ArcfinSessionBox(resourceTimeout: 600)

    private let resourceTimeout: TimeInterval
    private let lock = NSLock()
    private var cached: (headers: [String: String], session: URLSession)?

    private init(resourceTimeout: TimeInterval) {
        self.resourceTimeout = resourceTimeout
    }

    func session(for headers: [String: String]) -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.headers == headers { return cached.session }
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = resourceTimeout
        config.httpAdditionalHeaders = headers.isEmpty ? nil : headers
        let session = URLSession(configuration: config)
        cached?.session.finishTasksAndInvalidate()
        cached = (headers, session)
        return session
    }
}
