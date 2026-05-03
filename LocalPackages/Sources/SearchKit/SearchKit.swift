import Foundation
import CoreSpotlight
import Telemetry

// MARK: - Search client protocol

public protocol SearchClientProtocol: Sendable {
    func search(query: String, scope: SearchScope) async throws -> SearchResults
    func indexItem(_ item: SpotlightItem) async throws
    func deindexItems(identifiers: [String]) async throws
}

// MARK: - Search scope

public enum SearchScope: Sendable {
    case all
    case movies
    case series
    case episodes
    case music
}

// MARK: - Results

// CSSearchableItem is not Sendable; isolate Spotlight results behind @unchecked.
public struct SearchResults: @unchecked Sendable {
    public var serverResults: [ServerSearchResult]
    public var spotlightResults: [CSSearchableItem]

    public init(serverResults: [ServerSearchResult] = [], spotlightResults: [CSSearchableItem] = []) {
        self.serverResults = serverResults
        self.spotlightResults = spotlightResults
    }
}

public struct ServerSearchResult: Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var type: String
    public var year: Int?

    public init(id: String, name: String, type: String, year: Int? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.year = year
    }
}

// MARK: - Spotlight indexing

public struct SpotlightItem: Sendable {
    public var uniqueIdentifier: String
    public var domainIdentifier: String
    public var title: String
    public var contentDescription: String?
    public var thumbnailURL: URL?
    public var keywords: [String]

    public init(
        uniqueIdentifier: String,
        domainIdentifier: String,
        title: String,
        contentDescription: String? = nil,
        thumbnailURL: URL? = nil,
        keywords: [String] = []
    ) {
        self.uniqueIdentifier = uniqueIdentifier
        self.domainIdentifier = domainIdentifier
        self.title = title
        self.contentDescription = contentDescription
        self.thumbnailURL = thumbnailURL
        self.keywords = keywords
    }
}
