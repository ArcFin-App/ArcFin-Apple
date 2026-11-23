// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The Movie Database, asked directly with the user's own API key: used where Seerr isn't
/// set up, and when a Seerr request fails. Returns the same models as SeerrHTTPClient so
/// screens don't care which answered. Read-only — requests still need Seerr.
public struct TMDBClient: Sendable {
    private let key: String
    private let session: URLSession
    private static let base = URL(string: "https://api.themoviedb.org/3/")!

    /// `key` is either a v3 API key (32 hex characters) or a v4 read access token.
    public init(key: String) {
        self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    private var usesBearerToken: Bool { key.count > 40 }

    // MARK: - Lists

    public func trending() async throws -> [SeerrItem] {
        try await page("trending/all/week", [:])
    }

    public func popular(mediaType: RequestMediaType) async throws -> [SeerrItem] {
        try await page(mediaType == .tv ? "tv/popular" : "movie/popular", [:], mediaType: mediaType)
    }

    public func upcoming(mediaType: RequestMediaType) async throws -> [SeerrItem] {
        mediaType == .tv
            ? try await page("tv/on_the_air", [:], mediaType: .tv)
            : try await page("movie/upcoming", [:], mediaType: .movie)
    }

    public func related(mediaType: RequestMediaType, id: Int) async throws -> [SeerrItem] {
        let kind = mediaType == .tv ? "tv" : "movie"
        async let recommendations = page("\(kind)/\(id)/recommendations", [:], mediaType: mediaType)
        async let similar = page("\(kind)/\(id)/similar", [:], mediaType: mediaType)
        let merged = try await recommendations + ((try? await similar) ?? [])
        var seen = Set<Int>()
        return merged.filter { seen.insert($0.id).inserted }
    }

    public func discover(mediaType: RequestMediaType, filters: [String: String]) async throws -> [SeerrItem] {
        try await page(mediaType == .tv ? "discover/tv" : "discover/movie",
                       filters.merging(["sort_by": "popularity.desc"]) { current, _ in current },
                       mediaType: mediaType)
    }

    public func search(_ query: String) async throws -> [SeerrItem] {
        try await page("search/multi", ["query": query])
    }

    // MARK: - Streaming

    public func watchProviders(mediaType: RequestMediaType, region: String) async throws -> [SeerrWatchProvider] {
        struct Response: Decodable {
            struct Provider: Decodable { let providerId: Int; let providerName: String; let logoPath: String? }
            let results: [Provider]
        }
        let data = try await get(mediaType == .tv ? "watch/providers/tv" : "watch/providers/movie", ["watch_region": region])
        return try Self.decoder.decode(Response.self, from: data).results.map {
            SeerrWatchProvider(id: $0.providerId, name: $0.providerName, logoPath: $0.logoPath)
        }
    }

    public func watchRegions() async throws -> [(code: String, name: String)] {
        struct Response: Decodable {
            struct Region: Decodable { let iso31661: String; let englishName: String }
            let results: [Region]
        }
        let data = try await get("watch/providers/regions", [:])
        return try Self.decoder.decode(Response.self, from: data).results.map { ($0.iso31661, $0.englishName) }
    }

    // MARK: - Details

    /// Everything a title's page uses, in one request: facts, rating certifications,
    /// keywords, where it's streaming and external ids.
    public func details(mediaType: RequestMediaType, id: Int, region: String) async throws -> (info: SeerrRelatedInfo, detail: SeerrMediaDetail, certification: String?) {
        let kind = mediaType == .tv ? "tv" : "movie"
        let append = mediaType == .tv
            ? "content_ratings,keywords,watch/providers,external_ids,credits,videos"
            : "release_dates,keywords,watch/providers,external_ids,credits,videos"
        let data = try await get("\(kind)/\(id)", ["append_to_response": append])
        let d = try Self.decoder.decode(DetailResponse.self, from: data)

        var info = SeerrRelatedInfo(
            companies: ((mediaType == .tv ? d.networks : d.productionCompanies) ?? []).map { SeerrNamedEntity(id: $0.id, name: $0.name) },
            keywords: ((d.keywords?.keywords ?? d.keywords?.results) ?? []).map { SeerrNamedEntity(id: $0.id, name: $0.name) })
        if let entry = d.watchProviders?.results?[region.uppercased()] {
            var watch = SeerrWatchAvailability(
                streaming: entry.flatrate?.map(\.model) ?? [], rent: entry.rent?.map(\.model) ?? [],
                buy: entry.buy?.map(\.model) ?? [], link: entry.link.flatMap(URL.init(string:)))
            watch.free = entry.free?.map(\.model) ?? []
            watch.ads = entry.ads?.map(\.model) ?? []
            info.watch = watch
        }
        info.originalTitle = d.originalTitle ?? d.originalName
        info.originalLanguage = d.originalLanguage
        info.countries = (d.productionCountries ?? []).map(\.name)
        info.status = d.status
        info.budget = d.budget.flatMap { $0 > 0 ? $0 : nil }
        info.revenue = d.revenue.flatMap { $0 > 0 ? $0 : nil }
        info.createdBy = (d.createdBy ?? []).map(\.name)
        info.networks = (d.networks ?? []).map(\.name)
        info.numberOfSeasons = d.numberOfSeasons
        info.imdbId = d.externalIds?.imdbId ?? d.imdbId
        if let next = d.nextEpisodeToAir {
            info.nextEpisode = SeerrNextEpisode(
                name: next.name ?? "", seasonNumber: next.seasonNumber ?? 0,
                episodeNumber: next.episodeNumber ?? 0, airDate: next.airDate.flatMap(Self.day))
        }

        let videos = (d.videos?.results ?? []).filter { $0.site == "YouTube" }
        let detail = SeerrMediaDetail(
            tagline: (d.tagline?.isEmpty ?? true) ? nil : d.tagline,
            overview: d.overview,
            genres: (d.genres ?? []).map(\.name),
            runtimeMinutes: d.runtime ?? d.episodeRunTime?.first,
            voteAverage: d.voteAverage,
            status: d.status,
            cast: (d.credits?.cast ?? []).prefix(10).map {
                SeerrCastMember(id: $0.id, name: $0.name, character: $0.character, profilePath: $0.profilePath)
            },
            seasons: (d.seasons ?? []).filter { $0.seasonNumber > 0 }.map {
                SeerrSeasonInfo(number: $0.seasonNumber, episodeCount: $0.episodeCount)
            },
            trailerYouTubeKey: (videos.first { $0.type == "Trailer" } ?? videos.first)?.key)

        var byRegion: [String: String] = [:]
        for entry in d.releaseDates?.results ?? [] {
            if let rating = entry.releaseDates?.compactMap(\.certification).first(where: { !$0.isEmpty }) {
                byRegion[entry.iso31661] = rating
            }
        }
        for entry in d.contentRatings?.results ?? [] where !(entry.rating ?? "").isEmpty {
            byRegion[entry.iso31661] = entry.rating
        }
        let certification = byRegion[region.uppercased()] ?? byRegion["US"] ?? byRegion.values.first
        return (info, detail, certification)
    }

    // MARK: - Plumbing

    private func page(_ path: String, _ query: [String: String], mediaType: RequestMediaType? = nil) async throws -> [SeerrItem] {
        struct Page: Decodable { let results: [Row] }
        let data = try await get(path, query)
        return try Self.decoder.decode(Page.self, from: data).results.compactMap { $0.item(defaultMediaType: mediaType) }
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> Data {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !usesBearerToken { items.append(URLQueryItem(name: "api_key", value: key)) }
        comps.queryItems = items.isEmpty ? nil : items
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if usesBearerToken { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        await withCheckedContinuation { PathWait(continuation: $0).start(timeoutSeconds: 6) }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            struct Message: Decodable { let statusMessage: String? }
            let message = (try? Self.decoder.decode(Message.self, from: data))?.statusMessage ?? ""
            throw SeerrError.requestFailed(status: http.statusCode, body: message)
        }
        return data
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func day(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    private struct Row: Decodable {
        let id: Int
        let title: String?
        let name: String?
        let mediaType: String?
        let posterPath: String?
        let backdropPath: String?
        let releaseDate: String?
        let firstAirDate: String?
        let overview: String?
        let adult: Bool?

        func item(defaultMediaType: RequestMediaType?) -> SeerrItem? {
            guard mediaType == nil || mediaType == "movie" || mediaType == "tv",
                  let displayTitle = title ?? name else { return nil }
            let type: RequestMediaType = mediaType.map { $0 == "tv" ? .tv : .movie } ?? defaultMediaType ?? .movie
            let date = releaseDate ?? firstAirDate
            let year = date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
            return SeerrItem(id: id, title: displayTitle, mediaType: type, posterPath: posterPath,
                             backdropPath: backdropPath, year: year, overview: overview, isAdult: adult ?? false)
        }
    }

    private struct ProviderRow: Decodable {
        let providerId: Int
        let providerName: String
        let logoPath: String?
        var model: SeerrWatchProvider { SeerrWatchProvider(id: providerId, name: providerName, logoPath: logoPath) }
    }

    private struct DetailResponse: Decodable {
        struct Named: Decodable { let id: Int; let name: String }
        struct Country: Decodable { let name: String }
        struct Genre: Decodable { let name: String }
        struct Creator: Decodable { let name: String }
        struct ExternalIds: Decodable { let imdbId: String? }
        struct Episode: Decodable { let name: String?; let seasonNumber: Int?; let episodeNumber: Int?; let airDate: String? }
        struct Season: Decodable { let seasonNumber: Int; let episodeCount: Int? }
        struct Keywords: Decodable { let keywords: [Named]?; let results: [Named]? }
        struct WatchProviders: Decodable {
            struct Entry: Decodable {
                let link: String?
                let flatrate: [ProviderRow]?
                let free: [ProviderRow]?
                let ads: [ProviderRow]?
                let rent: [ProviderRow]?
                let buy: [ProviderRow]?
            }
            let results: [String: Entry]?
        }
        struct ReleaseDates: Decodable {
            struct Entry: Decodable {
                struct Release: Decodable { let certification: String? }
                let iso31661: String
                let releaseDates: [Release]?
            }
            let results: [Entry]?
        }
        struct ContentRatings: Decodable {
            struct Entry: Decodable { let iso31661: String; let rating: String? }
            let results: [Entry]?
        }
        struct Credits: Decodable {
            struct Cast: Decodable { let id: Int; let name: String; let character: String?; let profilePath: String? }
            let cast: [Cast]?
        }
        struct Videos: Decodable {
            struct Video: Decodable { let key: String; let site: String?; let type: String? }
            let results: [Video]?
        }

        let tagline: String?
        let overview: String?
        let genres: [Genre]?
        let runtime: Int?
        let episodeRunTime: [Int]?
        let voteAverage: Double?
        let status: String?
        let originalTitle: String?
        let originalName: String?
        let originalLanguage: String?
        let productionCompanies: [Named]?
        let productionCountries: [Country]?
        let networks: [Named]?
        let createdBy: [Creator]?
        let numberOfSeasons: Int?
        let nextEpisodeToAir: Episode?
        let seasons: [Season]?
        let budget: Int?
        let revenue: Int?
        let imdbId: String?
        let externalIds: ExternalIds?
        let keywords: Keywords?
        let watchProviders: WatchProviders?
        let releaseDates: ReleaseDates?
        let contentRatings: ContentRatings?
        let credits: Credits?
        let videos: Videos?

        // "watch/providers" doesn't come out of the snake-case conversion as a property name.
        enum CodingKeys: String, CodingKey {
            case tagline, overview, genres, runtime, episodeRunTime, voteAverage, status
            case originalTitle, originalName, originalLanguage, productionCompanies, productionCountries
            case networks, createdBy, numberOfSeasons, nextEpisodeToAir, seasons, budget, revenue
            case imdbId, externalIds, keywords, releaseDates, contentRatings, credits, videos
            case watchProviders = "watch/providers"
        }
    }
}
