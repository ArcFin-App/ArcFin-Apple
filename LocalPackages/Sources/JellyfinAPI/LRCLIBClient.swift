// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Lyrics from LRCLIB (lrclib.net), a free, open lyrics library, for songs the server has
/// none for.
public struct LRCLIBClient: Sendable {
    public static let baseURL = URL(string: "https://lrclib.net")!

    public enum Result: Sendable, Equatable {
        case found(Lyrics)
        /// LRCLIB has nothing for the song, or only marks it instrumental.
        case notFound
    }

    private let baseURL: URL
    private let userAgent: String

    /// LRCLIB asks every client to name itself, its version and its home page.
    public init(clientVersion: String, baseURL: URL = Self.baseURL) {
        self.baseURL = baseURL
        userAgent = "Arcfin \(clientVersion) (https://arcfin.psmattas.com)"
    }

    /// Its own session, without the custom headers meant for the Jellyfin server.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    /// The song's lyrics, matched on its title, artist, album and length (LRCLIB matches
    /// within two seconds of the length). Throws when LRCLIB couldn't be asked, or asked to
    /// wait, so a miss isn't remembered then.
    public func lyrics(track: String, artist: String, album: String?, duration: TimeInterval?) async throws -> Result {
        var query: [URLQueryItem] = [.init(name: "track_name", value: track), .init(name: "artist_name", value: artist)]
        if let album, !album.isEmpty { query.append(.init(name: "album_name", value: album)) }
        if let duration, (1...3600).contains(duration) { query.append(.init(name: "duration", value: String(Int(duration.rounded())))) }
        await withCheckedContinuation { PathWait(continuation: $0).start(timeoutSeconds: 6) }
        if let data = try await get("api/get", query) {
            let exact = try Self.decode(data)
            if exact != .notFound { return exact }
        }
        // No exact match (the album or length differs, often a single or a video's audio):
        // the closest in length of the same song and artist.
        let search = [URLQueryItem(name: "track_name", value: track), .init(name: "artist_name", value: artist)]
        guard let data = try await get("api/search", search) else { return .notFound }
        return try Self.closest(data, duration: duration)
    }

    /// The response, or nil when LRCLIB has nothing there.
    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data? {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = query
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200...299).contains(status) else { throw URLError(.badServerResponse) }
        return data
    }

    /// From search results, synced lyrics before plain ones, then the nearest length, within
    /// 15 seconds when the song's length is known.
    static func closest(_ data: Data, duration: TimeInterval?) throws -> Result {
        struct Record: Decodable {
            let duration: Double?
            let instrumental: Bool?
            let plainLyrics: String?
            let syncedLyrics: String?
        }
        let records = try JSONDecoder().decode([Record].self, from: data).filter { record in
            guard record.instrumental != true, record.syncedLyrics != nil || record.plainLyrics != nil else { return false }
            guard let duration, let length = record.duration else { return true }
            return abs(length - duration) <= 15
        }
        let best = records.min { a, b in
            let aSynced = a.syncedLyrics != nil, bSynced = b.syncedLyrics != nil
            if aSynced != bSynced { return aSynced }
            guard let duration else { return false }
            return abs((a.duration ?? .infinity) - duration) < abs((b.duration ?? .infinity) - duration)
        }
        guard let best else { return .notFound }
        if let synced = best.syncedLyrics, let lyrics = parseLRC(synced) { return .found(lyrics) }
        if let plain = best.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return .found(Lyrics(lines: plain.components(separatedBy: .newlines).map { Lyrics.Line(start: nil, text: $0) }))
        }
        return .notFound
    }

    static func decode(_ data: Data) throws -> Result {
        struct Record: Decodable {
            let instrumental: Bool?
            let plainLyrics: String?
            let syncedLyrics: String?
        }
        let record = try JSONDecoder().decode(Record.self, from: data)
        if let synced = record.syncedLyrics, let lyrics = parseLRC(synced) { return .found(lyrics) }
        if let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            return .found(Lyrics(lines: plain.components(separatedBy: .newlines).map { Lyrics.Line(start: nil, text: $0) }))
        }
        return .notFound
    }

    /// Timed lines from LRC text: `[mm:ss.xx] words`, a line may carry several times, and
    /// tags like `[ar: …]` are skipped. Nil when nothing in it is timed.
    static func parseLRC(_ text: String) -> Lyrics? {
        var lines: [Lyrics.Line] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var starts: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                guard let start = time(rest[rest.index(after: rest.startIndex)..<close]) else { break }
                starts.append(start)
                rest = rest[rest.index(after: close)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            lines += starts.map { Lyrics.Line(start: $0, text: words) }
        }
        guard !lines.isEmpty else { return nil }
        return Lyrics(lines: lines.sorted { ($0.start ?? 0) < ($1.start ?? 0) })
    }

    /// `mm:ss`, `mm:ss.xx` or `mm:ss:xx` in seconds.
    private static func time(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let minutes = Int(parts[0]) else { return nil }
        let seconds = parts[1].replacingOccurrences(of: ":", with: ".")
        guard let value = Double(seconds), value >= 0 else { return nil }
        return Double(minutes) * 60 + value
    }
}
