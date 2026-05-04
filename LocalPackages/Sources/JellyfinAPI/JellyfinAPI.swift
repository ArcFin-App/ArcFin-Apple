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

public struct MediaItem: Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var overview: String?
    public var type: MediaType
    public var backdropImageTags: [String]
    public var primaryImageTag: String?
    public var userData: UserData?
    public var productionYear: Int?
    public var communityRating: Double?
    public var seriesName: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    public var seriesId: String?
    public var seriesPrimaryImageTag: String?

    public init(
        id: String,
        name: String,
        overview: String? = nil,
        type: MediaType,
        backdropImageTags: [String] = [],
        primaryImageTag: String? = nil,
        userData: UserData? = nil,
        productionYear: Int? = nil,
        communityRating: Double? = nil,
        seriesName: String? = nil,
        indexNumber: Int? = nil,
        parentIndexNumber: Int? = nil,
        seriesId: String? = nil,
        seriesPrimaryImageTag: String? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.type = type
        self.backdropImageTags = backdropImageTags
        self.primaryImageTag = primaryImageTag
        self.userData = userData
        self.productionYear = productionYear
        self.communityRating = communityRating
        self.seriesName = seriesName
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.seriesId = seriesId
        self.seriesPrimaryImageTag = seriesPrimaryImageTag
    }
}

public enum MediaType: String, Sendable, Equatable {
    case movie = "Movie"
    case series = "Series"
    case episode = "Episode"
    case season = "Season"
    case audio = "Audio"
    case musicAlbum = "MusicAlbum"
    case unknown
}

public struct UserData: Sendable, Equatable {
    public var playbackPositionTicks: Int64
    public var playCount: Int
    public var isFavorite: Bool
    public var played: Bool
    public var playedPercentage: Double?

    public init(
        playbackPositionTicks: Int64 = 0,
        playCount: Int = 0,
        isFavorite: Bool = false,
        played: Bool = false,
        playedPercentage: Double? = nil
    ) {
        self.playbackPositionTicks = playbackPositionTicks
        self.playCount = playCount
        self.isFavorite = isFavorite
        self.played = played
        self.playedPercentage = playedPercentage
    }
}

// MARK: - Library

public struct JellyfinLibrary: Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var collectionType: LibraryType
    public var primaryImageTag: String?

    public init(id: String, name: String, collectionType: LibraryType, primaryImageTag: String? = nil) {
        self.id = id; self.name = name; self.collectionType = collectionType; self.primaryImageTag = primaryImageTag
    }

    public enum LibraryType: Sendable, Equatable {
        case movies, tvshows, music, homevideos, photos, books, livetv, playlists, unknown

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
            case .playlists:  "music.note.list"
            case .unknown:    "folder"
            }
        }

        public var accentHex: String {
            switch self {
            case .movies:     "06B6D4"
            case .tvshows:    "8B5CF6"
            case .music:      "EC4899"
            case .homevideos: "F59E0B"
            case .photos:     "10B981"
            case .books:      "F97316"
            case .livetv:     "EF4444"
            case .playlists:  "06B6D4"
            case .unknown:    "6B7280"
            }
        }
    }
}
