// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import AuthCore
import Telemetry

// MARK: - Client protocol
// Stub — replace with OpenAPI-generated types once seerr openapi.yaml is wired up.

public protocol SeerrClientProtocol: Sendable {
    func getRequests(page: Int, filter: RequestFilter) async throws -> RequestsPage
    func requestMedia(mediaType: RequestMediaType, mediaID: Int, seasons: [Int]?) async throws -> MediaRequest
    func getRequestStatus(requestID: Int) async throws -> MediaRequest
    func cancelRequest(requestID: Int) async throws
    func searchMedia(query: String) async throws -> [SearchResult]
}

// MARK: - Stub models

public enum RequestFilter: String, Sendable {
    case all, approved, pending, processing, available, unavailable
}

public enum RequestMediaType: String, Sendable {
    case movie, tv
}

/// Seerr's request.status — the approval state of the request itself, distinct from
/// media.status (SeerrAvailabilityStatus), which tracks whether the requested title has
/// actually shown up on the server yet. Seerr's MediaRequestStatus: 1 pending, 2 approved,
/// 3 declined, 4 failed (sending it to Radarr or Sonarr failed), 5 completed.
public enum RequestStatus: Int, Sendable, Equatable {
    case pending = 1, approved, declined, failed, completed
}

public struct MediaRequest: Sendable, Identifiable, Equatable {
    public let id: Int
    public var status: RequestStatus
    public var mediaType: RequestMediaType
    public var mediaTitle: String
    public var requestedAt: Date

    public init(id: Int, status: RequestStatus, mediaType: RequestMediaType, mediaTitle: String, requestedAt: Date) {
        self.id = id
        self.status = status
        self.mediaType = mediaType
        self.mediaTitle = mediaTitle
        self.requestedAt = requestedAt
    }
}

public struct RequestsPage: Sendable {
    public var results: [MediaRequest]
    public var pageInfo: PageInfo

    public init(results: [MediaRequest], pageInfo: PageInfo) {
        self.results = results
        self.pageInfo = pageInfo
    }
}

public struct PageInfo: Sendable {
    public var page: Int
    public var pages: Int
    public var results: Int

    public init(page: Int, pages: Int, results: Int) {
        self.page = page
        self.pages = pages
        self.results = results
    }
}

public struct SearchResult: Sendable, Identifiable, Equatable {
    public let id: Int
    public var title: String
    public var mediaType: RequestMediaType
    public var posterPath: String?
    public var overview: String?

    public init(id: Int, title: String, mediaType: RequestMediaType, posterPath: String? = nil, overview: String? = nil) {
        self.id = id
        self.title = title
        self.mediaType = mediaType
        self.posterPath = posterPath
        self.overview = overview
    }
}

// MARK: - Discover models

public struct SeerrItem: Sendable, Identifiable, Equatable, Hashable {
    public let id: Int
    public var title: String
    public var mediaType: RequestMediaType
    public var posterPath: String?
    public var backdropPath: String?
    public var year: String?
    public var overview: String?
    public var availabilityStatus: SeerrAvailabilityStatus?
    /// TMDB's adult flag, on movies only.
    public var isAdult: Bool

    public init(id: Int, title: String, mediaType: RequestMediaType, posterPath: String? = nil,
                backdropPath: String? = nil, year: String? = nil, overview: String? = nil,
                availabilityStatus: SeerrAvailabilityStatus? = nil, isAdult: Bool = false) {
        self.id = id; self.title = title; self.mediaType = mediaType
        self.posterPath = posterPath; self.backdropPath = backdropPath
        self.year = year; self.overview = overview; self.availabilityStatus = availabilityStatus
        self.isAdult = isAdult
    }

    public var posterURL: URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
    }
    public var backdropURL: URL? {
        backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") }
    }
}

/// A genre with a representative backdrop image — the picker data for /discover/genreslider,
/// used to browse movies/TV by genre.
public struct SeerrGenre: Sendable, Identifiable, Equatable, Hashable {
    public let id: Int
    public var name: String
    public var backdropPath: String?

    public init(id: Int, name: String, backdropPath: String? = nil) {
        self.id = id; self.name = name; self.backdropPath = backdropPath
    }

    public var backdropURL: URL? {
        backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w780\($0)") }
    }
}

public enum SeerrAvailabilityStatus: Int, Sendable, Equatable {
    case unknown = 1, pending, processing, partiallyAvailable, available

    public var label: String {
        switch self {
        case .unknown:           "Unknown"
        case .pending:           "Pending"
        case .processing:        "Processing"
        case .partiallyAvailable:"Partial"
        case .available:         "Available"
        }
    }

