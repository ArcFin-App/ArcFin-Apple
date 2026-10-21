// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum HomeShelf: String, CaseIterable, Identifiable {
    case continueWatching, nextUp, recentlyAddedMovies, recentlyAddedShows
    case recentlyReleasedMovies, recentlyAiredEpisodes, watchAgain, genreShelves
    case seerrWatchlist, seerrTrending, seerrPopularMovies, seerrPopularSeries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueWatching:       "Continue Watching"
        case .nextUp:                 "Next Up"
        case .recentlyAddedMovies:    "Recently Added Movies"
        case .recentlyAddedShows:     "Recently Added Shows"
        case .recentlyReleasedMovies: "Recently Released Movies"
        case .recentlyAiredEpisodes:  "Recently Aired Episodes"
        case .watchAgain:             "Watch Again"
        case .genreShelves:           "Genre Picks"
        case .seerrWatchlist:         "Watchlist"
        case .seerrTrending:          "Trending"
        case .seerrPopularMovies:     "Popular Movies"
        case .seerrPopularSeries:     "Popular Series"
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
    static func active(from raw: String) -> Set<HomeShelf> {
        guard !raw.isEmpty else { return Set(HomeShelf.allCases) }
        return Set(raw.split(separator: ",").compactMap { HomeShelf(rawValue: String($0)) })
    }

    static func encode(_ items: Set<HomeShelf>) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }
}
