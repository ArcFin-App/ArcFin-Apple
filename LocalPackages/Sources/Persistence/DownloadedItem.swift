import Foundation
import SwiftData

/// A fully offline-playable downloaded item — video, subtitles, trickplay tiles, and
/// metadata are all saved to disk at download time so playback needs zero network access.
@Model
public final class DownloadedItem {
    @Attribute(.unique) public var itemId: String

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

    // Local files — filenames only, resolved against DownloadStore.directory(for: itemId) at read time.
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

    public var fileSizeBytes: Int64
    public var downloadedAt: Date
    public var playbackPositionTicks: Int64
    public var played: Bool

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
        playbackPositionTicks: Int64 = 0, played: Bool = false
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
        self.playbackPositionTicks = playbackPositionTicks; self.played = played
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
}