    public var colorHex: String {
        switch self {
        case .available:         "10b981"
        case .pending:           "f59e0b"
        case .processing:        "FF6A4D"
        default:                 "6B7280"
        }
    }
}

public struct SeerrRequestItem: Sendable, Identifiable, Equatable, Hashable {
    public let id: Int
    public var mediaTitle: String
    public var mediaType: RequestMediaType
    public var status: RequestStatus
    /// Availability of the underlying media — separate from `status` (the request's own
    /// approval state). A request can be `.approved` while its media is still `.processing`,
    /// or even `.pending` approval while an earlier request already made the media
    /// `.partiallyAvailable`. nil only if Seerr didn't send a media status at all.
    public var mediaStatus: SeerrAvailabilityStatus?
    public var requestedAt: Date
    public var posterPath: String?
    public var backdropPath: String?
    /// TMDB id of the requested title — lets the detail screen fetch the full
    /// movie/tv record (overview, genres, cast, etc.) beyond what the request list carries.
    public var tmdbId: Int?
    /// Who asked for it. Someone who manages requests sees everyone's, not only their own.
    public var requestedByID: Int?
    public var requestedByName: String?

    public init(id: Int, mediaTitle: String, mediaType: RequestMediaType, status: RequestStatus,
                mediaStatus: SeerrAvailabilityStatus? = nil, requestedAt: Date,
                posterPath: String? = nil, backdropPath: String? = nil, tmdbId: Int? = nil,
                requestedByID: Int? = nil, requestedByName: String? = nil) {
        self.id = id; self.mediaTitle = mediaTitle; self.mediaType = mediaType
        self.status = status; self.mediaStatus = mediaStatus; self.requestedAt = requestedAt
        self.posterPath = posterPath; self.backdropPath = backdropPath
        self.tmdbId = tmdbId
        self.requestedByID = requestedByID; self.requestedByName = requestedByName
    }

    public var posterURL: URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") }
    }

    public var backdropURL: URL? {
        backdropPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") }
    }

    /// A single status label+color to show where only one badge fits (a Discover grid card,
    /// a TV card) — prefers the underlying media's own availability over the request's bare
    /// approval state, since "Processing"/"Partial" says more than "Approved" alone.
    public var displayStatus: (label: String, colorHex: String) {
        if let mediaStatus { return (mediaStatus.label, mediaStatus.colorHex) }
        switch status {
        case .pending:  return ("Pending", "f59e0b")
        case .approved: return ("Approved", "10b981")
        case .declined: return ("Declined", "F43F5E")
        case .failed: return ("Failed", "F43F5E")
        case .completed: return ("Completed", "10b981")
        }
    }
}

/// One title from a person's TMDB combined_credits (cast + crew merged, deduplicated) —
/// everything the Person detail screen needs to show "also appears in" and let the user
/// request it directly, without a second detail fetch per title.
public struct SeerrPersonCredit: Sendable, Identifiable, Equatable, Hashable {
    public let id: Int
    public var title: String
    public var mediaType: RequestMediaType
    public var posterPath: String?
    /// Character name (cast) or job (crew, e.g. "Director") — whichever this credit was.
    public var role: String?
    public var mediaStatus: SeerrAvailabilityStatus?

    public init(id: Int, title: String, mediaType: RequestMediaType, posterPath: String? = nil,
                role: String? = nil, mediaStatus: SeerrAvailabilityStatus? = nil) {
        self.id = id; self.title = title; self.mediaType = mediaType
        self.posterPath = posterPath; self.role = role; self.mediaStatus = mediaStatus
    }

    public var posterURL: URL? {
        posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") }
    }

    /// Lets a credit feed straight into the existing request sheet (SeerrRequestConfirmSheet),
    /// which only needs id/title/mediaType/posterPath — it fetches its own full detail
    /// (including season rows) once opened.
    public var asSeerrItem: SeerrItem {
        SeerrItem(id: id, title: title, mediaType: mediaType, posterPath: posterPath,
                  availabilityStatus: mediaStatus)
    }
}

// MARK: - Full media detail (for the request confirmation sheet)

public struct SeerrCastMember: Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let character: String?
    public let profilePath: String?

    public init(id: Int, name: String, character: String?, profilePath: String?) {
        self.id = id; self.name = name; self.character = character; self.profilePath = profilePath
    }

    public var profileURL: URL? {
        profilePath.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") }
    }
}

public struct SeerrSeasonInfo: Sendable, Identifiable, Equatable {
    public var id: Int { number }
    public let number: Int
    public let episodeCount: Int?

