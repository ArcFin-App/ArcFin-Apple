// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SeerrAPI
import JellyfinAPI

/// Discover's movies-or-series choice, genre and search results and the titles popular in the
/// device's language, shared by every platform's `SeerrView`.
@MainActor @Observable
final class SeerrDiscoverModel {
    var mediaType: RequestMediaType = .movie
    var selectedGenre: SeerrGenre?
    private(set) var genreResults: [SeerrItem] = []
    private(set) var isLoadingGenre = false
    private(set) var searchResults: [SeerrItem] = []
    private(set) var isSearching = false
    private var searchTask: Task<Void, Never>?
    /// Popular titles first made in this device's language, when it isn't English.
    private(set) var languageItems: [SeerrItem] = []
    /// Popular on each service picked in Popular Elsewhere, in that order.
    private(set) var serviceRows: [DiscoverRow] = []
    /// A few genres, picked at random on each load so Discover doesn't always show the same.
    private(set) var genreRows: [DiscoverRow] = []
    /// Titles like the one most recently finished in the library.
    private(set) var becauseYouWatched: DiscoverRow?

    struct DiscoverRow: Identifiable {
        let id: String
        let title: String
        let items: [SeerrItem]
    }

    private static let genreRowCount = 4

    func genres(in seerrRepo: SeerrRepository) -> [SeerrGenre] {
        mediaType == .tv ? seerrRepo.tvGenres : seerrRepo.movieGenres
    }

    func trending(in seerrRepo: SeerrRepository) -> [SeerrItem] {
        let trending = seerrRepo.trending.filter { $0.mediaType == mediaType }
        // Seerr can fail trending on its own (500 when its TMDB request fails); popular
        // titles stand in rather than an empty page.
        return trending.isEmpty ? popular(in: seerrRepo) : trending
    }

    func showsTrending(in seerrRepo: SeerrRepository) -> Bool {
        seerrRepo.trending.contains { $0.mediaType == mediaType }
    }

    func upcoming(in seerrRepo: SeerrRepository) -> [SeerrItem] {
        mediaType == .tv ? seerrRepo.upcomingTV : seerrRepo.upcomingMovies
    }

    func popular(in seerrRepo: SeerrRepository) -> [SeerrItem] {
        mediaType == .tv ? seerrRepo.popularTV : seerrRepo.popularMovies
    }

    var deviceLanguage: String? {
        guard let code = Locale.current.language.languageCode?.identifier, code != "en" else { return nil }
        return code
    }

    var languageName: String? {
        deviceLanguage.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
    }

    func load(seerrRepo: SeerrRepository) async {
        // Refetches live every time this appears, but loadDiscover() only flips the
        // loading flag (and so only shows a skeleton) when there's truly nothing cached
        // yet — otherwise this updates the already-visible list in place.
        async let discover: Void = seerrRepo.loadDiscover()
        async let genres: Void = seerrRepo.loadGenres()
        async let upcoming: Void = seerrRepo.loadUpcoming()
        // The bookmarks on every card read it.
        async let watchlist: Void = seerrRepo.loadWatchlist()
        _ = await (discover, genres, upcoming, watchlist)
    }

    func refresh(seerrRepo: SeerrRepository) async {
        async let discover: Void = seerrRepo.loadDiscover()
        async let upcoming: Void = seerrRepo.loadUpcoming()
        async let watchlist: Void = seerrRepo.loadWatchlist()
        _ = await (discover, upcoming, watchlist)
        await loadLanguageItems(seerrRepo: seerrRepo)
    }

    func loadLanguageItems(seerrRepo: SeerrRepository) async {
        guard let deviceLanguage else { return }
        languageItems = await seerrRepo.discoverByLanguage(deviceLanguage, mediaType: mediaType)
    }

