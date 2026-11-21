// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What the music widgets show, written by the app into the shared App Group container: the
/// song playing (or paused), what's next, and what was played lately, each with a small cover
/// file. Kept apart from the video widgets' snapshot so neither clears the other's covers.
public struct MusicWidgetSnapshot: Codable, Sendable, Equatable {
    public struct Song: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var artist: String?
        public var album: String?
        /// File name in the store's folder; nil when no cover could be saved.
        public var coverFileName: String?

        public init(id: String, title: String, artist: String?, album: String?, coverFileName: String?) {
            self.id = id; self.title = title; self.artist = artist; self.album = album
            self.coverFileName = coverFileName
        }
    }

    public var nowPlaying: Song?
    public var isPlaying: Bool
    /// Seconds into the song at `positionDate`, so a widget can run its progress on from there.
    public var position: Double
    public var duration: Double
    public var positionDate: Date
    public var upNext: [Song]
    public var recentlyPlayed: [Song]

    public init(nowPlaying: Song?, isPlaying: Bool, position: Double, duration: Double, positionDate: Date = .now,
                upNext: [Song], recentlyPlayed: [Song]) {
        self.nowPlaying = nowPlaying; self.isPlaying = isPlaying; self.position = position
        self.duration = duration; self.positionDate = positionDate
        self.upNext = upNext; self.recentlyPlayed = recentlyPlayed
    }

    /// When the song started, for a progress bar that runs while it plays.
    public var startDate: Date { positionDate.addingTimeInterval(-position) }
}

public enum MusicWidgetStore {
    /// The widgets' kinds, so the app reloads only these.
    public static let nowPlayingKind = "com.psmattas.arcfin.widget.music.nowPlaying"
    public static let recentlyPlayedKind = "com.psmattas.arcfin.widget.music.recentlyPlayed"
    public static let controlKind = "com.psmattas.arcfin.control.music"

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.groupID)?
            .appendingPathComponent("music-widget", isDirectory: true)
    }

    private static var snapshotURL: URL? { directory?.appendingPathComponent("snapshot.json") }

    public static func coverURL(fileName: String) -> URL? { directory?.appendingPathComponent(fileName) }

    public static func load() -> MusicWidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MusicWidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: MusicWidgetSnapshot) {
        guard let directory, let url = snapshotURL else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }

    public static func hasCover(fileName: String) -> Bool {
        guard let url = coverURL(fileName: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func writeCover(_ data: Data, fileName: String) {
        guard let directory, let url = coverURL(fileName: fileName) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Covers the snapshot no longer shows.
    public static func pruneCovers(keeping names: Set<String>) {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where file != "snapshot.json" && !names.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// Signing out or switching profile: the widgets shouldn't keep the last profile's music.
    public static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
