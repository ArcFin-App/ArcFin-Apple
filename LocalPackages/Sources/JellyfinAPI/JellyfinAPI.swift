// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import AuthCore
import Telemetry

// MARK: - Client protocol
// Replace stub implementations with OpenAPI-generated types once openapi.yaml is wired up.

public protocol JellyfinAPIClientProtocol: Sendable {
    // Auth
    func authenticate(baseURL: URL, username: String, password: String) async throws -> ServerCredential
    // Libraries
    func getLatestMedia(serverID: UUID, limit: Int) async throws -> [MediaItem]
    func getContinueWatching(serverID: UUID) async throws -> [MediaItem]
    // Items
    func getItem(serverID: UUID, itemID: String) async throws -> MediaItem
    func search(serverID: UUID, query: String) async throws -> [MediaItem]
    // Playback
    func reportPlaybackStart(serverID: UUID, itemID: String) async throws
    func reportPlaybackProgress(serverID: UUID, itemID: String, positionTicks: Int64) async throws
    func reportPlaybackStopped(serverID: UUID, itemID: String, positionTicks: Int64) async throws
}

// MARK: - Stub models (replace with OpenAPI-generated when specs land)

public struct MediaItem: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var overview: String?
    public var type: MediaType
    public var backdropImageTags: [String]
    public var primaryImageTag: String?
    public var thumbImageTag: String?
    public var userData: UserData?
    public var productionYear: Int?
    public var communityRating: Double?
    public var seriesName: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    public var seriesId: String?
    public var seriesPrimaryImageTag: String?
    public var parentBackdropItemId: String?
    public var parentBackdropImageTags: [String]
    public var tmdbId: Int?
    public var imdbId: String?
    public var premiereDate: Date?
    public var runTimeTicks: Int64?
    public var genres: [String]
    /// Listed on the server with no file behind it: an episode that hasn't aired or is missing.
    public var isVirtual: Bool

    public init(
        id: String,
        name: String,
        overview: String? = nil,
        type: MediaType,
        backdropImageTags: [String] = [],
        primaryImageTag: String? = nil,
        thumbImageTag: String? = nil,
        userData: UserData? = nil,
        productionYear: Int? = nil,
        communityRating: Double? = nil,
        seriesName: String? = nil,
        indexNumber: Int? = nil,
        parentIndexNumber: Int? = nil,
        seriesId: String? = nil,
        seriesPrimaryImageTag: String? = nil,
        parentBackdropItemId: String? = nil,
        parentBackdropImageTags: [String] = [],
        tmdbId: Int? = nil,
        imdbId: String? = nil,
        premiereDate: Date? = nil,
        runTimeTicks: Int64? = nil,
        genres: [String] = [],
        isVirtual: Bool = false
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.type = type
        self.backdropImageTags = backdropImageTags
        self.primaryImageTag = primaryImageTag
        self.thumbImageTag = thumbImageTag
        self.userData = userData
        self.productionYear = productionYear
        self.communityRating = communityRating
        self.seriesName = seriesName
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.seriesId = seriesId
        self.seriesPrimaryImageTag = seriesPrimaryImageTag
        self.parentBackdropItemId = parentBackdropItemId
        self.parentBackdropImageTags = parentBackdropImageTags
        self.tmdbId = tmdbId
        self.imdbId = imdbId
        self.premiereDate = premiereDate
        self.runTimeTicks = runTimeTicks
        self.genres = genres
        self.isVirtual = isVirtual
    }
}

public enum MediaType: String, Sendable, Equatable {
    case movie = "Movie"
    case series = "Series"
    case episode = "Episode"
    case season = "Season"
    case audio = "Audio"
    case musicAlbum = "MusicAlbum"
    case boxSet = "BoxSet"
    case playlist = "Playlist"
    case tvChannel = "TvChannel"
    case unknown
}

public struct UserData: Sendable, Equatable, Hashable {
    public var playbackPositionTicks: Int64
    public var playCount: Int
    public var isFavorite: Bool
    public var played: Bool
    public var playedPercentage: Double?
    /// Thumbs rating: true = liked, false = disliked, nil = not rated.
    public var likes: Bool?
    /// When it was last played anywhere, as the server records it.
    public var lastPlayedDate: Date?
    /// Episodes left to watch, for a series, season or collection.
    public var unplayedItemCount: Int?

    public init(
        playbackPositionTicks: Int64 = 0,
        playCount: Int = 0,
        isFavorite: Bool = false,
        played: Bool = false,
        playedPercentage: Double? = nil,
        likes: Bool? = nil,
        lastPlayedDate: Date? = nil,
        unplayedItemCount: Int? = nil
    ) {
        self.playbackPositionTicks = playbackPositionTicks
        self.playCount = playCount
        self.isFavorite = isFavorite
        self.played = played
        self.playedPercentage = playedPercentage
        self.likes = likes
        self.lastPlayedDate = lastPlayedDate
        self.unplayedItemCount = unplayedItemCount
    }
}

