// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network
import Telemetry
// Needed for the privacy-annotated string interpolation in the error log below — Telemetry
// wraps os.Logger, but that doesn't re-export the OSLogMessage interpolation machinery to
// callers (see MediaRepository.swift/JellyfinAuthClient.swift/SeerrRepository.swift, which hit
// the identical "missing import of defining module 'os'" error for the same reason).
import os

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

/// Races a one-shot NWPathMonitor read against a timeout — same lock-guarded resume-once
/// pattern as MediaRepository's/JellyfinAuthClient's PathWait (duplicated rather than shared
/// across the package boundary).
private final class PathWait: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Void, Never>
    private let monitor = NWPathMonitor()

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func start(timeoutSeconds: Double) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            self?.finish()
        }
        monitor.start(queue: DispatchQueue(label: "arcfin.seerrapi.pathwait"))
        Task {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            self.finish()
        }
    }

    private func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        monitor.cancel()
        continuation.resume()
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
    private var loginTask: Task<Void, Error>?
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
        // Default is false — a request fired before the network path is fully established
        // (cold launch, first connection to a LAN host) fails immediately instead of
        // waiting, which is exactly the shape of "loadDiscover failed: domain=NSURLErrorDomain
        // code=-1011" seen right at startup. Same fix already applied to JellyfinAPI's own
        // shared session (URLSession+Arcfin.swift) — this client predates that and was never
        // updated to match, being a separate package.
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.authFailedKey = "arcfin.seerr.authFailedUntil.\(baseURL.host ?? "unknown")"
    }

    /// Clears any persisted auth-failure cooldown. Call this when the user updates credentials.
    public func clearAuthFailure() {
        UserDefaults.standard.removeObject(forKey: authFailedKey)
        authPermanentlyFailed = false
    }

    // MARK: - Auth

    private static func waitForNetworkPath(timeoutSeconds: Double = 6) async {
        await withCheckedContinuation { continuation in
            PathWait(continuation: continuation).start(timeoutSeconds: timeoutSeconds)
        }
    }

    public func login() async throws {
        await Self.waitForNetworkPath()
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
        // The actor suspends during network I/O, so concurrent callers (Discover fires
        // several requests at once, alongside Requests) reach here while a login is already
        // running. They wait for that same login instead of returning early and sending
        // their request unauthenticated, which came back 401 and surfaced as error -1011.
        if let loginTask {
            try await loginTask.value
            return
        }
        let task = Task { try await login() }
        loginTask = task
        defer { loginTask = nil }
        try await task.value
    }

    // MARK: - Discover

    public func trending(mediaType: RequestMediaType? = nil) async throws -> [SeerrItem] {
        // Was "api/v1/trending" — not a real Seerr path (verified against seerr-api.yml,
        // the only trending endpoint is under /discover).
        var query: [(String, String)] = []
        if let mediaType { query.append(("mediaType", mediaType.rawValue)) }
        return try await fetchPage("api/v1/discover/trending", query: query)
    }

    public func discoverMovies(page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/movies", query: [("page", "\(page)")])
    }

    public func discoverTV(page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/tv", query: [("page", "\(page)")])
    }

    public func discoverMovies(genreId: Int, page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/movies/genre/\(genreId)", query: [("page", "\(page)")],
                            defaultMediaType: .movie)
    }

    public func discoverTV(genreId: Int, page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/tv/genre/\(genreId)", query: [("page", "\(page)")],
                            defaultMediaType: .tv)
    }

    public func upcomingMovies(page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/movies/upcoming", query: [("page", "\(page)")],
                            defaultMediaType: .movie)
    }

    public func upcomingTV(page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/tv/upcoming", query: [("page", "\(page)")],
                            defaultMediaType: .tv)
    }

    /// Genres with a representative backdrop attached — the picker data for browsing by genre.
    public func genreSlider(mediaType: RequestMediaType) async throws -> [SeerrGenre] {
        try await ensureAuthenticated()
        let path = mediaType == .tv ? "api/v1/discover/genreslider/tv" : "api/v1/discover/genreslider/movie"
        let data = try await fetch(baseURL.appendingPathComponent(path))
        return try JSONDecoder().decode([SeerrGenreResponse].self, from: data).map { $0.toGenre() }
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

    /// A person's full filmography (cast + crew merged, deduplicated by title+mediaType —
    /// a credit can appear in both, e.g. an actor who also directed). tmdbPersonId comes from
    /// a Jellyfin Person's own ProviderIds.Tmdb (see JellyfinMediaClient.getPersonDetail) —
    /// Seerr proxies TMDB directly, so there's no separate Seerr-side person id to resolve.
    public func personCredits(tmdbPersonId: Int) async throws -> [SeerrPersonCredit] {
        try await ensureAuthenticated()
        let data = try await fetch(baseURL.appendingPathComponent("api/v1/person/\(tmdbPersonId)/combined_credits"))
        struct Response: Decodable {
            let cast: [SeerrItemResponse]?
            let crew: [SeerrItemResponse]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<String>()
        var credits: [SeerrPersonCredit] = []
        for row in (decoded.cast ?? []) + (decoded.crew ?? []) {
            guard let credit = row.toCredit() else { continue }
            let key = "\(credit.mediaType.rawValue):\(credit.id)"
            if seen.insert(key).inserted { credits.append(credit) }
        }
        return credits
    }

    // MARK: - Watchlist

    /// The user's Seerr watchlist. Only carries tmdbId/mediaType, so each entry is
    /// enriched with title/poster via the same detail lookup used for requests.
    public func watchlist(limit: Int = 20) async throws -> [SeerrItem] {
        try await ensureAuthenticated()
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/discover/watchlist"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "take", value: "\(limit)")]
        let data = try await fetch(comps.url!)
        struct Page: Decodable { let results: [SeerrWatchlistItemResponse] }
        let raw = try JSONDecoder().decode(Page.self, from: data).results

        var items = [SeerrItem?](repeating: nil, count: raw.count)
        await withTaskGroup(of: (Int, SeerrItem?).self) { group in
            for (index, r) in raw.enumerated() {
                group.addTask {
                    let detail = try? await self.mediaDetail(tmdbId: r.tmdbId, mediaType: r.mediaType)
                    return (index, detail)
                }
            }
            for await (index, item) in group { items[index] = item }
        }
        return items.compactMap { $0 }
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
        // live on TMDB, so fetch each item's detail to fill them in. A failure here used to
        // be completely silent (bare try?), leaving the row showing "Unknown" with zero trace
        // of why — same silently-swallowed-error shape already found and fixed for
        // SeerrRepository.loadDiscover and others elsewhere in this codebase.
        // Bounded to a small window: URLSession's ephemeral config allows only ~6 connections
        // per host, and the 15s per-request timeout keeps ticking while a request waits for a
        // free connection — firing all 40 at once made the tail of the burst time out and
        // every one of those rows came back as "Unknown".
        let maxConcurrentDetailFetches = 4
        var items = [SeerrRequestItem?](repeating: nil, count: raw.count)
        await withTaskGroup(of: (Int, SeerrRequestItem).self) { group in
            func fetchItem(_ index: Int) async -> (Int, SeerrRequestItem) {
                let r = raw[index]
                var detail: SeerrItem?
                do {
                    detail = try await mediaDetail(tmdbId: r.media.tmdbId, mediaType: r.media.mediaType)
                } catch {
                    let nsError = error as NSError
                    Telemetry.logger(category: "SeerrHTTPClient").error(
                        "getRequests: detail fetch failed for tmdbId=\(r.media.tmdbId ?? -1, privacy: .public) mediaType=\(r.media.mediaType ?? "nil", privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
                    )
                }
                return (index, r.toItem(detail: detail))
            }
            var nextIndex = 0
            while nextIndex < min(maxConcurrentDetailFetches, raw.count) {
                let index = nextIndex
                group.addTask { await fetchItem(index) }
                nextIndex += 1
            }
            for await (index, item) in group {
                items[index] = item
                if nextIndex < raw.count {
                    let next = nextIndex
                    group.addTask { await fetchItem(next) }
                    nextIndex += 1
                }
            }
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

    /// Full movie/tv detail (genres, runtime, rating, cast, per-season request/library status)
    /// for the request confirmation sheet. `includeSpecials` should come from
    /// `publicSettings().enableSpecialEpisodes` — whether season 0 is offered at all is a
    /// server setting, not something this client decides on its own.
    public func fullDetail(mediaType: RequestMediaType, tmdbId: Int, includeSpecials: Bool = false) async throws -> SeerrMediaDetail {
        try await ensureAuthenticated()
        let path = mediaType == .tv ? "api/v1/tv/\(tmdbId)" : "api/v1/movie/\(tmdbId)"
        let data = try await fetch(baseURL.appendingPathComponent(path))
        return try JSONDecoder().decode(SeerrDetailResponse.self, from: data).toDetail(includeSpecials: includeSpecials)
    }

    /// A title's age rating for a country (e.g. "PG-13", "TV-MA"), from its TMDB release
    /// certifications (movies) or content ratings (TV). Falls back to the US rating, then any.
    /// nil when TMDB has none.
    public func certification(mediaType: RequestMediaType, tmdbId: Int, region: String) async throws -> String? {
        try await ensureAuthenticated()
        let path = mediaType == .tv ? "api/v1/tv/\(tmdbId)" : "api/v1/movie/\(tmdbId)"
        let data = try await fetch(baseURL.appendingPathComponent(path))
        let decoded = try JSONDecoder().decode(SeerrCertificationResponse.self, from: data)
        var byRegion: [String: String] = [:]
        for entry in decoded.releases?.results ?? [] {
            if let rating = entry.releaseDates?.compactMap({ $0.certification }).first(where: { !$0.isEmpty }) {
                byRegion[entry.region] = rating
            }
        }
        for entry in decoded.contentRatings?.results ?? [] where !(entry.rating ?? "").isEmpty {
            byRegion[entry.region] = entry.rating
        }
        return byRegion[region.uppercased()] ?? byRegion["US"] ?? byRegion.values.first
    }

    /// Movies (or shows) matching a TMDB keyword, e.g. "time travel".
    public func discoverByKeyword(_ keywordId: Int, page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage("api/v1/discover/keyword/\(keywordId)/movies", query: [("page", "\(page)")],
                            defaultMediaType: .movie)
    }

    /// Popular titles first made in a language (ISO 639-1, e.g. "ko").
    public func discoverByLanguage(_ language: String, mediaType: RequestMediaType, page: Int = 1) async throws -> [SeerrItem] {
        let path = mediaType == .tv ? "api/v1/discover/tv/language/\(language)" : "api/v1/discover/movies/language/\(language)"
        return try await fetchPage(path, query: [("page", "\(page)")], defaultMediaType: mediaType)
    }

    /// Movies from a studio, or shows from a network, by TMDB id.
    public func discoverByCompany(_ companyId: Int, mediaType: RequestMediaType, page: Int = 1) async throws -> [SeerrItem] {
        let path = mediaType == .tv ? "api/v1/discover/tv/network/\(companyId)" : "api/v1/discover/movies/studio/\(companyId)"
        return try await fetchPage(path, query: [("page", "\(page)")], defaultMediaType: mediaType)
    }

    /// A title's studios (movies) or networks (TV), keywords, where it's streaming in
    /// `region`, and the facts for a details section.
    public func related(mediaType: RequestMediaType, tmdbId: Int, region: String = "US") async throws -> SeerrRelatedInfo {
        try await ensureAuthenticated()
        let path = mediaType == .tv ? "api/v1/tv/\(tmdbId)" : "api/v1/movie/\(tmdbId)"
        let data = try await fetch(baseURL.appendingPathComponent(path))
        let decoded = try JSONDecoder().decode(SeerrRelatedResponse.self, from: data)
        let companies = (mediaType == .tv ? decoded.networks : decoded.productionCompanies) ?? []
        var info = SeerrRelatedInfo(
            companies: companies.map { SeerrNamedEntity(id: $0.id, name: $0.name) },
            keywords: (decoded.keywords ?? []).map { SeerrNamedEntity(id: $0.id, name: $0.name) })
        if let entry = decoded.watchProviders?.first(where: { $0.region == region.uppercased() }) {
            info.watch = SeerrWatchAvailability(
                streaming: (entry.flatrate ?? []).map(\.model), rent: (entry.rent ?? []).map(\.model),
                buy: (entry.buy ?? []).map(\.model), link: entry.link.flatMap(URL.init(string:)))
        }
        info.originalTitle = decoded.originalTitle ?? decoded.originalName
        info.originalLanguage = decoded.originalLanguage
        info.countries = (decoded.productionCountries ?? []).map(\.name)
        info.status = decoded.status
        info.budget = decoded.budget.flatMap { $0 > 0 ? $0 : nil }
        info.revenue = decoded.revenue.flatMap { $0 > 0 ? $0 : nil }
        info.createdBy = (decoded.createdBy ?? []).map(\.name)
        info.networks = (decoded.networks ?? []).map(\.name)
        info.numberOfSeasons = decoded.numberOfSeasons
        info.imdbId = decoded.externalIds?.imdbId ?? decoded.imdbId
        if let next = decoded.nextEpisodeToAir {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            info.nextEpisode = SeerrNextEpisode(
                name: next.name ?? "", seasonNumber: next.seasonNumber ?? 0,
                episodeNumber: next.episodeNumber ?? 0, airDate: next.airDate.flatMap(formatter.date(from:)))
        }
        return info
    }

    /// Rotten Tomatoes and IMDb scores (movies get both, shows Rotten Tomatoes only).
    public func ratings(mediaType: RequestMediaType, tmdbId: Int) async throws -> SeerrRatings {
        try await ensureAuthenticated()
        var result = SeerrRatings()
        if mediaType == .tv {
            let data = try await fetch(baseURL.appendingPathComponent("api/v1/tv/\(tmdbId)/ratings"))
            let rt = try JSONDecoder().decode(SeerrRTResponse.self, from: data)
            result.criticsScore = rt.criticsScore
            result.criticsRating = rt.criticsRating
            result.rottenTomatoesURL = rt.url.flatMap(URL.init(string:))
        } else {
            let data = try await fetch(baseURL.appendingPathComponent("api/v1/movie/\(tmdbId)/ratingscombined"))
            struct Combined: Decodable {
                struct IMDb: Decodable { let criticsScore: Double?; let url: String? }
                let rt: SeerrRTResponse?
                let imdb: IMDb?
            }
            let combined = try JSONDecoder().decode(Combined.self, from: data)
            result.criticsScore = combined.rt?.criticsScore
            result.criticsRating = combined.rt?.criticsRating
            result.audienceScore = combined.rt?.audienceScore
            result.audienceRating = combined.rt?.audienceRating
            result.rottenTomatoesURL = combined.rt?.url.flatMap(URL.init(string:))
            result.imdbScore = combined.imdb?.criticsScore
            result.imdbURL = combined.imdb?.url.flatMap(URL.init(string:))
        }
        return result
    }

    /// The streaming services TMDB lists for a country, most popular first.
    public func watchProviders(mediaType: RequestMediaType, region: String) async throws -> [SeerrWatchProvider] {
        try await ensureAuthenticated()
        var comps = URLComponents(
            url: baseURL.appendingPathComponent(mediaType == .tv ? "api/v1/watchproviders/tv" : "api/v1/watchproviders/movies"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "watchRegion", value: region.uppercased())]
        let data = try await fetch(comps.url!)
        return try JSONDecoder().decode([SeerrProviderResponse].self, from: data).map(\.model)
    }

    /// Popular titles on a streaming service in a country.
    public func discoverByWatchProvider(_ providerId: Int, mediaType: RequestMediaType, region: String, page: Int = 1) async throws -> [SeerrItem] {
        try await fetchPage(mediaType == .tv ? "api/v1/discover/tv" : "api/v1/discover/movies",
                            query: [("watchProviders", "\(providerId)"), ("watchRegion", region.uppercased()),
                                    ("sortBy", "popularity.desc"), ("page", "\(page)")],
                            defaultMediaType: mediaType)
    }

    /// Server-wide request settings — whether a partial (per-season) request is even offered,
    /// and whether specials (season 0) are included in the season picker at all. Unauthenticated;
    /// Seerr serves this publicly.
    public func publicSettings() async throws -> SeerrPublicSettings {
        let data = try await fetch(baseURL.appendingPathComponent("api/v1/settings/public"))
        struct Response: Decodable {
            let partialRequestsEnabled: Bool?
            let enableSpecialEpisodes: Bool?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return SeerrPublicSettings(
            partialRequestsEnabled: r.partialRequestsEnabled ?? true,
            enableSpecialEpisodes: r.enableSpecialEpisodes ?? false
        )
    }

    /// The signed-in Seerr user's id and permission bitmask — needed to read their own
    /// request quota and to tell whether their requests auto-approve.
    public func currentUser() async throws -> SeerrCurrentUser {
        try await ensureAuthenticated()
        let data = try await fetch(baseURL.appendingPathComponent("api/v1/auth/me"))
        struct Response: Decodable {
            let id: Int
            let permissions: Int?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return SeerrCurrentUser(id: r.id, permissions: r.permissions ?? 0)
    }

    /// A user's series request quota — nil if the server sent no `tv` quota at all (no limit
    /// configured), distinct from a limit of 0.
    public func seasonQuota(userId: Int) async throws -> SeerrSeasonQuota? {
        try await ensureAuthenticated()
        let data = try await fetch(baseURL.appendingPathComponent("api/v1/user/\(userId)/quota"))
        struct Response: Decodable {
            struct Quota: Decodable {
                let days: Int?
                let limit: Int?
                let remaining: Int?
                let restricted: Bool?
            }
            let tv: Quota?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        guard let tv = r.tv else { return nil }
        return SeerrSeasonQuota(limit: tv.limit, remaining: tv.remaining, days: tv.days, restricted: tv.restricted ?? false)
    }

    public func createRequest(mediaType: RequestMediaType, mediaId: Int, seasons: [Int] = []) async throws {
        try await ensureAuthenticated()
        let url = baseURL.appendingPathComponent("api/v1/request")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyXSRF(to: &req)
        var body: [String: Any] = ["mediaType": mediaType.rawValue, "mediaId": mediaId]
        // Seerr requires an explicit seasons array for tv requests — omitting it
        // (rather than sending all season numbers) does not request the full series.
        if mediaType == .tv { body["seasons"] = seasons }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw SeerrError.requestFailed(status: status, body: bodyText)
        }
    }

    public func addToWatchlist(tmdbId: Int, mediaType: RequestMediaType, title: String) async throws {
        try await ensureAuthenticated()
        let url = baseURL.appendingPathComponent("api/v1/watchlist")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyXSRF(to: &req)
        // Seerr's watchlist schema requires `mediaType`; the old `type` key was rejected with a
        // 400 on every add, which the callers' try? swallowed.
        let body: [String: Any] = ["tmdbId": tmdbId, "mediaType": mediaType.rawValue, "title": title]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SeerrError.requestFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    public func removeFromWatchlist(tmdbId: Int, mediaType: RequestMediaType) async throws {
        try await ensureAuthenticated()
        var comps = URLComponents(url: baseURL.appendingPathComponent("api/v1/watchlist/\(tmdbId)"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "mediaType", value: mediaType.rawValue)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        applyXSRF(to: &req)
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SeerrError.requestFailed(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Cancels a pending request, or removes a declined/available one from the list —
    /// Seerr uses the same DELETE for both.
    public func cancelRequest(requestID: Int) async throws {
        try await ensureAuthenticated()
        let url = baseURL.appendingPathComponent("api/v1/request/\(requestID)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        applyXSRF(to: &req)
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
    case requestFailed(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .authFailed:
            return "Invalid Seerr username or password."
        case .requestFailed(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Server returned HTTP \(status)." : "HTTP \(status): \(trimmed.prefix(200))"
        }
    }
}

// MARK: - Private response decoders

private struct SeerrGenreResponse: Decodable {
    let id: Int
    let name: String
    let backdrops: [String]?

    func toGenre() -> SeerrGenre {
        SeerrGenre(id: id, name: name, backdropPath: backdrops?.first)
    }
}

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
    let adult: Bool?
    // Only present on a person's combined_credits entries — a plain discover/search/
    // recommendations row never has these, so they're harmlessly nil everywhere else.
    let character: String?
    let job: String?

    private var resolvedMediaType: RequestMediaType? {
        mediaType.map { $0 == "tv" ? .tv : .movie }
    }

    func toItem(defaultMediaType: RequestMediaType? = nil) -> SeerrItem? {
        // Search also returns people (and collections), which aren't requestable titles.
        guard mediaType == nil || mediaType == "movie" || mediaType == "tv",
              let displayTitle = title ?? name else { return nil }
        let type = resolvedMediaType ?? defaultMediaType ?? .movie
        let year = (releaseDate ?? firstAirDate).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let status = mediaInfo.flatMap { SeerrAvailabilityStatus(rawValue: $0.status) }
        return SeerrItem(id: id, title: displayTitle, mediaType: type,
                         posterPath: posterPath, backdropPath: backdropPath,
                         year: year, overview: overview, availabilityStatus: status,
                         isAdult: adult ?? false)
    }

    /// For a person's combined_credits row — needs the TMDB-assigned mediaType (unlike
    /// toItem(defaultMediaType:) above, there's no sensible single default across a whole
    /// filmography) and keeps character/job instead of discarding them.
    func toCredit() -> SeerrPersonCredit? {
        guard let displayTitle = title ?? name, let type = resolvedMediaType else { return nil }
        let status = mediaInfo.flatMap { SeerrAvailabilityStatus(rawValue: $0.status) }
        return SeerrPersonCredit(id: id, title: displayTitle, mediaType: type, posterPath: posterPath,
                                 role: character ?? job, mediaStatus: status)
    }
}

private struct SeerrMediaInfoResponse: Decodable {
    let status: Int
}

private struct SeerrWatchlistItemResponse: Decodable {
    let tmdbId: Int?
    let mediaType: String?
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
        let status: Int?
    }

    func toItem(detail: SeerrItem?) -> SeerrRequestItem {
        let reqStatus = RequestStatus(rawValue: status) ?? .pending
        let mediaStatus = media.status.flatMap { SeerrAvailabilityStatus(rawValue: $0) }
        let mType: RequestMediaType = media.mediaType == "tv" ? .tv : .movie
        let title = detail?.title ?? "Unknown"
        let date = createdAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        return SeerrRequestItem(id: id, mediaTitle: title, mediaType: mType,
                                status: reqStatus, mediaStatus: mediaStatus, requestedAt: date,
                                posterPath: detail?.posterPath, backdropPath: detail?.backdropPath,
                                tmdbId: media.tmdbId)
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
    let seasons: [SeerrSeason]?     // tv only
    let mediaInfo: SeerrMediaInfo?
    let relatedVideos: [SeerrVideo]?

    /// TMDB-backed, included in Seerr's standard detail response. `site` is almost always
    /// "YouTube" (Jellyseerr/Overseerr only ever source these from TMDB, which itself only
    /// stores YouTube keys) but checked anyway rather than assumed.
    struct SeerrVideo: Decodable {
        let key: String
        let site: String?
        let type: String?
    }

    struct SeerrGenre: Decodable { let name: String }
    struct SeerrCredits: Decodable { let cast: [SeerrCast]? }
    struct SeerrCast: Decodable {
        let id: Int
        let name: String
        let character: String?
        let profilePath: String?
    }
    struct SeerrSeason: Decodable {
        let seasonNumber: Int
        let episodeCount: Int?
    }

    /// What the library/request pipeline knows about this title, beyond its TMDB record —
    /// absent entirely when nobody has ever requested or added it.
    struct SeerrMediaInfo: Decodable {
        let seasons: [SeasonStatus]?
        let requests: [RequestInfo]?

        /// MediaStatus as Seerr numbers it: 1 unknown, 2 pending, 3 processing,
        /// 4 partially available, 5 available, 6 blocklisted, 7 deleted.
        struct SeasonStatus: Decodable {
            let seasonNumber: Int
            let status: Int
        }

        /// A standing (or past) request. `seasons` carries each season's own status,
        /// numbered as a request status (MediaRequestStatus), not the library's.
        struct RequestInfo: Decodable {
            let status: Int
            let is4k: Bool?
            let seasons: [RequestSeason]?

            struct RequestSeason: Decodable {
                let seasonNumber: Int
                let status: Int
            }
        }
    }

    /// Per-season request/library status, read the same way Seerr's own request table reads
    /// it (TvRequestModal/seasonRows): the library first, unless it lost the season, then a
    /// request that still stands. MediaRequestStatus: 1 pending, 2 approved, 3 declined,
    /// 4 failed, 5 completed. MediaStatus: 1 unknown, 5 available, 4 partially available,
    /// 3 processing, 7 deleted.
    private func seasonRows(includeSpecials: Bool) -> [SeerrSeasonRow] {
        let standingRequests = (mediaInfo?.requests ?? []).filter {
            $0.is4k != true && $0.status != 3 && $0.status != 5
        }
        let standingSeasonRequests = standingRequests.flatMap { $0.seasons ?? [] }

        return (seasons ?? [])
            .filter { ($0.episodeCount ?? 0) != 0 && (includeSpecials || $0.seasonNumber > 0) }
            .map { season in
                let seasonRequest = standingSeasonRequests.first {
                    $0.seasonNumber == season.seasonNumber && $0.status != 5
                }
                let mediaSeason = mediaInfo?.seasons?.first {
                    $0.seasonNumber == season.seasonNumber && $0.status != 1 && $0.status != 7
                }

                var badge: SeerrSeasonBadge?
                if mediaSeason?.status == 5 {
                    badge = .available
                } else if mediaSeason?.status == 4 {
                    badge = .partiallyAvailable
                } else if mediaSeason?.status == 3 || (mediaSeason == nil && seasonRequest?.status == 2) {
                    badge = .requested
                } else if mediaSeason == nil && seasonRequest?.status == 1 {
                    badge = .pending
                } else if mediaSeason == nil && seasonRequest == nil {
                    badge = .notRequested
                }

                return SeerrSeasonRow(
                    seasonNumber: season.seasonNumber,
                    episodeCount: season.episodeCount ?? 0,
                    badge: badge,
                    locked: mediaSeason != nil || seasonRequest != nil
                )
            }
            .sorted { $0.seasonNumber < $1.seasonNumber }
    }

    /// Prefers an actual "Trailer" over a "Teaser"/other clip; either way, only a YouTube
    /// video is playable through YouTubeTrailerPlayerView.
    private var trailerYouTubeKey: String? {
        let youTubeVideos = (relatedVideos ?? []).filter { $0.site == "YouTube" }
        return (youTubeVideos.first { $0.type == "Trailer" } ?? youTubeVideos.first)?.key
    }

    func toDetail(includeSpecials: Bool = false) -> SeerrMediaDetail {
        let cast = (credits?.cast ?? []).prefix(10).map {
            SeerrCastMember(id: $0.id, name: $0.name, character: $0.character, profilePath: $0.profilePath)
        }
        let seasonList = (seasons ?? [])
            .filter { $0.seasonNumber > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
            .map { SeerrSeasonInfo(number: $0.seasonNumber, episodeCount: $0.episodeCount) }
        return SeerrMediaDetail(
            tagline: (tagline?.isEmpty ?? true) ? nil : tagline,
            overview: overview,
            genres: (genres ?? []).map(\.name),
            runtimeMinutes: runtime ?? episodeRunTime?.first,
            voteAverage: voteAverage,
            status: status,
            cast: Array(cast),
            seasons: seasonList,
            seasonRows: seasonList.isEmpty ? nil : seasonRows(includeSpecials: includeSpecials),
            trailerYouTubeKey: trailerYouTubeKey
        )
    }
}

private struct SeerrCertificationResponse: Decodable {
    struct Releases: Decodable {
        struct Entry: Decodable {
            struct ReleaseDate: Decodable { let certification: String? }
            let region: String
            let releaseDates: [ReleaseDate]?
            enum CodingKeys: String, CodingKey { case region = "iso_3166_1", releaseDates = "release_dates" }
        }
        let results: [Entry]?
    }
    struct ContentRatings: Decodable {
        struct Entry: Decodable {
            let region: String
            let rating: String?
            enum CodingKeys: String, CodingKey { case region = "iso_3166_1", rating }
        }
        let results: [Entry]?
    }
    let releases: Releases?
    let contentRatings: ContentRatings?
}

private struct SeerrProviderResponse: Decodable {
    let id: Int
    let name: String
    let logoPath: String?
    var model: SeerrWatchProvider { SeerrWatchProvider(id: id, name: name, logoPath: logoPath) }
}

private struct SeerrRTResponse: Decodable {
    let criticsScore: Int?
    let criticsRating: String?
    let audienceScore: Int?
    let audienceRating: String?
    let url: String?
}

private struct SeerrRelatedResponse: Decodable {
    struct Named: Decodable { let id: Int; let name: String }
    struct Country: Decodable { let name: String }
    struct Creator: Decodable { let name: String }
    struct ExternalIds: Decodable { let imdbId: String? }
    struct Episode: Decodable {
        let name: String?
        let seasonNumber: Int?
        let episodeNumber: Int?
        let airDate: String?
    }
    struct WatchEntry: Decodable {
        let region: String
        let link: String?
        let flatrate: [SeerrProviderResponse]?
        let rent: [SeerrProviderResponse]?
        let buy: [SeerrProviderResponse]?
        enum CodingKeys: String, CodingKey { case region = "iso_3166_1", link, flatrate, rent, buy }
    }
    let productionCompanies: [Named]?
    let networks: [Named]?
    let keywords: [Named]?
    let watchProviders: [WatchEntry]?
    let originalTitle: String?
    let originalName: String?
    let originalLanguage: String?
    let productionCountries: [Country]?
    let status: String?
    let budget: Int?
    let revenue: Int?
    let createdBy: [Creator]?
    let numberOfSeasons: Int?
    let nextEpisodeToAir: Episode?
    let externalIds: ExternalIds?
    let imdbId: String?
}
