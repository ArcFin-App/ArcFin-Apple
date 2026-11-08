// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Testing
@testable import Arcfin

struct HomeShelfPrefsTests {
    private let order: [HomeShelf] = [.continueWatching, .seerrTrending, .nextUp, .streamingServices, .favorites]

    @Test func moveSkipsShelvesThatAreHidden() {
        let shown: [HomeShelf] = [.continueWatching, .nextUp, .favorites]
        let reordered = HomeShelfPrefs.reorder(order, shown: shown) { $0.move(fromOffsets: [2], toOffset: 0) }
        #expect(reordered == [.favorites, .seerrTrending, .continueWatching, .streamingServices, .nextUp])
    }

    @Test func swapKeepsHiddenShelvesInPlace() {
        let shown: [HomeShelf] = [.continueWatching, .nextUp, .favorites]
        let reordered = HomeShelfPrefs.reorder(order, shown: shown) { $0.swapAt(0, 1) }
        #expect(reordered == [.nextUp, .seerrTrending, .continueWatching, .streamingServices, .favorites])
    }

    @Test func catalogueShelvesNeedSeerrOrTMDB() {
        #expect(!HomeShelf.streamingServices.isOffered(seerrConfigured: false, hasCatalog: false))
        #expect(HomeShelf.streamingServices.isOffered(seerrConfigured: false, hasCatalog: true))
        #expect(!HomeShelf.seerrWatchlist.isOffered(seerrConfigured: false, hasCatalog: true))
        #expect(HomeShelf.favorites.isOffered(seerrConfigured: false, hasCatalog: false))
    }
}
