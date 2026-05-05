import Foundation

// Extension-target copy — keep in sync with Arcfin/TopShelf/TopShelfBridge.swift

struct TopShelfMediaItem: Codable {
    let id: String
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let progress: Double
}

enum TopShelfBridge {
    private static let suiteName            = "group.com.psmattas.arcfin"
    private static let continueWatchingKey  = "topShelf.continueWatching"
    private static let recentlyAddedKey     = "topShelf.recentlyAdded"

    static func loadContinueWatching() -> [TopShelfMediaItem] { load(key: continueWatchingKey) }
    static func loadRecentlyAdded()    -> [TopShelfMediaItem] { load(key: recentlyAddedKey) }

    private static func load(key: String) -> [TopShelfMediaItem] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([TopShelfMediaItem].self, from: data)
        else { return [] }
        return items
    }

    static func playURL(for itemID: String) -> URL {
        URL(string: "arcfin://play/\(itemID)")!
    }
}
