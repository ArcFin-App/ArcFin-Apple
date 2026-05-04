import Foundation

// Shared between the main app target and ArcfinTopShelf extension target.
// Add this file to BOTH targets in Xcode's file inspector.

public struct TopShelfMediaItem: Codable {
    public let id: String
    public let title: String
    public let subtitle: String?    // e.g. "S1 E4 · Episode Title"
    public let imageURL: URL?       // backdrop/landscape 16:9 preferred
    public let progress: Double     // 0.0 – 1.0

    public init(id: String, title: String, subtitle: String?, imageURL: URL?, progress: Double) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.progress = progress
    }
}

public enum TopShelfBridge {
    private static let suiteName = "group.com.psmattas.arcfin"
    private static let continueWatchingKey = "topShelf.continueWatching"

    /// Called from the main app whenever Continue Watching changes.
    public static func save(continueWatching items: [TopShelfMediaItem]) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(Array(items.prefix(10))) else { return }
        defaults.set(data, forKey: continueWatchingKey)
        defaults.synchronize()
    }

    /// Called from the Top Shelf extension.
    public static func loadContinueWatching() -> [TopShelfMediaItem] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: continueWatchingKey),
              let items = try? JSONDecoder().decode([TopShelfMediaItem].self, from: data)
        else { return [] }
        return items
    }

    /// Deep link URL the extension hands to tvOS for a given item.
    public static func playURL(for itemID: String) -> URL {
        URL(string: "arcfin://play/\(itemID)")!
    }
}
