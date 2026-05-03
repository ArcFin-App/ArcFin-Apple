import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import AuthCore
import Telemetry

// MARK: - Client protocol
// Stub — replace with OpenAPI-generated types once jellyseerr openapi.yaml is wired up.

public protocol JellyseerrClientProtocol: Sendable {
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

public enum RequestStatus: Int, Sendable, Equatable {
    case pending = 1, approved, declined, available
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
