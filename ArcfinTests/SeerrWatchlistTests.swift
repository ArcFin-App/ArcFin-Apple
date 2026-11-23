// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
import SeerrAPI

struct SeerrWatchlistTests {
    @Test func aFailedLookupKeepsItsTitleInTheList() {
        let movie = SeerrItem.watchlistPlaceholder(tmdbId: 603, mediaType: "movie")
        #expect(movie?.id == 603)
        #expect(movie?.mediaType == .movie)
        #expect(movie?.title == "Unknown")
        #expect(SeerrItem.watchlistPlaceholder(tmdbId: 1399, mediaType: "tv")?.mediaType == .tv)
        #expect(SeerrItem.watchlistPlaceholder(tmdbId: 1, mediaType: nil)?.mediaType == .movie)
    }

    @Test func anEntryWithoutTmdbIdHasNoPlaceholder() {
        #expect(SeerrItem.watchlistPlaceholder(tmdbId: nil, mediaType: "movie") == nil)
    }
}
