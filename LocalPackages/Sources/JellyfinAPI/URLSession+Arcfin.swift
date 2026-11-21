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
    /// Adds a server's custom headers (see CustomHTTPHeaders) to requests for that server only.
    public static let arcfin = ArcfinSession(resourceTimeout: 30)

    /// The same as `arcfin`, for the few calls the server only answers once a long job is
    /// done (a backup) or that return a lot (a server log): `arcfin` caps a whole transfer at
    /// 30 s.
    public static let arcfinLongRunning = ArcfinSession(resourceTimeout: 600)
}

/// Wraps a URLSession to add the custom headers per request, since each server has its own
/// and a session's httpAdditionalHeaders can't depend on the host.
public struct ArcfinSession: Sendable {
    private let session: URLSession
    private let resourceTimeout: TimeInterval

    init(resourceTimeout: TimeInterval) {
        self.resourceTimeout = resourceTimeout
        session = URLSession(configuration: Self.configuration(resourceTimeout: resourceTimeout, headers: [:]))
    }

    private static func configuration(resourceTimeout: TimeInterval, headers: [String: String]) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = resourceTimeout
        config.httpAdditionalHeaders = headers.isEmpty ? nil : headers
        return config
    }

    /// For a session of its own (one with a delegate) whose requests all go to `url`'s server.
    public func configuration(for url: URL?) -> URLSessionConfiguration {
        Self.configuration(resourceTimeout: resourceTimeout, headers: CustomHTTPHeaders.headers(for: url))
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: Self.withHeaders(request))
    }

    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(for: Self.withHeaders(URLRequest(url: url)))
    }

    public func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        try await session.download(for: Self.withHeaders(request))
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

    /// A header the caller set itself (Authorization above all) wins.
    private static func withHeaders(_ request: URLRequest) -> URLRequest {
        var request = request
        for (name, value) in CustomHTTPHeaders.headers(for: request.url) where request.value(forHTTPHeaderField: name) == nil {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}
