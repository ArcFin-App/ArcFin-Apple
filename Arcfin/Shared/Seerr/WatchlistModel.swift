// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SeerrAPI

/// Loading and removing from the Seerr watchlist, shared by every platform's `WatchlistView`.
@MainActor @Observable
final class WatchlistModel {
    private(set) var isLoading = false
    var error: String?

    func load(seerrRepo: SeerrRepository) async {
        isLoading = true
        await seerrRepo.loadWatchlist()
        isLoading = false
    }

    func remove(_ item: SeerrItem, seerrRepo: SeerrRepository) {
        HapticManager.impact(.light)
        Task {
            do {
                try await seerrRepo.removeFromWatchlist(item)
            } catch where SeerrRepository.isCancellation(error) {
            } catch {
                self.error = String(localized: "Couldn't remove this from your watchlist. Check your connection and try again.")
            }
        }
    }
}
