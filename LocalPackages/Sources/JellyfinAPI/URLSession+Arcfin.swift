// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

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
    public static let arcfin: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()
}
