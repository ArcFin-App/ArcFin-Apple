import Foundation

// MARK: - Auth method

public enum JellyseerrAuthMethod: String, Sendable, CaseIterable {
    case jellyfin = "jellyfin"   // Jellyfin-imported account — POST /api/v1/auth/jellyfin
    case local    = "local"      // Local Jellyseerr account  — POST /api/v1/auth/local

    public var label: String {
        switch self {
        case .jellyfin: "Jellyfin Account"
        case .local:    "Local Account"
        }
    }

    public var description: String {
        switch self {
        case .jellyfin: "Sign in with your Jellyfin username and password."
        case .local:    "Sign in with a local Jellyseerr account."
        }
    }

    public var apiPath: String {
        "api/v1/auth/\(rawValue)"
    }
}

// MARK: - Jellyseerr HTTP client

public actor JellyseerrHTTPClient {
    private let baseURL: URL
    private let username: String
    private let password: String
    private let authMethod: JellyseerrAuthMethod

    private var isAuthenticated = false
    private var authPermanentlyFailed = false
    private let session: URLSession
    // UserDefaults key used to persist a per-URL auth-failure cooldown across cold launches.
    private let authFailedKey: String

    public init(baseURL: URL, username: String, password: String,
                authMethod: JellyseerrAuthMethod = .jellyfin) {
        self.baseURL    = baseURL
        self.username   = username
        self.password   = password
        self.authMethod = authMethod
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies   = true
        self.session = URLSession(configuration: config)
        self.authFailedKey = "arcfin.seerr.authFailedUntil.\(baseURL.host ?? "unknown")"
    }

    /// Clears any persisted auth-failure cooldown. Call this when the user updates credentials.
    public func clearAuthFailure() {
        UserDefaults.standard.removeObject(forKey: authFailedKey)
        authPermanentlyFailed = false
    }

    // MARK: - Auth

    public func login() async throws {
        let url = baseURL.appendingPathComponent(authMethod.apiPath)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        req.timeoutInterval = 15
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 401 || http.statusCode == 403 {
            // Real credential rejection — back off to protect against Jellyfin brute-force lockout.
            authPermanentlyFailed = true
            UserDefaults.standard.set(Date().addingTimeInterval(3600), forKey: authFailedKey)
            throw JellyseerrError.authFailed
        }
        guard (200...299).contains(http.statusCode) else {
            // Transient server error (5xx, 503 during startup, etc.) — do not lock out.
            throw URLError(.badServerResponse)
        }
        authPermanentlyFailed = false
        UserDefaults.standard.removeObject(forKey: authFailedKey)
        isAuthenticated = true
    }

    private func ensureAuthenticated() async throws {
        // Check in-memory flag first (fast path within a session).
        guard !authPermanentlyFailed else { throw JellyseerrError.authFailed }
        // Check persisted cooldown so cold relaunches also respect previous failures.
        if let until = UserDefaults.standard.object(forKey: authFailedKey) as? Date,
           until > Date() {
            authPermanentlyFailed = true
            throw JellyseerrError.authFailed
        }
        guard !isAuthenticated else { return }
        try await login()
    }

    // MARK: - Discover

    public func trending() async throws -> [SeerrItem] {
        try await fetchPage("api/v1/trending", query: [])
    }

    public func discoverMovies(page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/movies", query: [("page", "\(page)")])
    }

    public func discoverTV(page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/tv", query: [("page", "\(page)")])
    }

    // MARK: - Search

    public func search(query: String, page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/search", query: [("query", query), ("page", "\(page)")])
    }

    public func recommendations(mediaType: RequestMediaType, mediaId: Int, page: Int = 1) async throws -> [SeerrItem] {
        let path = mediaType == .tv
            ? "api/v1/tv/\(mediaId)/recommendations"
            : "api/v1/movie/\(mediaId)/recommendations"
        return try await fetchPage(path, query: [("page", "\(page)")], defaultMediaType: mediaType)
    }

    public func similar(mediaType: RequestMediaType, mediaId: Int, page: Int = 1) async throws -> [SeerrItem] {
        let path = mediaType == .tv
            ? "api/v1/tv/\(mediaId)/similar"
            : "api/v1/movie/\(mediaId)/similar"
        return try await fetchPage(path, query: [("page", "\(page)")], defaultMediaType: mediaType)
    }

    // MARK: - Requests

    public func getRequests(filter: String = "all", skip: Int = 0, take: Int = 40) async throws -> [SeerrRequestItem] {
        try await ensureAuthenticated()
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
        try await ensureAuthenticated()
        let url = baseURL.appendingPathComponent("api/v1/request")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["mediaType": mediaType.rawValue, "mediaId": mediaId]
        if !seasons.isEmpty { body["seasons"] = seasons }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Private helpers

    private func fetchPage(
        _ path: String,
        query: [(String, String)],
        defaultMediaType: RequestMediaType? = nil
    ) async throws -> [SeerrItem] {
        try await ensureAuthenticated()
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        let data = try await fetch(comps.url!)
        struct Page: Decodable { let results: [SeerrItemResponse] }
        return try JSONDecoder().decode(Page.self, from: data).results.compactMap {
            $0.toItem(defaultMediaType: defaultMediaType)
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            isAuthenticated = false
            try await ensureAuthenticated()
            let (retryData, retryResp) = try await session.data(for: req)
            guard let retryHttp = retryResp as? HTTPURLResponse,
                  (200...299).contains(retryHttp.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return retryData
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

// MARK: - Errors

public enum JellyseerrError: Error, LocalizedError {
    case authFailed

    public var errorDescription: String? {
        switch self {
        case .authFailed: "Invalid Jellyseerr username or password."
        }
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

    func toItem(defaultMediaType: RequestMediaType? = nil) -> SeerrItem? {
        guard let displayTitle = title ?? name else { return nil }
        let type: RequestMediaType
        if let mediaType {
            type = mediaType == "tv" ? .tv : .movie
        } else if let defaultMediaType {
            type = defaultMediaType
        } else {
            type = .movie
        }
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
        let backdropPath: String?
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
                                status: reqStatus, requestedAt: date,
                                posterPath: media.posterPath, backdropPath: media.backdropPath)
    }
}