// MARK: - Person

public struct MediaPerson: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var role: String?
    public var primaryImageTag: String?
    public var type: String

    public init(id: String, name: String, role: String? = nil, primaryImageTag: String? = nil, type: String = "Actor") {
        self.id = id; self.name = name; self.role = role
        self.primaryImageTag = primaryImageTag; self.type = type
    }
}

/// Fetched separately from the bare MediaPerson Jellyfin hands back inline on an item's People
/// list (name/role/image tag only) — a person's own biography and provider ids live on the
/// Person as its own item, a second request (getPersonDetail).
public struct MediaPersonDetail: Sendable, Equatable {
    public let id: String
    public let overview: String?
    public let tmdbId: Int?
    public let birthDate: Date?

    public init(id: String, overview: String? = nil, tmdbId: Int? = nil, birthDate: Date? = nil) {
        self.id = id; self.overview = overview; self.tmdbId = tmdbId; self.birthDate = birthDate
    }
}

// MARK: - Media stream

public struct MediaStream: Sendable, Equatable, Hashable {
    public var type: String
    public var codec: String?
    public var displayTitle: String?
    public var width: Int?
    public var height: Int?
    public var bitRate: Int?
    public var isDefault: Bool

    public init(type: String, codec: String? = nil, displayTitle: String? = nil,
                width: Int? = nil, height: Int? = nil, bitRate: Int? = nil, isDefault: Bool = false) {
        self.type = type; self.codec = codec; self.displayTitle = displayTitle
        self.width = width; self.height = height; self.bitRate = bitRate; self.isDefault = isDefault
    }
}

// MARK: - Chapter

public struct MediaChapter: Sendable, Equatable, Hashable {
    public let startPositionTicks: Int64
    public let name: String?

    public init(startPositionTicks: Int64, name: String? = nil) {
        self.startPositionTicks = startPositionTicks
        self.name = name
    }
}

// MARK: - Item detail

public struct MediaItemDetail: Sendable, Identifiable {
    public var id: String { item.id }
    public var item: MediaItem
    public var people: [MediaPerson]
    public var mediaStreams: [MediaStream]
    public var genres: [String]
    public var studios: [String]
    public var officialRating: String?
    public var runTimeTicks: Int64?
    public var taglines: [String]
    public var chapters: [MediaChapter]
    /// Keyed by MediaSourceId — look up with the id PlaybackInfo actually returns for the
    /// stream being played, since an item can have more than one version/source.
    public var trickplay: [String: JellyfinTrickplayInfo]
    /// External trailer links (YouTube, etc.) a metadata provider attached to the item —
    /// distinct from LocalTrailers, which are real files the server can stream directly.
    /// Fallback when there's no local trailer indexed.
    public var remoteTrailers: [RemoteTrailer]

    public var runtimeMinutes: Int? {
        guard let ticks = runTimeTicks, ticks > 0 else { return nil }
        return Int(ticks / 10_000_000 / 60)
    }

    public var videoStream: MediaStream? { mediaStreams.first { $0.type == "Video" } }
    public var audioStreams: [MediaStream] { mediaStreams.filter { $0.type == "Audio" } }
    public var directors: [MediaPerson] { people.filter { $0.type == "Director" } }
    public var writers: [MediaPerson] { people.filter { $0.type == "Writer" } }
    public var cast: [MediaPerson] { Array(people.filter { $0.type == "Actor" }.prefix(20)) }

    public var is4K: Bool { (videoStream?.height ?? 0) >= 2160 }
    public var isHDR: Bool {
        let t = (videoStream?.displayTitle ?? "").lowercased()
        return t.contains("hdr") || t.contains("dolby vision") || t.contains(" dv")
    }

    /// Critics' score out of 100 (the OMDb plugin fills it from Rotten Tomatoes).
    public var criticRating: Double?
    // For the title page's details section.
    public var originalTitle: String?
    public var productionLocations: [String] = []
    public var tags: [String] = []
    /// "Continuing" or "Ended", for shows.
    public var status: String?
    public var airDays: [String] = []
    public var airTime: String?
    public var premiereDate: Date?
    public var endDate: Date?
    public var externalLinks: [ExternalLink] = []
    public var files: [MediaFileInfo] = []

    public init(item: MediaItem, people: [MediaPerson] = [], mediaStreams: [MediaStream] = [],
                genres: [String] = [], studios: [String] = [], officialRating: String? = nil,
                runTimeTicks: Int64? = nil, taglines: [String] = [], chapters: [MediaChapter] = [],
                trickplay: [String: JellyfinTrickplayInfo] = [:], remoteTrailers: [RemoteTrailer] = [],
                criticRating: Double? = nil) {
        self.item = item; self.people = people; self.mediaStreams = mediaStreams
        self.genres = genres; self.studios = studios; self.officialRating = officialRating
        self.runTimeTicks = runTimeTicks; self.taglines = taglines; self.chapters = chapters
        self.trickplay = trickplay; self.remoteTrailers = remoteTrailers
        self.criticRating = criticRating
    }
}

