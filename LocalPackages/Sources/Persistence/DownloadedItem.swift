// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SwiftData

/// A fully offline-playable downloaded item — video, subtitles, trickplay tiles, and
/// metadata are all saved to disk at download time so playback needs zero network access.
@Model
public final class DownloadedItem {
    // Not unique: each profile keeps its own copy of a title. DownloadManager keeps one per profile.
    public var itemId: String

    public var name: String
    public var typeRaw: String
    public var overview: String?
    public var runtimeTicks: Int64
    public var productionYear: Int?
    public var communityRating: Double?
    public var officialRating: String?
    public var genres: [String]

    // Series grouping — nil for movies.
    public var seriesId: String?
    public var seriesName: String?
    public var seasonNumber: Int?
    public var episodeNumber: Int?

    // Server context, so progress can sync back once the user's online again.
    public var serverId: String
    public var serverBaseURL: String
    public var userId: String

    /// The folder under Downloads holding the files, when it isn't the itemId itself: another
    /// profile's copy of the same title was already there. nil on downloads from before this was kept.
    public var folderName: String?

    // Local files — filenames only, resolved against DownloadStore.directory(for: self) at read time.
    public var videoFileName: String
    public var posterFileName: String?
    public var backdropFileName: String?
    public var subtitleFileNames: [String]
    public var subtitleLanguages: [String]
    public var trickplayFileNames: [String]
    public var trickplayWidth: Int?
    public var trickplayHeight: Int?
    public var trickplayTileWidth: Int?
    public var trickplayTileHeight: Int?
    public var trickplayIntervalMs: Int?
    public var trickplayThumbnailCount: Int?
    public var introEndSeconds: Double?
    public var creditsStartSeconds: Double?
    // The rest of the skip markers. Downloads from before these existed have only the two
    // above until they're filled in from the server.
    public var introStartSeconds: Double?
    public var creditsEndSeconds: Double?
    public var recapStartSeconds: Double?
    public var recapEndSeconds: Double?
    public var previewStartSeconds: Double?
    public var previewEndSeconds: Double?
    /// Ad breaks as "start-end" pairs in seconds, comma-separated.
    public var commercialSpans: String?
    public var skipSegmentsSaved: Bool = false

    public var fileSizeBytes: Int64
    public var downloadedAt: Date
    public var playbackPositionTicks: Int64
    public var played: Bool
    /// Set whenever position/played changes from offline playback — cleared once
    /// OfflineProgressSync (SyncEngine) has successfully reported it back to the server.
    public var needsSync: Bool = false
    /// When playback here last moved the position or watched state, to weigh it against the
    /// server's own last-played time. nil on downloads from before this was kept.
    public var progressChangedAt: Date?
    /// The server's play count when this was downloaded, and as last seen. Jellyfin only raises
    /// it when a title is watched to the end (or marked watched), on any device, so the two tell
    /// a finish since the download apart from a title watched before it, or one being rewatched.
    /// nil on downloads from before these were kept, until the next watched-state sync.
    public var playCountAtDownload: Int?
    public var serverPlayCount: Int?

    /// Watched to the end, here or anywhere else, since it was downloaded. What Delete After
    /// Watching and Smart Downloads go by, rather than `played`, which can be true from before.
    public var finishedSinceDownload: Bool {
        guard let start = playCountAtDownload, let now = serverPlayCount else { return false }
        return now > start
    }

    // Richer page details, saved at download time so the downloaded page reads like the
    // online one. Defaults keep older downloads (made before these existed) loading as-is.
    public var tagline: String?
    public var studios: [String] = []
    public var directors: [String] = []
    /// Up to ten billed cast members, with roles and small photos saved alongside.
    public var castNames: [String] = []
    public var castRoles: [String] = []
    public var castPhotoFileNames: [String] = []
    /// e.g. "4K · HDR10 · HEVC" and "English · Dolby Digital 5.1".
    public var videoSummary: String?
    public var audioSummary: String?

    public init(
        itemId: String, name: String, typeRaw: String, overview: String? = nil,
        runtimeTicks: Int64 = 0, productionYear: Int? = nil, communityRating: Double? = nil,
        officialRating: String? = nil, genres: [String] = [],
        seriesId: String? = nil, seriesName: String? = nil, seasonNumber: Int? = nil, episodeNumber: Int? = nil,
        serverId: String, serverBaseURL: String, userId: String,
        videoFileName: String, posterFileName: String? = nil, backdropFileName: String? = nil,
        subtitleFileNames: [String] = [], subtitleLanguages: [String] = [],
        trickplayFileNames: [String] = [], trickplayWidth: Int? = nil, trickplayHeight: Int? = nil,
        trickplayTileWidth: Int? = nil, trickplayTileHeight: Int? = nil,
        trickplayIntervalMs: Int? = nil, trickplayThumbnailCount: Int? = nil,
        introEndSeconds: Double? = nil, creditsStartSeconds: Double? = nil,
        fileSizeBytes: Int64 = 0, downloadedAt: Date = Date(),
        playbackPositionTicks: Int64 = 0, played: Bool = false, needsSync: Bool = false
    ) {
        self.itemId = itemId; self.name = name; self.typeRaw = typeRaw; self.overview = overview
        self.runtimeTicks = runtimeTicks; self.productionYear = productionYear
        self.communityRating = communityRating; self.officialRating = officialRating; self.genres = genres
        self.seriesId = seriesId; self.seriesName = seriesName
        self.seasonNumber = seasonNumber; self.episodeNumber = episodeNumber
        self.serverId = serverId; self.serverBaseURL = serverBaseURL; self.userId = userId
        self.videoFileName = videoFileName; self.posterFileName = posterFileName; self.backdropFileName = backdropFileName
        self.subtitleFileNames = subtitleFileNames; self.subtitleLanguages = subtitleLanguages
        self.trickplayFileNames = trickplayFileNames
        self.trickplayWidth = trickplayWidth; self.trickplayHeight = trickplayHeight
        self.trickplayTileWidth = trickplayTileWidth; self.trickplayTileHeight = trickplayTileHeight
        self.trickplayIntervalMs = trickplayIntervalMs; self.trickplayThumbnailCount = trickplayThumbnailCount
        self.introEndSeconds = introEndSeconds; self.creditsStartSeconds = creditsStartSeconds
        self.fileSizeBytes = fileSizeBytes; self.downloadedAt = downloadedAt
        self.playbackPositionTicks = playbackPositionTicks; self.played = played; self.needsSync = needsSync
    }
}

