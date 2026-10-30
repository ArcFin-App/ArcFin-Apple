// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
import AuthCore
import SeerrAPI

enum HomeShelf: String, CaseIterable, Identifiable {
    case continueWatching, nextUp, recentlyAddedMovies, recentlyAddedShows
    case recentlyReleasedMovies, recentlyAiredEpisodes, watchAgain, becauseYouWatched, genreShelves
    case favorites, topRatedUnwatched
    case nowAvailable
    case suggested, recommendations
    case streamingServices
    case seerrWatchlist, seerrTrending, seerrPopularMovies, seerrPopularSeries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueWatching:       String(localized: "Continue Watching")
        case .nextUp:                 String(localized: "Next Up")
        case .recentlyAddedMovies:    String(localized: "Recently Added Movies")
        case .recentlyAddedShows:     String(localized: "Recently Added Shows")
        case .recentlyReleasedMovies: String(localized: "Recently Released Movies")
        case .recentlyAiredEpisodes:  String(localized: "Recently Aired Episodes")
        case .watchAgain:             String(localized: "Watch Again")
        case .genreShelves:           String(localized: "Genre Picks")
        case .becauseYouWatched:      String(localized: "Because You Watched")
        case .favorites:              String(localized: "Favorites")
        case .topRatedUnwatched:      String(localized: "Top Rated, Unwatched")
        case .nowAvailable:           String(localized: "Now Available")
        case .suggested:              String(localized: "Suggested for You")
        case .recommendations:        String(localized: "Recommended")
        case .streamingServices:      String(localized: "Your Streaming Services")
        case .seerrWatchlist:         String(localized: "Watchlist")
        case .seerrTrending:          String(localized: "Trending")
        case .seerrPopularMovies:     String(localized: "Popular Movies")
        case .seerrPopularSeries:     String(localized: "Popular Series")
        }
    }

    var isSeerr: Bool {
        switch self {
        case .nowAvailable, .streamingServices, .seerrWatchlist, .seerrTrending, .seerrPopularMovies, .seerrPopularSeries: true
        default: false
        }
    }

    var icon: String {
        switch self {
        case .continueWatching:       "play.circle"
        case .nextUp:                 "forward.circle"
        case .recentlyAddedMovies:    "film"
        case .recentlyAddedShows:     "tv"
        case .recentlyReleasedMovies: "sparkles"
        case .recentlyAiredEpisodes:  "calendar"
        case .watchAgain:             "arrow.counterclockwise"
        case .genreShelves:           "theatermasks"
        case .becauseYouWatched:      "sparkles.tv"
        case .favorites:              "heart"
        case .topRatedUnwatched:      "star.leadinghalf.filled"
        case .nowAvailable:           "checkmark.seal"
        case .suggested:              "wand.and.stars"
        case .recommendations:        "hand.thumbsup"
        case .streamingServices:      "play.tv"
        case .seerrWatchlist:         "bookmark"
        case .seerrTrending:          "chart.line.uptrend.xyaxis"
        case .seerrPopularMovies:     "star"
        case .seerrPopularSeries:     "star.fill"
        }
    }
}

enum HomeShelfPrefs {
    static let orderKey = "homeShelfOrder"
    static let activeKey = "homeShelfActive"
    static let shuffleKey = "shuffleHomeShelves"
    /// Every shelf there was when the active list was last saved.
    static let knownKey = "homeShelfKnown"

    /// The shelves in 0.1.0, which saved its active list without a known list beside it.
    private static let firstShelves: Set<HomeShelf> = [
        .continueWatching, .nextUp, .recentlyAddedMovies, .recentlyAddedShows,
        .recentlyReleasedMovies, .recentlyAiredEpisodes, .watchAgain,
        .seerrWatchlist, .seerrTrending, .seerrPopularMovies, .seerrPopularSeries,
    ]

    /// Continue Watching and Up Next always lead; everything else is fair game when shuffling.
    static let pinned: [HomeShelf] = [.continueWatching, .nextUp]

    static func shuffledOrder() -> [HomeShelf] {
        pinned + HomeShelf.allCases.filter { !pinned.contains($0) }.shuffled()
    }

    /// Every shelf, in the user's chosen order — any shelf type added in a future update
    /// that isn't in the saved order yet is appended at the end rather than dropped.
    static func order(from raw: String) -> [HomeShelf] {
        let saved = raw.split(separator: ",").compactMap { HomeShelf(rawValue: String($0)) }
        let missing = HomeShelf.allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    static func encode(_ items: [HomeShelf]) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }

