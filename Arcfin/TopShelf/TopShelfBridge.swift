// SPDX-License-Identifier: AGPL-3.0-or-later

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
    private static let recentlyAddedKey    = "topShelf.recentlyAdded"

    public static func save(
        continueWatching: some Collection<TopShelfMediaItem>,
        recentlyAdded: some Collection<TopShelfMediaItem>
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(Array(continueWatching.prefix(5))) {
            defaults.set(data, forKey: continueWatchingKey)
        }
        if let data = try? JSONEncoder().encode(Array(recentlyAdded.prefix(3))) {
            defaults.set(data, forKey: recentlyAddedKey)
        }
        defaults.synchronize()
    }

    public static func loadContinueWatching() -> [TopShelfMediaItem] {
        load(key: continueWatchingKey)
    }

    public static func loadRecentlyAdded() -> [TopShelfMediaItem] {
        load(key: recentlyAddedKey)
    }

    private static func load(key: String) -> [TopShelfMediaItem] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([TopShelfMediaItem].self, from: data)
        else { return [] }
        return items
    }

    public static func playURL(for itemID: String) -> URL {
        URL(string: "arcfin://play/\(itemID)")!
    }
}
