// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum BottomNavItem: String, CaseIterable, Identifiable {
    // Case name stays "requests" even though it now displays as "Discover" — the rawValue is
    // persisted in bottomNavOrder/bottomNavActive UserDefaults strings, renaming it would drop
    // the tab from every existing saved layout instead of just relabeling it.
    case home, browse, stats, requests, watchlist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:      "Home"
        case .browse:    "Browse"
        case .stats:     "Stats"
        case .requests:  "Discover"
        case .watchlist: "Watchlist"
        }
    }

    var icon: String {
        switch self {
        case .home:      "house"
        case .browse:    "square.grid.2x2"
        case .stats:     "chart.xyaxis.line"
        case .requests:  "sparkle.magnifyingglass"
        case .watchlist: "bookmark"
        }
    }
}

enum BottomNavPrefs {
    static let maxActive = 5
    static let orderKey = "bottomNavOrder"
    static let activeKey = "bottomNavActive"
    static let launchTabKey = "launchTab"

    /// Every tab, in the user's chosen order — any tab type added in a future update
    /// that isn't in the saved order yet is appended at the end rather than dropped.
    static func order(from raw: String) -> [BottomNavItem] {
        let saved = raw.split(separator: ",").compactMap { BottomNavItem(rawValue: String($0)) }
        let missing = BottomNavItem.allCases.filter { !saved.contains($0) }
        return saved + missing
    }

    static func encode(_ items: [BottomNavItem]) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }

    /// Every tab except Stats until the user chooses; Stats is opt-in, from Navigation
    /// settings (or Appearance on Apple TV).
    static func active(from raw: String) -> Set<BottomNavItem> {
        guard !raw.isEmpty else { return Set(BottomNavItem.allCases).subtracting([.stats]) }
        return Set(raw.split(separator: ",").compactMap { BottomNavItem(rawValue: String($0)) })
    }

    static func encode(_ items: Set<BottomNavItem>) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }
}
