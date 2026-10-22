// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// A movie or episode marked watched, with what Stats needs beyond a MediaItem.
public struct WatchedTitle: Sendable, Identifiable, Hashable {
    public let item: MediaItem
    public let runTimeTicks: Int64
    public let genres: [String]
    public let studios: [String]
    public let officialRating: String?

    public var id: String { item.id }
    public var lastPlayed: Date? { item.userData?.lastPlayedDate }
    public var playCount: Int { max(item.userData?.playCount ?? 1, 1) }
    public var runtimeSeconds: Double { Double(runTimeTicks) / 10_000_000 }

    public init(item: MediaItem, runTimeTicks: Int64, genres: [String] = [], studios: [String] = [], officialRating: String? = nil) {
        self.item = item
        self.runTimeTicks = runTimeTicks
        self.genres = genres
        self.studios = studios
        self.officialRating = officialRating
    }
}

/// A show's or movie's own details, which its episodes or the watched list don't carry.
public struct StatsTitleDetails: Sendable, Hashable {
    public let item: MediaItem
    public let genres: [String]
    public let studios: [String]
    public let people: [MediaPerson]
    /// Episodes of a show not yet watched.
    public let unplayedCount: Int?

    public init(item: MediaItem, genres: [String] = [], studios: [String] = [], people: [MediaPerson] = [], unplayedCount: Int? = nil) {
        self.item = item
        self.genres = genres
        self.studios = studios
        self.people = people
        self.unplayedCount = unplayedCount
    }
}

/// Library-wide totals for the signed-in user.
public struct StatsLibraryCounts: Sendable, Equatable {
    public var movies = 0
    public var shows = 0
    public var episodes = 0
    public var watchedMovies = 0
    public var watchedEpisodes = 0
    public var finishedShows = 0
    public var inProgress = 0
    public var favourites = 0

    public init() {}
}

extension JellyfinMediaClient {

    // MARK: - Stats

    /// Every movie and episode marked watched, most recently played first.
    public func getWatchedTitles(credential: ServerCredential, authHeader: String, limit: Int = 10_000) async throws -> [WatchedTitle] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "IncludeItemTypes", value: "Movie,Episode"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "DatePlayed"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Fields", value: "Genres,Studios,OfficialRating,SeriesId,SeriesName,SeriesPrimaryImageTag,ProductionYear,CommunityRating,PrimaryImageTags"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImageTypes", value: "Primary"),
            .init(name: "ImageTypeLimit", value: "1"),
            .init(name: "Limit", value: "\(limit)"),
        ]
        let data = try await statsData(comps.url!, timeout: 60, authHeader: authHeader)
        let items = try JSONDecoder().decode(ItemsPage.self, from: data).items
        let extras = try JSONDecoder().decode(StatsExtrasPage.self, from: data).items
        return zip(items, extras).map { item, extra in
            WatchedTitle(item: item.toMediaItem(), runTimeTicks: extra.runTimeTicks ?? 0,
                         genres: item.genres ?? [], studios: extra.studios?.map(\.name) ?? [],
                         officialRating: extra.officialRating)
        }
    }

    /// Shows' and movies' own genres, studios, unwatched counts and, when asked, cast and crew.
    public func getStatsDetails(credential: ServerCredential, authHeader: String, ids: [String], includePeople: Bool) async throws -> [String: StatsTitleDetails] {
        var result: [String: StatsTitleDetails] = [:]
        var start = 0
        while start < ids.count {
            let chunk = ids[start..<min(start + 80, ids.count)]
            start += 80
            var comps = URLComponents(
                url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
                resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                .init(name: "Ids", value: chunk.joined(separator: ",")),
                .init(name: "Fields", value: "Genres,Studios,ProductionYear,PrimaryImageTags,BackdropImageTags" + (includePeople ? ",People" : "")),
                .init(name: "EnableUserData", value: "true"),
                .init(name: "EnableImageTypes", value: "Primary,Backdrop"),
                .init(name: "ImageTypeLimit", value: "1"),
            ]
            let data = try await statsData(comps.url!, timeout: 30, authHeader: authHeader)
            let items = try JSONDecoder().decode(ItemsPage.self, from: data).items
            let extras = try JSONDecoder().decode(StatsExtrasPage.self, from: data).items
            for (item, extra) in zip(items, extras) {
                let people = (extra.people ?? []).map {
                    MediaPerson(id: $0.id, name: $0.name, role: $0.role, primaryImageTag: $0.primaryImageTag, type: $0.type ?? "Actor")
                }
                result[item.id] = StatsTitleDetails(
                    item: item.toMediaItem(), genres: item.genres ?? [], studios: extra.studios?.map(\.name) ?? [],
                    people: people, unplayedCount: extra.userData?.unplayedItemCount)
            }
        }
        return result
    }

    public func getStatsLibraryCounts(credential: ServerCredential, authHeader: String) async -> StatsLibraryCounts {
        func total(_ types: String, _ filters: String? = nil) async -> Int {
            var comps = URLComponents(
                url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
                resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                .init(name: "IncludeItemTypes", value: types),
                .init(name: "Recursive", value: "true"),
                .init(name: "Limit", value: "0"),
            ]
            if let filters { comps.queryItems?.append(.init(name: "Filters", value: filters)) }
            guard let data = try? await statsData(comps.url!, timeout: 20, authHeader: authHeader) else { return 0 }
            return (try? JSONDecoder().decode(ItemsPage.self, from: data).totalRecordCount) ?? 0
        }
        async let movies = total("Movie")
        async let shows = total("Series")
        async let episodes = total("Episode")
        async let watchedMovies = total("Movie", "IsPlayed")
        async let watchedEpisodes = total("Episode", "IsPlayed")
        async let finishedShows = total("Series", "IsPlayed")
        async let inProgress = total("Movie,Episode", "IsResumable")
        async let favourites = total("Movie,Series,Episode", "IsFavorite")
        var counts = StatsLibraryCounts()
        counts.movies = await movies
        counts.shows = await shows
        counts.episodes = await episodes
        counts.watchedMovies = await watchedMovies
        counts.watchedEpisodes = await watchedEpisodes
        counts.finishedShows = await finishedShows
        counts.inProgress = await inProgress
        counts.favourites = await favourites
        return counts
    }

    private func statsData(_ url: URL, timeout: TimeInterval, authHeader: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout
        let (data, response) = try await URLSession.arcfin.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw JellyfinRequestError.status(http.statusCode)
        }
        return data
    }
}

/// The parts of an item response the shared JellyfinItemResponse leaves out, decoded from
/// the same data alongside it.
private struct StatsExtrasPage: Decodable {
    struct Named: Decodable {
        let name: String
        enum CodingKeys: String, CodingKey { case name = "Name" }
    }
    struct Person: Decodable {
        let id: String
        let name: String
        let role: String?
        let primaryImageTag: String?
        let type: String?
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", role = "Role", primaryImageTag = "PrimaryImageTag", type = "Type"
        }
    }
    struct Counts: Decodable {
        let unplayedItemCount: Int?
        enum CodingKeys: String, CodingKey { case unplayedItemCount = "UnplayedItemCount" }
    }
    struct Extras: Decodable {
        let runTimeTicks: Int64?
        let studios: [Named]?
        let officialRating: String?
        let people: [Person]?
        let userData: Counts?
        enum CodingKeys: String, CodingKey {
            case runTimeTicks = "RunTimeTicks", studios = "Studios", officialRating = "OfficialRating"
            case people = "People", userData = "UserData"
        }
    }
    let items: [Extras]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}
