import Foundation

// Copy of the bridge for the ArcfinTopShelf extension target.
// The main app target has its own copy at Arcfin/TopShelf/TopShelfBridge.swift.
// Keep both in sync.

struct TopShelfMediaItem: Codable {
    let id: String
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let progress: Double
}

enum TopShelfBridge {
    private static let suiteName = "group.com.psmattas.arcfin"
    private static let continueWatchingKey = "topShelf.continueWatching"

    static func save(continueWatching items: [TopShelfMediaItem]) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(Array(items.prefix(10))) else { return }
        defaults.set(data, forKey: continueWatchingKey)
        defaults.synchronize()
    }

    static func loadContinueWatching() -> [TopShelfMediaItem] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: continueWatchingKey),
              let items = try? JSONDecoder().decode([TopShelfMediaItem].self, from: data)
        else { return [] }
        return items
    }

    static func playURL(for itemID: String) -> URL {
        URL(string: "arcfin://play/\(itemID)")!
    }
}
