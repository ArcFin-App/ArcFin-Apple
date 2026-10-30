// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

enum LibraryNavTarget: Hashable {
    case playlist(MediaItem)     // a playlist in the Playlists library — opens its titles
    case media(MediaItem)
    case collection(MediaItem)   // BoxSet item — routed to collection detail
}

enum LibraryWatchedFilter: String, CaseIterable, Identifiable {
    case all = "All", unwatched = "Unwatched", watched = "Watched"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .unwatched: String(localized: "Unwatched")
        case .watched: String(localized: "Watched")
        }
    }
}

/// Filters beyond genre/year/watched/favorites: content rating and a minimum community
/// score, kept as one value so it travels through the filter sheet as a single binding.
struct LibraryExtraFilters: Equatable {
    var officialRatings: Set<String> = []
    var minRating: Double?
    /// Jellyfin's `Genres` filter is "any of"; this narrows to titles carrying every selected genre.
    var matchAllGenres = false
    var tags: Set<String> = []
    var quality: LibraryQualityFilter = .any
    var hasSubtitles = false

    var isActive: Bool {
        !officialRatings.isEmpty || minRating != nil || !tags.isEmpty || quality != .any || hasSubtitles
    }

    private static let maturityOrder = [
        "G", "TV-Y", "TV-G", "TV-Y7", "PG", "TV-PG", "PG-13", "TV-14", "R", "TV-MA", "NC-17",
    ]

    /// Least to most mature; ratings outside the known scale sort last by name.
    static func ordered(_ ratings: [String]) -> [String] {
        ratings.sorted { lhs, rhs in
            let l = maturityOrder.firstIndex(of: lhs) ?? .max
            let r = maturityOrder.firstIndex(of: rhs) ?? .max
            return l == r ? lhs < rhs : l < r
        }
    }

    /// Slider position for a selection: `ordered.count` means no limit.
    static func ratingStep(_ selected: Set<String>, in ordered: [String]) -> Int {
        ordered.lastIndex { selected.contains($0) } ?? ordered.count
    }

    static func ratings(upToStep step: Int, in ordered: [String]) -> Set<String> {
        step >= ordered.count ? [] : Set(ordered.prefix(step + 1))
    }
}

enum LibraryQualityFilter: String, CaseIterable, Identifiable {
    case any = "Any", hd = "HD", uhd = "4K"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: String(localized: "Any")
        case .hd: String(localized: "HD")
        case .uhd: String(localized: "4K")
        }
    }
}

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case nameAsc = "Name (A–Z)"
    case nameDesc = "Name (Z–A)"
    case dateAddedDesc = "Recently Added"
    case releaseDateDesc = "Release Date (Newest)"
    case releaseDateAsc = "Release Date (Oldest)"
    case ratingDesc = "Rating (Highest)"
    case genreAsc = "Genre"
    /// The order the playlist was put together in; only offered for playlists.
    case playlistOrder = "Playlist Order"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nameAsc: String(localized: "Name (A–Z)")
        case .nameDesc: String(localized: "Name (Z–A)")
        case .dateAddedDesc: String(localized: "Recently Added")
        case .releaseDateDesc: String(localized: "Release Date (Newest)")
        case .releaseDateAsc: String(localized: "Release Date (Oldest)")
        case .ratingDesc: String(localized: "Rating (Highest)")
        case .genreAsc: String(localized: "Genre")
        case .playlistOrder: String(localized: "Playlist Order")
        }
    }

    static let standard = allCases.filter { $0 != .playlistOrder }

    var sortBy: String {
        switch self {
        case .nameAsc, .nameDesc: return "SortName"
        case .dateAddedDesc: return "DateCreated"
        case .releaseDateDesc, .releaseDateAsc: return "PremiereDate"
        case .ratingDesc: return "CommunityRating"
        case .genreAsc: return "Genres"
        case .playlistOrder: return "SortName"
        }
    }

    var sortOrder: String {
        switch self {
        case .nameAsc, .releaseDateAsc: return "Ascending"
        case .nameDesc, .dateAddedDesc, .releaseDateDesc, .ratingDesc: return "Descending"
        case .genreAsc, .playlistOrder: return "Ascending"
        }
    }
}

enum LibraryGridDensity: String, CaseIterable, Identifiable {
    case compact, normal, comfortable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .normal: return String(localized: "Normal")
        case .comfortable: return String(localized: "Comfortable")
        }
    }

    var systemIcon: String {
        switch self {
        case .compact: return "square.grid.4x3.fill"
        case .normal: return "square.grid.3x2.fill"
        case .comfortable: return "square.grid.2x2.fill"
        }
    }

    var columnCount: Int {
        switch self {
        case .compact: return 5
        case .normal: return 3
        case .comfortable: return 2
        }
    }

    /// Minimum poster width for the adaptive grid (macOS and iPad) — a fixed column
    /// count doesn't reflow as the window resizes or leaves iPad's much larger screen
    /// with absurdly wide cards, so density instead sets how small a card can get
    /// before another column joins.
    var adaptiveMinimumWidth: CGFloat {
        switch self {
        case .compact: return 110
        case .normal: return 140
        case .comfortable: return 180
        }
    }
}
