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
        #expect(!HomeShelf.streamingServices.isOffered(seerrConfigured: false, hasCatalog: false, hasLiveTV: false))
        #expect(HomeShelf.streamingServices.isOffered(seerrConfigured: false, hasCatalog: true, hasLiveTV: false))
        #expect(!HomeShelf.seerrWatchlist.isOffered(seerrConfigured: false, hasCatalog: true, hasLiveTV: false))
        #expect(HomeShelf.favorites.isOffered(seerrConfigured: false, hasCatalog: false, hasLiveTV: false))
    }

    @Test func liveTVShelvesNeedLiveTV() {
        for shelf in [HomeShelf.liveFavoriteChannels, .liveOnNow, .liveRecentChannels] {
            #expect(!shelf.isOffered(seerrConfigured: true, hasCatalog: true, hasLiveTV: false))
            #expect(shelf.isOffered(seerrConfigured: false, hasCatalog: false, hasLiveTV: true))
        }
    }

    @Test func liveTVShelvesStartOff() {
        let fresh = HomeShelfPrefs.active(from: "")
        #expect(fresh.isDisjoint(with: HomeShelfPrefs.offByDefault))
        #expect(fresh.contains(.continueWatching))
        // A list saved before the Live TV shelves existed doesn't turn them on either.
        let known = UserDefaults.standard.string(forKey: HomeShelfPrefs.knownKey)
        defer { UserDefaults.standard.set(known, forKey: HomeShelfPrefs.knownKey) }
        UserDefaults.standard.set("continueWatching,nextUp,favorites", forKey: HomeShelfPrefs.knownKey)
        let updated = HomeShelfPrefs.active(from: "continueWatching,favorites")
        #expect(updated.isDisjoint(with: HomeShelfPrefs.offByDefault))
        #expect(updated.contains(.watchAgain))
    }
}
