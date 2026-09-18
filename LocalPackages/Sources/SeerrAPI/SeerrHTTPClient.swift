import Foundation

// MARK: - Auth method

public enum SeerrAuthMethod: String, Sendable, CaseIterable {
    case jellyfin = "jellyfin"   // Jellyfin-imported account — POST /api/v1/auth/jellyfin
    case local    = "local"      // Local Seerr account  — POST /api/v1/auth/local

    public var label: String {
        switch self {
        case .jellyfin: "Jellyfin Account"
        case .local:    "Local Account"
        }
    }

    public var description: String {
        switch self {
        case .jellyfin: "Sign in with your Jellyfin username and password."
        case .local:    "Sign in with a local Seerr account."
        }
    }

    public var apiPath: String {
        "api/v1/auth/\(rawValue)"
    }
}

// MARK: - Seerr HTTP client

public actor SeerrHTTPClient {
    private let baseURL: URL
    private let username: String
    private let password: String
    private let authMethod: SeerrAuthMethod

    private var isAuthenticated = false
    private var authPermanentlyFailed = false
    private var loginInFlight = false
    private let session: URLSession
    // UserDefaults key used to persist a per-URL auth-failure cooldown across cold launches.
    private let authFailedKey: String

    public init(baseURL: URL, username: String, password: String,
                authMethod: SeerrAuthMethod = .jellyfin) {
        self.baseURL    = baseURL
        self.username   = username
        self.password   = password
        self.authMethod = authMethod
        let config = URLSessionConfiguration.ephemeral
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
            throw SeerrError.authFailed
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
        guard !authPermanentlyFailed else { throw SeerrError.authFailed }
        if let until = UserDefaults.standard.object(forKey: authFailedKey) as? Date,
           until > Date() {
            authPermanentlyFailed = true
            throw SeerrError.authFailed
        }
        guard !isAuthenticated else { return }
        // Actor suspends during network I/O, so concurrent callers can reach here while
        // a login is already in flight. Skip rather than fan out — the first caller's
        // login will set isAuthenticated = true before the retry.
        guard !loginInFlight else { return }
        loginInFlight = true
        defer { loginInFlight = false }
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
        let raw = try JSONDecoder().decode(Page.self, from: data).results

        // The request list only carries tmdbId/mediaType — title and artwork
        // live on TMDB, so fetch each item's detail to fill them in.
        var items = [SeerrRequestItem?](repeating: nil, count: raw.count)
        await withTaskGroup(of: (Int, SeerrRequestItem).self) { group in
            for (index, r) in raw.enumerated() {
                group.addTask {
                    let detail = try? await self.mediaDetail(tmdbId: r.media.tmdbId, mediaType: r.media.mediaType)
                    return (index, r.toItem(detail: detail))
                }
            }
            for await (index, item) in group { items[index] = item }
        }
        return items.compactMap { $0 }
    }

    private func mediaDetail(tmdbId: Int?, mediaType: String?) async throws -> SeerrItem? {
        guard let tmdbId else { return nil }
        let defaultType: RequestMediaType = mediaType == "tv" ? .tv : .movie
        let path = defaultType == .tv ? "api/v1/tv/\(tmdbId)" : "api/v1/movie/\(tmdbId)"
        let data = try await fetch(baseURL.appendingPathComponent(path))
        return try JSONDecoder().decode(SeerrItemResponse.self, from: data).toItem(defaultMediaType: defaultType)
    }

    /// Full movie/tv detail (genres, runtime, rating, cast) for the request confirmation sheet.
    public func fullDetail(mediaType: RequestMediaType, tmdbId: Int) async throws -> SeerrMediaDetail {
        try await ensureAuthenticated()
        let path = mediaType == .tv ? "api/v1/tv/\(tmdbId)" : "api/v1/movie/\(tmdbId)"
        let data = try await fetch(baseURL.appendingPathComponent(path))
        return try JSONDecoder().decode(SeerrDetailResponse.self, from: data).toDetail()
    }

    public func createRequest(mediaType: RequestMediaType, mediaId: Int, seasons: [Int] = []) async throws {
        try await ensureAuthenticated()
        let url = baseURL.appendingPathComponent("api/v1/request")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyXSRF(to: &req)
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

    /// Reads the XSRF-TOKEN cookie from the session's cookie jar and injects it
    /// as the XSRF-TOKEN header. Seerr uses the double-submit cookie pattern —
    /// the cookie alone is not enough; the value must also appear as a header.
    private func applyXSRF(to request: inout URLRequest) {
        guard let token = session.configuration.httpCookieStorage?
            .cookies(for: baseURL)?
            .first(where: { $0.name == "XSRF-TOKEN" })?
            .value else { return }
        request.setValue(token, forHTTPHeaderField: "XSRF-TOKEN")
    }

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
        applyXSRF(to: &req)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            isAuthenticated = false
            try await ensureAuthenticated()
            // Rebuild so the fresh XSRF-TOKEN from the new login is included.
            var retryReq = URLRequest(url: url)
            retryReq.timeoutInterval = 15
            applyXSRF(to: &retryReq)
            let (retryData, retryResp) = try await session.data(for: retryReq)
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

public enum SeerrError: Error, LocalizedError {
    case authFailed

    public var errorDescription: String? {
        switch self {
        case .authFailed: "Invalid Seerr username or password."
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

    // Seerr's request media entity only stores identifiers/status —
    // title, name, posterPath, backdropPath live on TMDB and are fetched separately.
    struct SeerrRequestMedia: Decodable {
        let tmdbId: Int?
        let mediaType: String?
    }

    func toItem(detail: SeerrItem?) -> SeerrRequestItem {
        let reqStatus = RequestStatus(rawValue: status) ?? .pending
        let mType: RequestMediaType = media.mediaType == "tv" ? .tv : .movie
        let title = detail?.title ?? "Unknown"
        let date = createdAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        return SeerrRequestItem(id: id, mediaTitle: title, mediaType: mType,
                                status: reqStatus, requestedAt: date,
                                posterPath: detail?.posterPath, backdropPath: detail?.backdropPath)
    }
}

private struct SeerrDetailResponse: Decodable {
    let tagline: String?
    let overview: String?
    let genres: [SeerrGenre]?
    let runtime: Int?               // movie
    let episodeRunTime: [Int]?      // tv
    let voteAverage: Double?
    let status: String?
    let credits: SeerrCredits?

    struct SeerrGenre: Decodable { let name: String }
    struct SeerrCredits: Decodable { let cast: [SeerrCast]? }
    struct SeerrCast: Decodable {
        let id: Int
        let name: String
        let character: String?
        let profilePath: String?
    }

    func toDetail() -> SeerrMediaDetail {
        let cast = (credits?.cast ?? []).prefix(10).map {
            SeerrCastMember(id: $0.id, name: $0.name, character: $0.character, profilePath: $0.profilePath)
        }
        return SeerrMediaDetail(
            tagline: (tagline?.isEmpty ?? true) ? nil : tagline,
            overview: overview,
            genres: (genres ?? []).map(\.name),
            runtimeMinutes: runtime ?? episodeRunTime?.first,
            voteAverage: voteAverage,
            status: status,
            cast: Array(cast)
        )
    }
}
