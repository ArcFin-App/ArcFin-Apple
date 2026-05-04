import Foundation

// MARK: - Jellyseerr HTTP client (API-key auth)

public struct JellyseerrHTTPClient: Sendable {
    private let baseURL: URL
    private let apiKey: String

    public init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    // MARK: Discover

    public func trending() async throws -> [SeerrItem] {
        try await fetchPage("api/v1/trending", query: [])
    }

    public func discoverMovies(page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/movies", query: [("page", "\(page)")])
    }

    public func discoverTV(page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/tv", query: [("page", "\(page)")])
    }

    // MARK: Search

    public func search(query: String, page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/search", query: [("query", query), ("page", "\(page)")])
    }

    // MARK: Requests

    public func getRequests(filter: String = "all", skip: Int = 0, take: Int = 40) async throws -> [SeerrRequestItem] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/request"),
                                   resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "filter", value: filter),
            URLQueryItem(name: "skip", value: "\(skip)"),
            URLQueryItem(name: "take", value: "\(take)"),
        ]
        let data = try await fetch(comps.url!)
        struct Page: Decodable { let results: [SeerrRequestResponse] }
        return try JSONDecoder().decode(Page.self, from: data).results.map { $0.toItem() }
    }

    public func createRequest(mediaType: RequestMediaType, mediaId: Int, seasons: [Int] = []) async throws {
        let url = baseURL.appendingPathComponent("api/v1/request")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        var body: [String: Any] = ["mediaType": mediaType.rawValue, "mediaId": mediaId]
        if !seasons.isEmpty { body["seasons"] = seasons }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: Private helpers

    private func fetchPage(_ path: String, query: [(String, String)]) async throws -> [SeerrItem] {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                   resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        let data = try await fetch(comps.url!)
        struct Page: Decodable { let results: [SeerrItemResponse] }
        return try JSONDecoder().decode(Page.self, from: data).results.compactMap { $0.toItem() }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Private response decoders

private struct SeerrItemResponse: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let mediaType: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let overview: String?
    let mediaInfo: SeerrMediaInfoResponse?

    func toItem() -> SeerrItem? {
        guard let displayTitle = title ?? name else { return nil }
        let type: RequestMediaType = mediaType == "tv" ? .tv : .movie
        let year = (releaseDate ?? firstAirDate).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let status = mediaInfo.flatMap { SeerrAvailabilityStatus(rawValue: $0.status) }
        return SeerrItem(id: id, title: displayTitle, mediaType: type,
                         posterPath: posterPath, backdropPath: backdropPath,
                         year: year, overview: overview, availabilityStatus: status)
    }
}

private struct SeerrMediaInfoResponse: Decodable {
    let status: Int
}

private struct SeerrRequestResponse: Decodable {
    let id: Int
    let status: Int
    let createdAt: String?
    let media: SeerrRequestMedia

    struct SeerrRequestMedia: Decodable {
        let mediaType: String?
        let posterPath: String?
        let title: String?
        let name: String?
        let originalTitle: String?
    }

    func toItem() -> SeerrRequestItem {
        let reqStatus = RequestStatus(rawValue: status) ?? .pending
        let mType: RequestMediaType = media.mediaType == "tv" ? .tv : .movie
        let title = media.originalTitle ?? media.title ?? media.name ?? "Unknown"
        let date = createdAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        return SeerrRequestItem(id: id, mediaTitle: title, mediaType: mType,
                                status: reqStatus, requestedAt: date, posterPath: media.posterPath)
    }
}
