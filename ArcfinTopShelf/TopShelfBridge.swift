// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// Extension-target copy — keep in sync with Arcfin/TopShelf/TopShelfBridge.swift

struct TopShelfMediaItem: Codable {
    let id: String
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let progress: Double
    let summary: String?
    let genre: String?
    let duration: TimeInterval?
    let year: Int?
    let backdropURL: URL?
    let contextTitle: String?
    let logoURL: URL?
    let ratingTitle: String?
    let ratingValue: String?
    let artworkFileName: String?
    let artworkHasLogo: Bool?
}

enum TopShelfBridge {
    private static let suiteName            = "group.com.psmattas.Arcfin.shared"
    private static let continueWatchingKey  = "topShelf.continueWatching"
    private static let nextUpKey            = "topShelf.nextUp"
    private static let recentlyAddedKey     = "topShelf.recentlyAdded"
    private static let liveChannelsKey      = "topShelf.liveChannels"

    static func loadContinueWatching() -> [TopShelfMediaItem] { load(key: continueWatchingKey) }
    static func loadNextUp()           -> [TopShelfMediaItem] { load(key: nextUpKey) }
    static func loadRecentlyAdded()    -> [TopShelfMediaItem] { load(key: recentlyAddedKey) }
    static func loadLiveChannels()     -> [TopShelfMediaItem] { load(key: liveChannelsKey) }

    private static func load(key: String) -> [TopShelfMediaItem] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([TopShelfMediaItem].self, from: data)
        else { return [] }
        return items
    }

    static func artworkURL(for item: TopShelfMediaItem) -> URL? {
        guard let name = item.artworkFileName else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("TopShelfArtwork", isDirectory: true)
            .appendingPathComponent(name)
    }

    static func playURL(for itemID: String) -> URL {
        URL(string: "arcfin://play/\(itemID)")!
    }
}
