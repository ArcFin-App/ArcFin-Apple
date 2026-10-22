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
        ArcfinSessionBox.session(for: CustomHTTPHeaders.current)
    }
}

private enum ArcfinSessionBox {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: (headers: [String: String], session: URLSession)?

    static func session(for headers: [String: String]) -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let cached, cached.headers == headers { return cached.session }
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = headers.isEmpty ? nil : headers
        let session = URLSession(configuration: config)
        cached?.session.finishTasksAndInvalidate()
        cached = (headers, session)
        return session
    }
}
