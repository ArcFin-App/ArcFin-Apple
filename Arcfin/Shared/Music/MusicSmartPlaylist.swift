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

    @MainActor private static var coverCache: [String: [URL]] = [:]

    /// Covers of up to four different albums in it, for its tile; kept while the app runs.
    @MainActor func covers(libraryID: String) async -> [URL] {
        let key = "\(rawValue)|\(libraryID)"
        if let cached = Self.coverCache[key] { return cached }
        var seen = Set<String>()
        let urls = await songs(libraryID: libraryID, limit: 30)
            .filter { seen.insert($0.albumId ?? $0.id).inserted }
            .compactMap { MusicAPI.artworkURL($0, width: 240) }
            .prefix(4)
        Self.coverCache[key] = Array(urls)
        return Array(urls)
    }

    /// Up to 100 songs, fresh each time.
    func songs(libraryID: String, limit: Int = 100) async -> [MusicSong] {
        let (sort, ascending, filter): (MusicSort, Bool, MusicFilter) = switch self {
        case .notPlayedInAWhile: (.datePlayed, true, MusicFilter(playedOnly: true))
        case .favoritesMix: (.random, true, MusicFilter(favoritesOnly: true))
        case .recentlyAdded: (.dateAdded, false, MusicFilter())
        case .neverPlayed: (.random, true, MusicFilter(unplayedOnly: true))
        }
        let page = try? await MusicAPI.call {
            try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: sort,
                                        ascending: ascending, filter: filter, limit: limit)
        }
        return page?.tracks ?? []
    }
}

/// A smart playlist's artwork: four of its covers, or one when it has fewer, tinted toward
/// its colour at the bottom, with its symbol and name over them; the colour alone while the
/// covers load or when it's empty.
struct MusicSmartPlaylistArt<Cover: View>: View {
    let playlist: MusicSmartPlaylist
    let libraryID: String
    var side: CGFloat
    @ViewBuilder let cover: (URL) -> Cover
    @State private var covers: [URL] = []

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: playlist.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if covers.count >= 4 {
                VStack(spacing: 0) {
                    HStack(spacing: 0) { cell(covers[0]); cell(covers[1]) }
                    HStack(spacing: 0) { cell(covers[2]); cell(covers[3]) }
                }
            } else if let first = covers.first {
                cover(first).frame(width: side, height: side).clipped()
            }
            LinearGradient(colors: [.clear, (playlist.colors.last ?? .black).opacity(0.9)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: side * 0.03) {
                Image(systemName: playlist.systemImage)
                    .font(.system(size: side * 0.14, weight: .semibold))
                Text(playlist.title)
                    .font(.system(size: side * 0.1, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .padding(side * 0.08)
        }
        .frame(width: side, height: side)
        .task(id: libraryID) { covers = await playlist.covers(libraryID: libraryID) }
        .accessibilityHidden(true)
    }

    private func cell(_ url: URL) -> some View {
        cover(url).frame(width: side / 2, height: side / 2).clipped()
    }
}
