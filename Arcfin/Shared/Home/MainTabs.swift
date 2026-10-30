// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum MainTabs {
    /// The tabs the user has turned on, in their order. Requests and Watchlist need Seerr.
    static func visible(orderString: String, activeString: String, seerrConfigured: Bool) -> [BottomNavItem] {
        let order = BottomNavPrefs.order(from: orderString)
        let active = BottomNavPrefs.active(from: activeString)
        return order.filter { tab in
            guard active.contains(tab) else { return false }
            if tab == .requests || tab == .watchlist { return seerrConfigured }
            return true
        }
    }
}
