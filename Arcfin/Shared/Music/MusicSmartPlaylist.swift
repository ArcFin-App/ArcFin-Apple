// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Playlists Arcfin makes from the library's play counts, favourites and dates.
enum MusicSmartPlaylist: String, CaseIterable, Hashable, Identifiable {
    case notPlayedInAWhile, favoritesMix, recentlyAdded, neverPlayed

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .notPlayedInAWhile: "Not Played in a While"
        case .favoritesMix: "Favorites Mix"
        case .recentlyAdded: "Recently Added Songs"
        case .neverPlayed: "Never Played"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .notPlayedInAWhile: "Songs you played, longest ago first"
        case .favoritesMix: "Your favorite songs, shuffled"
        case .recentlyAdded: "The newest songs in your library"
        case .neverPlayed: "Songs you haven't played yet"
        }
    }

    var systemImage: String {
        switch self {
        case .notPlayedInAWhile: "clock.arrow.circlepath"
        case .favoritesMix: "star.fill"
        case .recentlyAdded: "sparkles"
        case .neverPlayed: "music.note"
        }
    }

    var colors: [Color] {
        switch self {
        case .notPlayedInAWhile: [DT.Color.palette("60A5FA"), DT.Color.palette("1D4ED8")]
        case .favoritesMix: [DT.Color.accent, DT.Color.palette("B83A25")]
        case .recentlyAdded: [DT.Color.palette("10B981"), DT.Color.palette("047857")]
        case .neverPlayed: [DT.Color.palette("F59E0B"), DT.Color.palette("B45309")]
        }
    }

    /// Up to 100 songs, fresh each time.
    func songs(libraryID: String) async -> [MusicSong] {
        let (sort, ascending, filter): (MusicSort, Bool, MusicFilter) = switch self {
        case .notPlayedInAWhile: (.datePlayed, true, MusicFilter(playedOnly: true))
        case .favoritesMix: (.random, true, MusicFilter(favoritesOnly: true))
        case .recentlyAdded: (.dateAdded, false, MusicFilter())
        case .neverPlayed: (.random, true, MusicFilter(unplayedOnly: true))
        }
        let page = try? await MusicAPI.call {
            try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: sort,
                                        ascending: ascending, filter: filter, limit: 100)
        }
        return page?.tracks ?? []
    }
}
