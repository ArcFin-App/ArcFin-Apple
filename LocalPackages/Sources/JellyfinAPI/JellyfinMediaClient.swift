import Foundation
import AuthCore

// MARK: - Image type

public enum JellyfinImageType: String, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
}

// MARK: - Media client

public struct JellyfinMediaClient: Sendable {

    public init() {}

    public func getLatestMedia(
        credential: ServerCredential,
        authHeader: String,
        limit: Int = 16
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/Latest"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating"),
            .init(name: "ImageTypeLimit", value: "1"),
            .init(name: "Recursive", value: "true"),
            .init(name: "IncludeItemTypes", value: "Movie,Series"),
            .init(name: "Limit", value: "\(limit)"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode([JellyfinItemResponse].self, from: data).map { $0.toMediaItem() }
    }

    public func getContinueWatching(
        credential: ServerCredential,
        authHeader: String,
        limit: Int = 12
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "DatePlayed"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Filters", value: "IsResumable"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,SeriesName"),
            .init(name: "IncludeItemTypes", value: "Movie,Episode"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try JSONDecoder().decode(ItemsPage.self, from: data)
        return page.items.map { $0.toMediaItem() }
    }

    public static func imageURL(
        baseURL: URL,
        itemID: String,
        tag: String,
        type: JellyfinImageType = .primary,
        fillWidth: Int = 300,
        token: String
    ) -> URL {
        let path = type == .backdrop
            ? "Items/\(itemID)/Images/Backdrop/0"
            : "Items/\(itemID)/Images/Primary"
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "fillWidth", value: "\(fillWidth)"),
            .init(name: "quality", value: "90"),
            .init(name: "tag", value: tag),
            .init(name: "api_key", value: token),
        ]
        return comps.url!
    }
}

// MARK: - Private response types

private struct ItemsPage: Decodable {
    let items: [JellyfinItemResponse]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct JellyfinItemResponse: Decodable {
    let id: String
    let name: String
    let type: String
    let overview: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let userData: UserDataResponse?
    let productionYear: Int?
    let communityRating: Double?
    let seriesName: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case overview = "Overview"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case userData = "UserData"
        case productionYear = "ProductionYear"
        case communityRating = "CommunityRating"
        case seriesName = "SeriesName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
    }

    func toMediaItem() -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            overview: overview,
            type: MediaType(rawValue: type) ?? .unknown,
            backdropImageTags: backdropImageTags ?? [],
            primaryImageTag: imageTags?["Primary"],
            userData: userData.map {
                UserData(
                    playbackPositionTicks: $0.playbackPositionTicks ?? 0,
                    playCount: $0.playCount ?? 0,
                    isFavorite: $0.isFavorite ?? false,
                    played: $0.played ?? false,
                    playedPercentage: $0.playedPercentage
                )
            },
            productionYear: productionYear,
            communityRating: communityRating,
            seriesName: seriesName,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber
        )
    }
}

private struct UserDataResponse: Decodable {
    let playbackPositionTicks: Int64?
    let playCount: Int?
    let isFavorite: Bool?
    let played: Bool?
    let playedPercentage: Double?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case isFavorite = "IsFavorite"
        case played = "Played"
        case playedPercentage = "PlayedPercentage"
    }
}