    /// The rows beyond Seerr's own lists, all for the current choice of movies or series.
    func loadMoreRows(seerrRepo: SeerrRepository, mediaRepo: MediaRepository, services: [SeerrWatchProvider]) async {
        guard seerrRepo.hasCatalog else {
            serviceRows = []; genreRows = []; becauseYouWatched = nil
            return
        }
        let type = mediaType
        async let services = loadServiceRows(services, type: type, seerrRepo: seerrRepo)
        async let genres = loadGenreRows(genres(in: seerrRepo), type: type, seerrRepo: seerrRepo)
        async let watched = loadBecauseYouWatched(type: type, seerrRepo: seerrRepo, mediaRepo: mediaRepo)
        let (s, g, w) = await (services, genres, watched)
        // A switch to the other type while loading starts its own load.
        guard type == mediaType else { return }
        serviceRows = s; genreRows = g; becauseYouWatched = w
    }

    private func loadServiceRows(_ services: [SeerrWatchProvider], type: RequestMediaType, seerrRepo: SeerrRepository) async -> [DiscoverRow] {
        await withTaskGroup(of: (Int, DiscoverRow?).self) { group in
            for (index, provider) in services.enumerated() {
                group.addTask {
                    let items = await seerrRepo.popularOn(provider.id).filter { $0.mediaType == type }
                    let row = items.isEmpty ? nil
                        : DiscoverRow(id: "service-\(provider.id)", title: String(localized: "Popular on \(provider.name)"), items: items)
                    return (index, row)
                }
            }
            var rows: [(Int, DiscoverRow)] = []
            for await (index, row) in group { if let row { rows.append((index, row)) } }
            return rows.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func loadGenreRows(_ genres: [SeerrGenre], type: RequestMediaType, seerrRepo: SeerrRepository) async -> [DiscoverRow] {
        let picked = Array(genres.shuffled().prefix(Self.genreRowCount))
        return await withTaskGroup(of: (Int, DiscoverRow?).self) { group in
            for (index, genre) in picked.enumerated() {
                group.addTask {
                    let items = await seerrRepo.discoverByGenre(genre.id, mediaType: type)
                    return (index, items.isEmpty ? nil : DiscoverRow(id: "genre-\(genre.id)", title: genre.name, items: items))
                }
            }
            var rows: [(Int, DiscoverRow)] = []
            for await (index, row) in group { if let row { rows.append((index, row)) } }
            return rows.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Seeded from the latest finished movie or series that TMDB knows; only titles not in the
    /// library, since those are the ones Discover can do something with.
    private func loadBecauseYouWatched(type: RequestMediaType, seerrRepo: SeerrRepository, mediaRepo: MediaRepository) async -> DiscoverRow? {
        let wanted: MediaType = type == .tv ? .series : .movie
        guard let source = mediaRepo.watchAgain.first(where: { $0.type == wanted && $0.tmdbId != nil }),
              let tmdbId = source.tmdbId else { return nil }
        let items = await seerrRepo.relatedMedia(mediaType: type, mediaId: tmdbId)
            .filter { $0.mediaType == type && !mediaRepo.hasInLibrary($0) }
        guard !items.isEmpty else { return nil }
        return DiscoverRow(id: "watched-\(source.id)", title: String(localized: "Because You Watched \(source.name)"), items: items)
    }

    /// A new choice of movies or series starts again from All.
    func mediaTypeChanged() {
        selectedGenre = nil
        genreResults = []
    }

    func loadGenreResults(_ genre: SeerrGenre?, seerrRepo: SeerrRepository) {
        guard let genre else { genreResults = []; return }
        isLoadingGenre = true
        genreResults = []
        Task {
            genreResults = await seerrRepo.discoverByGenre(genre.id, mediaType: mediaType)
            isLoadingGenre = false
        }
    }

    /// Debounced, and a response for an older query never replaces a newer one's results.
    func search(_ query: String, seerrRepo: SeerrRepository) {
        searchTask?.cancel()
        guard !query.isEmpty else { searchResults = []; isSearching = false; return }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let results = await seerrRepo.search(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
        }
    }

    func toggleWatchlist(_ item: SeerrItem, seerrRepo: SeerrRepository) {
        HapticManager.impact(.light)
        Task {
            if seerrRepo.isInWatchlist(item) {
                try? await seerrRepo.removeFromWatchlist(item)
            } else {
                try? await seerrRepo.addToWatchlist(item)
            }
        }
    }
}