/// A page about the title elsewhere (IMDb, TMDB, TheTVDB…).
public struct ExternalLink: Sendable, Identifiable, Equatable {
    public var id: String { url.absoluteString }
    public let name: String
    public let url: URL
    public init(name: String, url: URL) { self.name = name; self.url = url }
}

/// One version of the title on the server.
public struct MediaFileInfo: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String?
    public let container: String?
    public let sizeBytes: Int64?
    public let bitrate: Int?
    public init(id: String, name: String?, container: String?, sizeBytes: Int64?, bitrate: Int?) {
        self.id = id; self.name = name; self.container = container; self.sizeBytes = sizeBytes; self.bitrate = bitrate
    }
}

public struct RemoteTrailer: Sendable, Identifiable, Equatable {
    public var id: String { url.absoluteString }
    public let url: URL
    public let name: String?

    public init(url: URL, name: String?) {
        self.url = url
        self.name = name
    }

    /// The raw YouTube video id, or nil if this remote trailer isn't a YouTube link at all
    /// (some providers attach other hosts). YouTubePlayerKit takes it from here — actually
    /// building an embeddable player (origin/config validation etc.) is its job, not ours.
    public var youTubeVideoID: String? {
        guard let host = url.host?.lowercased() else { return nil }
        var videoId: String?
        if host.contains("youtu.be") {
            videoId = url.pathComponents.dropFirst().first
        } else if host.contains("youtube.com") {
            if url.path.hasPrefix("/embed/") {
                videoId = url.pathComponents.dropFirst(2).first
            } else {
                videoId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "v" })?.value
            }
        }
        return (videoId?.isEmpty == false) ? videoId : nil
    }
}

/// One category from GET /Movies/Recommendations — e.g. "movies like something you recently
/// watched" or "more from an actor you like." Server-wide, not scoped to a single item.
public struct MovieRecommendationCategory: Sendable, Identifiable, Equatable {
    public let id: String
    public let recommendationType: String
    public let baselineItemName: String?
    public let items: [MediaItem]

    public init(id: String, recommendationType: String, baselineItemName: String?, items: [MediaItem]) {
        self.id = id
        self.recommendationType = recommendationType
        self.baselineItemName = baselineItemName
        self.items = items
    }

    public var title: String {
        switch recommendationType {
        case "SimilarToRecentlyPlayed":     "Because You Watched \(baselineItemName ?? "")"
        case "SimilarToLikedItem":          "Because You Liked \(baselineItemName ?? "")"
        case "HasDirectorFromRecentlyPlayed": "More From This Director"
        case "HasActorFromRecentlyPlayed":  "More With This Cast"
        case "HasLikedDirector":            "More From Directors You Like"
        case "HasLikedActor":               "More With Actors You Like"
        default:                            "Recommended"
        }
    }
}

// MARK: - Library

public struct JellyfinLibrary: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var collectionType: LibraryType
    public var primaryImageTag: String?
    public var backdropImageTag: String?

    public init(id: String, name: String, collectionType: LibraryType, primaryImageTag: String? = nil, backdropImageTag: String? = nil) {
        self.id = id; self.name = name; self.collectionType = collectionType
        self.primaryImageTag = primaryImageTag; self.backdropImageTag = backdropImageTag
    }

    public enum LibraryType: Sendable, Equatable, Hashable {
        case movies, tvshows, music, homevideos, photos, books, livetv, playlists, boxsets, unknown

        public init(apiValue: String) {
            switch apiValue.lowercased() {
            case "movies":     self = .movies
            case "tvshows":    self = .tvshows
            case "music":      self = .music
            case "homevideos": self = .homevideos
            case "photos":     self = .photos
            case "books":      self = .books
            case "livetv":     self = .livetv
            case "playlists":  self = .playlists
            case "boxsets":    self = .boxsets
            default:           self = .unknown
            }
        }

        public var systemIcon: String {
            switch self {
            case .movies:     "film"
            case .tvshows:    "tv"
            case .music:      "music.note"
            case .homevideos: "video.fill"
            case .photos:     "photo"
            case .books:      "books.vertical"
            case .livetv:     "antenna.radiowaves.left.and.right"
            case .playlists:  "list.and.film"
            case .boxsets:    "rectangle.stack"
            case .unknown:    "folder"
            }
        }

        public var accentHex: String {
            switch self {
            case .movies:     "FF6A4D"
            case .tvshows:    "60A5FA"
            case .music:      "EC4899"
            case .homevideos: "F59E0B"
            case .photos:     "10B981"
            case .books:      "F97316"
            case .livetv:     "F43F5E"
            case .playlists:  "FF6A4D"
            case .boxsets:    "F59E0B"
            case .unknown:    "6B7280"
            }
        }
    }
}
