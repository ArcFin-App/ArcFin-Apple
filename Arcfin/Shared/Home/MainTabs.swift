// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum MainTabs {
    /// The tabs the user has turned on, in their order, up to `limit`. Requests and Watchlist
    /// need Seerr; Admin an admin profile.
    static func visible(orderString: String, activeString: String, seerrConfigured: Bool,
                        isAdmin: Bool, limit: Int) -> [BottomNavItem] {
        let order = BottomNavPrefs.order(from: orderString)
        let active = BottomNavPrefs.active(from: activeString)
        return Array(order.filter { tab in
            guard active.contains(tab) else { return false }
            if tab == .requests || tab == .watchlist { return seerrConfigured }
            if tab == .admin { return isAdmin }
            return true
        }.prefix(limit))
    }
}
