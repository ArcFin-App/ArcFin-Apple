// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What the Scene of the Day widget shows, written by the app into the shared App Group
/// container. No snapshot means the widget shows its neutral placeholder. Kept in its own folder
/// so the video widgets' pruning doesn't delete its picture.
public struct ArcsWidgetSnapshot: Codable, Sendable, Equatable {
    public var clipID: String
    public var title: String
    public var sceneLine: String?
    public var overview: String?
    /// File name in the store's folder; nil when no picture could be saved.
    public var imageFileName: String?
    public var updatedAt: Date

    public init(clipID: String, title: String, sceneLine: String?, overview: String?, imageFileName: String?,
                updatedAt: Date = .now) {
        self.clipID = clipID; self.title = title; self.sceneLine = sceneLine; self.overview = overview
        self.imageFileName = imageFileName; self.updatedAt = updatedAt
    }

    public var url: URL? { URL(string: "arcfin://arcs/\(clipID)") }
}

public enum ArcsWidgetStore {
    public static let kind = "com.psmattas.arcfin.widget.arcs.sceneOfTheDay"

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.groupID)?
            .appendingPathComponent("arcs-widget", isDirectory: true)
    }

    private static var snapshotURL: URL? { directory?.appendingPathComponent("snapshot.json") }

    public static func imageURL(fileName: String) -> URL? { directory?.appendingPathComponent(fileName) }

    public static func load() -> ArcsWidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ArcsWidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: ArcsWidgetSnapshot) {
        guard let directory, let url = snapshotURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }

    public static func hasImage(fileName: String) -> Bool {
        guard let url = imageURL(fileName: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func writeImage(_ data: Data, fileName: String) {
        guard let directory, let url = imageURL(fileName: fileName) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public static func pruneImages(keeping name: String?) {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where file != "snapshot.json" && file != name {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// Signing out, a profile switch, a new app-lock PIN, or Arcs turned off.
    public static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
