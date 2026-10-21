// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What the Home Screen / Lock Screen widgets show, written by the app and read by the widget
/// extension through the shared App Group container. The extension has no credentials or
/// network stack of its own, so the app hands it a ready-made snapshot — text plus small
/// poster files already on disk — instead of the extension fetching anything itself.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        /// Season/episode code ("S2 · E5") for episodes, the year for everything else.
        public var subtitle: String?
        /// The episode's own title; nil for movies.
        public var detail: String?
        /// 0...1 watched fraction.
        public var progress: Double
        /// File name inside the store's poster directory, nil when no image could be saved.
        public var posterFileName: String?

        public init(
            id: String, title: String, subtitle: String?, detail: String? = nil,
            progress: Double, posterFileName: String?
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.detail = detail
            self.progress = progress
            self.posterFileName = posterFileName
        }
    }

    /// Continue Watching, then Up Next.
    public var items: [Item]
    /// Newest titles in the library, for the Recently Added widget. Optional so a snapshot
    /// written before this existed still decodes.
    public var recentlyAdded: [Item]?
    public var updatedAt: Date

    public init(items: [Item], recentlyAdded: [Item] = [], updatedAt: Date = Date()) {
        self.items = items
        self.recentlyAdded = recentlyAdded
        self.updatedAt = updatedAt
    }
}

public enum WidgetSnapshotStore {
    public static let groupID = "group.com.psmattas.Arcfin.shared"

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget", isDirectory: true)
    }

    private static var snapshotURL: URL? { directory?.appendingPathComponent("snapshot.json") }

    public static func posterURL(fileName: String) -> URL? {
        directory?.appendingPathComponent(fileName)
    }

    public static func load() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: WidgetSnapshot) {
        guard let directory, let url = snapshotURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public static func hasPoster(fileName: String) -> Bool {
        guard let url = posterURL(fileName: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func writePoster(_ data: Data, fileName: String) {
        guard let directory, let url = posterURL(fileName: fileName) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Removes everything the widgets show: used on sign-out so a Lock Screen or Home Screen
    /// widget doesn't keep displaying the previous account's titles.
    public static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Deletes poster files the current snapshot no longer references so the container
    /// doesn't grow every time Continue Watching changes.
    public static func prunePosters(keeping names: Set<String>) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for file in files where file != "snapshot.json" && !names.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}
