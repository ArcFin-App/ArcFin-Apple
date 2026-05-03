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
        parentIndexNumber: Int? = nil
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
