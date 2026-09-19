import Foundation

enum BottomNavItem: String, CaseIterable, Identifiable {
    case home, browse, stats, requests, watchlist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:      "Home"
        case .browse:    "Browse"
        case .stats:     "Stats"
        case .requests:  "Requests"
        case .watchlist: "Watchlist"
        }
    }

    var icon: String {
        switch self {
        case .home:      "house"
        case .browse:    "square.grid.2x2"
        case .stats:     "chart.xyaxis.line"
        case .requests:  "clock"
        case .watchlist: "bookmark"
        }
    }
}

enum BottomNavPrefs {
    static let maxActive = 5
    static let orderKey = "bottomNavOrder"
    static let activeKey = "bottomNavActive"

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

    /// Defaults to every tab active except Stats (a niche, plugin-dependent screen most
    /// users won't have configured — visible via Bottom Navigation settings if wanted)
    /// until the user opts to trim the list themselves.
    static func active(from raw: String) -> Set<BottomNavItem> {
        guard !raw.isEmpty else { return Set(BottomNavItem.allCases).subtracting([.stats]) }
        return Set(raw.split(separator: ",").compactMap { BottomNavItem(rawValue: String($0)) })
    }

    static func encode(_ items: Set<BottomNavItem>) -> String {
        items.map(\.rawValue).joined(separator: ",")
    }
}
