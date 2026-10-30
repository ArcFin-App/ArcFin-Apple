// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SeerrAPI

/// Loading and removing from the Seerr watchlist, shared by every platform's `WatchlistView`.
@MainActor @Observable
final class WatchlistModel {
    private(set) var isLoading = false

    func load(seerrRepo: SeerrRepository) async {
        isLoading = true
        await seerrRepo.loadWatchlist()
        isLoading = false
    }

    func remove(_ item: SeerrItem, seerrRepo: SeerrRepository) {
        HapticManager.impact(.light)
        Task { try? await seerrRepo.removeFromWatchlist(item) }
    }
}
