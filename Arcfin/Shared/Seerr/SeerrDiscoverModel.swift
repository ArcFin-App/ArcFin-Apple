// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SeerrAPI

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
