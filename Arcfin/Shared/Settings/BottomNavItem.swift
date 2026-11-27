// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum BottomNavItem: String, CaseIterable, Identifiable {
    // Case name stays "requests" even though it now displays as "Discover" — the rawValue is
    // persisted in bottomNavOrder/bottomNavActive UserDefaults strings, renaming it would drop
    // the tab from every existing saved layout instead of just relabeling it.
    case home, browse, arcs, stats, requests, watchlist, admin

    var id: String { rawValue }

    /// The tabs this platform has: Arcs is only on iPhone and iPad.
    static var available: [BottomNavItem] {
        allCases.filter { $0 != .arcs || PlatformMetrics.hasArcs }
    }

    var title: String {
        switch self {
        case .home:      String(localized: "Home")
        case .browse:    String(localized: "Browse")
        case .arcs:      String(localized: "Arcs")
        case .stats:     String(localized: "Stats")
        case .requests:  String(localized: "Discover")
        case .watchlist: String(localized: "Watchlist")
        case .admin:     String(localized: "Admin")
        }
    }

    var icon: String {
        switch self {
        case .home:      "house"
        case .browse:    "square.grid.2x2"
        case .arcs:      "play.square.stack"
        case .stats:     "chart.xyaxis.line"
        case .requests:  "sparkle.magnifyingglass"
        case .watchlist: "bookmark"
        case .admin:     "server.rack"
        }
    }
}

enum BottomNavPrefs {
    /// iPhone's tab bar shows five; a sixth would fold into a "More" tab. iPad and the Mac
    /// have room for all six.
    static let maxActiveCompact = 5
    static let maxActiveRegular = 6
    static let orderKey = "bottomNavOrder"
    static let activeKey = "bottomNavActive"
    static let launchTabKey = "launchTab"

    /// Every tab, in the user's chosen order — any tab type added in a future update
    /// that isn't in the saved order yet is appended at the end rather than dropped.
    static func order(from raw: String) -> [BottomNavItem] {
        let saved = raw.split(separator: ",").compactMap { BottomNavItem(rawValue: String($0)) }.filter(BottomNavItem.available.contains)
        let missing = BottomNavItem.available.filter { !saved.contains($0) }
        return saved + missing
    }

    static func encode(_ items: [BottomNavItem]) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }

    /// Every tab except Stats and Admin until the user chooses; both are opt-in, from
    /// Navigation settings (or Appearance on Apple TV, which has no Admin).
    static func active(from raw: String) -> Set<BottomNavItem> {
        guard !raw.isEmpty else { return Set(BottomNavItem.available).subtracting([.stats, .admin]) }
        return Set(raw.split(separator: ",").compactMap { BottomNavItem(rawValue: String($0)) })
    }

    static func encode(_ items: Set<BottomNavItem>) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }
}

extension BottomNavPrefs {
    /// The profile whose tab layout the keys above hold.
    private static let layoutProfileKey = "bottomNavProfile"
    private static func storeKey(_ profile: String) -> String { "bottomNavLayout.\(profile)" }
    private static var layoutKeys: [String] { [orderKey, activeKey, launchTabKey] }

    /// Each profile keeps its own tabs: the layout in use is put away under the profile it
    /// belonged to, and the new profile's comes back, or the defaults if it has none yet.
    static func switchLayout(toProfile profile: String) {
        let defaults = UserDefaults.standard
        let current = defaults.string(forKey: layoutProfileKey)
        defaults.set(profile, forKey: layoutProfileKey)
        // The first time, the layout already there is this profile's.
        guard let current, current != profile else { return }
        var saved: [String: String] = [:]
        for key in layoutKeys { saved[key] = defaults.string(forKey: key) }
        defaults.set(saved, forKey: storeKey(current))
        let restored = defaults.dictionary(forKey: storeKey(profile)) as? [String: String] ?? [:]
        for key in layoutKeys {
            if let value = restored[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }
}