    /// Defaults to every shelf active until the user opts to trim the list — a shelf still
    /// only actually shows when it has content (or, for Recently Added, when the server's
    /// reachable at all), same gating as before this was configurable.
    /// A shelf added in an update since the list was saved starts out on: it was never
    /// switched off, only unknown.
    static func active(from raw: String) -> Set<HomeShelf> {
        guard !raw.isEmpty else { return Set(HomeShelf.allCases) }
        let saved = Set(raw.split(separator: ",").compactMap { HomeShelf(rawValue: String($0)) })
        let known = UserDefaults.standard.string(forKey: knownKey)
            .map { Set($0.split(separator: ",").compactMap { HomeShelf(rawValue: String($0)) }) } ?? firstShelves
        return saved.union(HomeShelf.allCases.filter { !known.contains($0) })
    }

    /// Records every current shelf as known alongside, so turning a new one off sticks.
    static func encode(_ items: Set<HomeShelf>) -> String {
        UserDefaults.standard.set(encode(HomeShelf.allCases), forKey: knownKey)
        return items.map(\.rawValue).joined(separator: ",")
    }
}

/// Data for the shelves that need more than MediaRepository, shared by Home on every platform.
@MainActor
enum HomeShelfLoader {
    /// Jellyfin names a recommendation row by why it was picked.
    static func recommendationTitle(_ category: MovieRecommendationCategory) -> String {
        guard let name = category.baselineItemName, !name.isEmpty else { return "Recommended" }
        switch category.recommendationType {
        case "SimilarToRecentlyPlayed": return "Because You Watched \(name)"
        case "SimilarToLikedItem": return "Because You Liked \(name)"
        case "HasDirectorFromRecentlyPlayed", "HasLikedDirector": return "Directed by \(name)"
        case "HasActorFromRecentlyPlayed", "HasLikedActor": return "Starring \(name)"
        default: return "Recommended"
        }
    }

    /// "Popular on …" rows, by streaming service id.
    static func serviceRows(seerrRepo: SeerrRepository, previous: [Int: [SeerrItem]]) async -> [Int: [SeerrItem]] {
        guard seerrRepo.hasCatalog else { return previous }
        let providers = StreamingServicePrefs.decode(UserDefaults.standard.data(forKey: StreamingServicePrefs.key) ?? Data())
        var rows: [Int: [SeerrItem]] = [:]
        await withTaskGroup(of: (Int, [SeerrItem]).self) { group in
            for provider in providers {
                let id = provider.id
                group.addTask { @MainActor in (id, await seerrRepo.popularOn(id)) }
            }
            // An empty answer is far more often a failed request than an empty catalogue; the
            // row keeps what it had rather than disappearing until the next load.
            for await (id, items) in group { rows[id] = items.isEmpty ? previous[id] : items }
        }
        return rows
    }

    /// Requests from the last two months whose title has arrived, newest first.
    static func recentlyAvailable(_ requests: [SeerrRequestItem]) -> [SeerrRequestItem] {
        let cutoff = Date().addingTimeInterval(-60 * 86_400)
        return Array(requests
            .filter { request in
                (request.mediaStatus == .available || request.mediaStatus == .partiallyAvailable)
                    && request.requestedAt > cutoff && request.tmdbId != nil
            }
            .sorted { $0.requestedAt > $1.requestedAt }
            .prefix(12))
    }

    /// Finds each arrived request's title in the library, keeping the request order and
    /// dropping anything already watched. nil when nothing could be looked up.
    static func nowAvailable(_ requests: [SeerrRequestItem], credential: ServerCredential, authHeader: String) async -> [MediaItem]? {
        let client = JellyfinMediaClient()
        var found: [Int: MediaItem] = [:]
        await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, request) in requests.enumerated() {
                guard let tmdbId = request.tmdbId else { continue }
                let isSeries = request.mediaType == .tv
                let title = request.mediaTitle
                group.addTask {
                    (index, try? await client.findItem(credential: credential, authHeader: authHeader,
                                                       tmdbId: tmdbId, isSeries: isSeries, title: title))
                }
            }
            for await (index, item) in group {
                if let item { found[index] = item }
            }
        }
        guard !found.isEmpty else { return nil }
        return found.sorted { $0.key < $1.key }.map(\.value).filter { $0.userData?.played != true }
    }
}