    public init(number: Int, episodeCount: Int?) {
        self.number = number; self.episodeCount = episodeCount
    }

    public var label: String { number == 0 ? "Specials" : "Season \(number)" }
}

public struct SeerrMediaDetail: Sendable, Equatable {
    public let tagline: String?
    public let overview: String?
    public let genres: [String]
    public let runtimeMinutes: Int?
    public let voteAverage: Double?
    public let status: String?
    public let cast: [SeerrCastMember]
    public let seasons: [SeerrSeasonInfo]
    /// Per-season request/library status — nil for a movie, or for a server where this
    /// couldn't be computed. Drives the season picker in the request sheet; `seasons` above
    /// stays a plain list for the simpler season-chips row on the detail screen.
    public let seasonRows: [SeerrSeasonRow]?
    /// YouTube video ID for the best available trailer, from Seerr's own relatedVideos
    /// (TMDB-backed, included in its standard movie/tv detail response — no extra query
    /// param needed). nil when TMDB has no trailer on file for this title.
    public let trailerYouTubeKey: String?

    public init(tagline: String?, overview: String?, genres: [String], runtimeMinutes: Int?,
                voteAverage: Double?, status: String?, cast: [SeerrCastMember],
                seasons: [SeerrSeasonInfo] = [], seasonRows: [SeerrSeasonRow]? = nil,
                trailerYouTubeKey: String? = nil) {
        self.tagline = tagline; self.overview = overview; self.genres = genres
        self.runtimeMinutes = runtimeMinutes; self.voteAverage = voteAverage
        self.status = status; self.cast = cast; self.seasons = seasons
        self.seasonRows = seasonRows; self.trailerYouTubeKey = trailerYouTubeKey
    }
}

/// A TMDB company, network or keyword: just enough to label and browse a row by it.
public struct SeerrNamedEntity: Sendable, Identifiable, Equatable, Hashable {
    public let id: Int
    public let name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

/// A streaming service, rental store or shop that has a title (TMDB/JustWatch data).
public struct SeerrWatchProvider: Sendable, Identifiable, Equatable, Hashable, Codable {
    public let id: Int
    public let name: String
    public let logoPath: String?

    public init(id: Int, name: String, logoPath: String?) {
        self.id = id; self.name = name; self.logoPath = logoPath
    }

    public var logoURL: URL? {
        logoPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w154\($0)") }
    }
}

/// Where a title can be watched in one country.
public struct SeerrWatchAvailability: Sendable, Equatable {
    public let streaming: [SeerrWatchProvider]
    public var free: [SeerrWatchProvider] = []
    public var ads: [SeerrWatchProvider] = []
    public let rent: [SeerrWatchProvider]
    public let buy: [SeerrWatchProvider]

    public var isEmpty: Bool { streaming.isEmpty && free.isEmpty && ads.isEmpty && rent.isEmpty && buy.isEmpty }
    /// TMDB's page listing every option, with links out to each service.
    public let link: URL?
}

public struct SeerrNextEpisode: Sendable, Equatable {
    public let name: String
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let airDate: Date?
}

/// What Seerr knows about a title beyond the request sheet's needs: what it's related to,
/// where it's streaming, and the facts a details section shows.
public struct SeerrRelatedInfo: Sendable, Equatable {
    public let companies: [SeerrNamedEntity]
    public let keywords: [SeerrNamedEntity]
    public var watch: SeerrWatchAvailability?
    public var originalTitle: String?
    public var originalLanguage: String?
    public var countries: [String] = []
    public var status: String?
    public var budget: Int?
    public var revenue: Int?
    public var createdBy: [String] = []
    public var networks: [String] = []
    public var numberOfSeasons: Int?
    public var nextEpisode: SeerrNextEpisode?
    public var imdbId: String?

    public init(companies: [SeerrNamedEntity], keywords: [SeerrNamedEntity]) {
        self.companies = companies
        self.keywords = keywords
    }
}

/// Review scores Seerr gathers: Rotten Tomatoes (critics and audience) and IMDb.
public struct SeerrRatings: Sendable, Equatable {
    public var criticsScore: Int?
    /// "Certified Fresh", "Fresh" or "Rotten".
    public var criticsRating: String?
    public var audienceScore: Int?
    /// "Upright" or "Spilled".
    public var audienceRating: String?
    public var rottenTomatoesURL: URL?
    public var imdbScore: Double?
    public var imdbURL: URL?

    public init() {}

    public var isEmpty: Bool { criticsScore == nil && audienceScore == nil && imdbScore == nil }
}
