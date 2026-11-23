// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import JellyfinAPI
import SeerrAPI
@testable import Arcfin

@MainActor
struct PersonCreditsTests {
    private func request(_ title: String, _ type: RequestMediaType, tmdbId: Int?) -> SeerrRequestItem {
        SeerrRequestItem(id: tmdbId ?? 0, mediaTitle: title, mediaType: type, status: .pending,
                         requestedAt: Date(), tmdbId: tmdbId)
    }

    @Test func leavesOutWhatTheLibraryHasOrIsAvailable() {
        let credits = [
            SeerrPersonCredit(id: 1, title: "In Library", mediaType: .movie),
            SeerrPersonCredit(id: 2, title: "Available", mediaType: .movie, mediaStatus: .available),
            SeerrPersonCredit(id: 3, title: "Processing", mediaType: .tv, mediaStatus: .processing),
            SeerrPersonCredit(id: 4, title: "Missing", mediaType: .movie),
        ]
        let library = [MediaItem(id: "a", name: "In Library", type: .movie, tmdbId: 1)]
        let missing = PersonDetailModel.missingCredits(credits, library: library, requests: [])
        #expect(missing.map(\.id) == [4])
    }

    @Test func leavesOutRequestedTitlesMatchedByTmdbIdAndType() {
        let credits = [
            SeerrPersonCredit(id: 10, title: "Requested Movie", mediaType: .movie),
            SeerrPersonCredit(id: 11, title: "Same Id, Other Type", mediaType: .tv),
        ]
        let requests = [request("Something Else", .movie, tmdbId: 10), request("x", .movie, tmdbId: 11)]
        let missing = PersonDetailModel.missingCredits(credits, library: [], requests: requests)
        #expect(missing.map(\.id) == [11])
    }

    @Test func matchesByTitleOnlyForARequestWithoutTmdbId() {
        let credits = [
            SeerrPersonCredit(id: 20, title: "Old Request", mediaType: .movie),
            SeerrPersonCredit(id: 21, title: "Same Title", mediaType: .movie),
        ]
        let requests = [request("Old Request", .movie, tmdbId: nil), request("Same Title", .movie, tmdbId: 99)]
        let missing = PersonDetailModel.missingCredits(credits, library: [], requests: requests)
        #expect(missing.map(\.id) == [21])
    }
}
