import Foundation

// MARK: - Streamystats HTTP client
// Auth: MediaBrowser Token (Jellyfin token). No separate credentials needed.

public actor StreamystatsHTTPClient {
    private let baseURL: URL
    private let jellyfinToken: String
    private let jellyfinServerId: String   // Jellyfin server UUID from /System/Info/Public

    private let session: URLSession

    public init(baseURL: URL, jellyfinToken: String, jellyfinServerId: String) {
        self.baseURL     = baseURL
        self.jellyfinToken    = jellyfinToken
        self.jellyfinServerId = jellyfinServerId
        let config = URLSessionConfiguration.default
        self.session = URLSession(configuration: config)
    }

    // MARK: - Recommendations

    /// Recommended movies/series based on the user's watch history.
    public func getRecommendations(
        type: StreamystatsMediaType = .all,
        range: StreamystatsRange = .thirtyDays,
        limit: Int = 20
    ) async throws -> [StreamystatsRecommendation] {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/recommendations"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "jellyfinServerId", value: jellyfinServerId),
            .init(name: "limit", value: "\(limit)"),
            .init(name: "type", value: type.rawValue),
            .init(name: "range", value: range.rawValue),
            .init(name: "format", value: "full"),
            .init(name: "includeReasons", value: "true"),
        ]
        let data = try await fetch(comps.url!)
        return try JSONDecoder().decode([StreamystatsRecommendation].self, from: data)
    }

    // MARK: - Watchlists

    public func getPromotedWatchlists(limit: Int = 10) async throws -> [StreamystatsWatchlist] {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/watchlists/promoted"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "jellyfinServerId", value: jellyfinServerId),
            .init(name: "limit", value: "\(limit)"),
            .init(name: "format", value: "full"),
        ]
        let data = try await fetch(comps.url!)
        return try JSONDecoder().decode([StreamystatsWatchlist].self, from: data)
    }

    public func getWatchlists() async throws -> [StreamystatsWatchlist] {
        let data = try await fetch(baseURL.appendingPathComponent("api/watchlists"))
        return try JSONDecoder().decode([StreamystatsWatchlist].self, from: data)
    }

    public func addToWatchlist(watchlistId: String, jellyfinItemId: String) async throws {
        let url = baseURL.appendingPathComponent("api/watchlists/\(watchlistId)/items")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MediaBrowser Token=\"\(jellyfinToken)\"", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "jellyfinServerId": jellyfinServerId,
            "jellyfinId": jellyfinItemId,
        ])
        req.timeoutInterval = 15
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw StreamystatsError.requestFailed
        }
    }

    // MARK: - Search

    public func search(query: String, limit: Int = 20) async throws -> [StreamystatsSearchResult] {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("api/search"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "limit", value: "\(limit)"),
            .init(name: "format", value: "full"),
        ]
        let data = try await fetch(comps.url!)
        struct SearchResponse: Decodable {
            let items: [StreamystatsSearchResult]?
        }
        if let resp = try? JSONDecoder().decode(SearchResponse.self, from: data) {
            return resp.items ?? []
        }
        return (try? JSONDecoder().decode([StreamystatsSearchResult].self, from: data)) ?? []
    }

    // MARK: - Private

    private func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("MediaBrowser Token=\"\(jellyfinToken)\"", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw StreamystatsError.requestFailed
        }
        return data
    }
}

// MARK: - Enums

public enum StreamystatsMediaType: String, Sendable {
    case all = "all"
    case movie = "Movie"
    case series = "Series"
}

public enum StreamystatsRange: String, Sendable {
    case sevenDays   = "7d"
    case thirtyDays  = "30d"
    case ninetyDays  = "90d"
    case thisMonth   = "thisMonth"
    case all         = "all"
}

// MARK: - Models

public struct StreamystatsRecommendation: Decodable, Sendable, Identifiable {
    public let id: String
    public let item: StreamystatsItem?
    public let reasoning: String?
    public let similarityScore: Double?

    enum CodingKeys: String, CodingKey {
        case id, item, reasoning, similarityScore
    }
}

public struct StreamystatsItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let jellyfinId: String?
    public let title: String?
    public let name: String?
    public let type: String?
    public let productionYear: Int?
    public let images: StreamystatsImages?
    public let overview: String?

    public var displayTitle: String { title ?? name ?? "Unknown" }
    public var posterURL: URL? { images?.poster.flatMap { URL(string: $0) } }
    public var backdropURL: URL? { images?.backdrop.flatMap { URL(string: $0) } }

    enum CodingKeys: String, CodingKey {
        case id, jellyfinId, title, name, type, productionYear, images, overview
    }
}

public struct StreamystatsImages: Decodable, Sendable {
    public let poster: String?
    public let backdrop: String?
    public let logo: String?
}

public struct StreamystatsWatchlist: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let visibility: String?
    public let itemType: String?
    public let items: [StreamystatsItem]?
}

public struct StreamystatsSearchResult: Decodable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let name: String?
    public let type: String?
    public let images: StreamystatsImages?

    public var displayTitle: String { title ?? name ?? "Unknown" }
    public var posterURL: URL? { images?.poster.flatMap { URL(string: $0) } }
}

// MARK: - Error

public enum StreamystatsError: Error, LocalizedError {
    case requestFailed
    public var errorDescription: String? { "Streamystats request failed." }
}