// MARK: - File layout

/// Where a DownloadedItem's files live on disk — Application Support, not Documents, and
/// excluded from iCloud/iTunes backup since media files would otherwise eat the user's
/// backup quota for content that can just be re-downloaded.
public enum DownloadStore {
    public static func rootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Downloads", isDirectory: true)
    }

    public static func directory(for itemId: String) -> URL {
        rootDirectory().appendingPathComponent(itemId, isDirectory: true)
    }

    public static func ensureDirectory(for itemId: String) throws -> URL {
        let dir = directory(for: itemId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(resourceValues)
        return dir
    }

    public static func deleteDirectory(for itemId: String) {
        try? FileManager.default.removeItem(at: directory(for: itemId))
    }

    /// Holds the folders of a second profile's copy of a title, one folder per profile.
    public static let profilesFolderName = "Profiles"

    /// A download's folder under Downloads: the itemId, as every download from before profiles
    /// kept their own had, unless another profile's copy already has that folder.
    public static func folderName(for itemId: String, profileId: String, itemFolderTaken: Bool) -> String {
        itemFolderTaken ? "\(profilesFolderName)/\(profileId)/\(itemId)" : itemId
    }

    public static func directory(forFolder folderName: String) -> URL {
        rootDirectory().appendingPathComponent(folderName, isDirectory: true)
    }

    public static func directory(for item: DownloadedItem) -> URL {
        directory(forFolder: item.storedFolderName)
    }

    /// The folder name of a directory under Downloads, as `folderName` gives it.
    public static func folderName(of directory: URL) -> String {
        let root = rootDirectory().standardizedFileURL.pathComponents
        let parts = directory.standardizedFileURL.pathComponents
        if parts.count > root.count, Array(parts.prefix(root.count)) == root {
            return parts.dropFirst(root.count).joined(separator: "/")
        }
        // A path saved under another container path: read from its end.
        let tail = Array(parts.suffix(3))
        return tail.count == 3 && tail[0] == profilesFolderName ? tail.joined(separator: "/") : directory.lastPathComponent
    }

    public static func ensureDirectory(forFolder folderName: String) throws -> URL {
        let dir = directory(forFolder: folderName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(resourceValues)
        return dir
    }

    public static func deleteDirectory(forFolder folderName: String) {
        try? FileManager.default.removeItem(at: directory(forFolder: folderName))
    }

    /// The folders, by `folderName`, that nothing points to any more: neither a kept folder nor
    /// one for a title still under way (which can be in either place).
    public static func leftoverFolders(present: [String], keeping kept: Set<String>, underway: Set<String>) -> [String] {
        present.filter { folder in
            !kept.contains(folder) && !underway.contains(folder.split(separator: "/").last.map(String.init) ?? folder)
        }
    }
}

extension DownloadedItem {
    public var storedFolderName: String { folderName ?? itemId }

    public var profile: DownloadProfile {
        DownloadProfile(id: serverId, userId: userId, serverBaseURL: serverBaseURL)
    }

    public func belongs(to profile: DownloadProfile?) -> Bool {
        profile?.owns(self.profile) ?? false
    }

    /// Names this profile's copy in lists kept outside SwiftData, like the downloads waiting
    /// to be removed once watched.
    public var profileKey: String { "\(serverId)|\(userId)|\(itemId)" }

    /// Keys from before each profile kept its own downloads are a bare item id, naming the one
    /// download of it there was then, which is still in the item's own folder.
    public func matches(profileKey key: String) -> Bool {
        key.contains("|") ? key == profileKey : (key == itemId && folderName == nil)
    }
}

/// Who a download is for: the saved profile (its id is what DownloadedItem.serverId holds), and
/// the Jellyfin user and server behind it.
public struct DownloadProfile: Hashable, Sendable {
    public let id: String
    public let userId: String
    public let serverBaseURL: String

    public init(id: String, userId: String, serverBaseURL: String) {
        self.id = id
        self.userId = userId
        self.serverBaseURL = serverBaseURL
    }

    /// The same profile, or the same user on the same server signed in again as a new profile
    /// (signing out keeps the downloads, and a new sign-in gets a new profile id).
    public func owns(_ other: DownloadProfile) -> Bool {
        other.userId == userId && (other.id == id || other.serverBaseURL == serverBaseURL)
    }
}
