// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// Shared between the main app target and ArcfinTopShelf extension target.
// Add this file to BOTH targets in Xcode's file inspector.

public struct TopShelfMediaItem: Codable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?    // e.g. "S1 E4 · Episode Title"
    public let imageURL: URL?       // backdrop/landscape 16:9 preferred
    public let progress: Double     // 0.0 – 1.0
    public let summary: String?
    public let genre: String?
    public let duration: TimeInterval?  // seconds
    public let year: Int?
    public let backdropURL: URL?        // 1920-wide 16:9 for the carousel
    public let contextTitle: String?    // why it is shown, already localized
    public let logoURL: URL?
    public let ratingTitle: String?     // already localized
    public let ratingValue: String?
    public var artworkFileName: String? // image with the logo and progress bar drawn in
    public var artworkHasLogo: Bool?

    public init(
        id: String, title: String, subtitle: String?, imageURL: URL?, progress: Double,
        summary: String? = nil, genre: String? = nil, duration: TimeInterval? = nil,
        year: Int? = nil, backdropURL: URL? = nil, contextTitle: String? = nil,
        logoURL: URL? = nil, ratingTitle: String? = nil, ratingValue: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.progress = progress
        self.summary = summary
        self.genre = genre
        self.duration = duration
        self.year = year
        self.backdropURL = backdropURL
        self.contextTitle = contextTitle
        self.logoURL = logoURL
        self.ratingTitle = ratingTitle
        self.ratingValue = ratingValue
    }
}

public enum TopShelfBridge {
    private static let suiteName = "group.com.psmattas.Arcfin.shared"
    private static let continueWatchingKey = "topShelf.continueWatching"
    private static let nextUpKey           = "topShelf.nextUp"
    private static let recentlyAddedKey    = "topShelf.recentlyAdded"
    private static let liveChannelsKey     = "topShelf.liveChannels"

    public static var artworkDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)?
            .appendingPathComponent("TopShelfArtwork", isDirectory: true)
    }

    public static func save(
        continueWatching: some Collection<TopShelfMediaItem>,
        nextUp: some Collection<TopShelfMediaItem>,
        recentlyAdded: some Collection<TopShelfMediaItem>,
        liveChannels: [TopShelfMediaItem] = []
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let data = try? JSONEncoder().encode(Array(continueWatching.prefix(5))) {
            defaults.set(data, forKey: continueWatchingKey)
        }
        if let data = try? JSONEncoder().encode(Array(nextUp.prefix(3))) {
            defaults.set(data, forKey: nextUpKey)
        }
        if let data = try? JSONEncoder().encode(Array(recentlyAdded.prefix(3))) {
            defaults.set(data, forKey: recentlyAddedKey)
        }
        if let data = try? JSONEncoder().encode(Array(liveChannels.prefix(3))) {
            defaults.set(data, forKey: liveChannelsKey)
        }
        defaults.synchronize()
    }

    /// Nobody signed in, or another profile now: the shelf shouldn't show the last one's titles.
    public static func clear() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        for key in [continueWatchingKey, nextUpKey, recentlyAddedKey, liveChannelsKey] {
            defaults.removeObject(forKey: key)
        }
    }

    public static func loadContinueWatching() -> [TopShelfMediaItem] {
        load(key: continueWatchingKey)
    }

    public static func loadNextUp() -> [TopShelfMediaItem] {
        load(key: nextUpKey)
    }

    public static func loadRecentlyAdded() -> [TopShelfMediaItem] {
        load(key: recentlyAddedKey)
    }

    public static func loadLiveChannels() -> [TopShelfMediaItem] {
        load(key: liveChannelsKey)
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
