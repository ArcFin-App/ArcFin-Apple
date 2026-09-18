import Foundation
import AuthCore

// MARK: - Image type

public enum JellyfinImageType: String, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case logo = "Logo"
    case thumb = "Thumb"
}

// MARK: - Media client

public struct JellyfinMediaClient: Sendable {

    public init() {}

    public func getLatestMedia(
        credential: ServerCredential,
        authHeader: String,
        itemTypes: String = "Movie,Series",
        limit: Int = 16
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/Latest"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,CommunityRating,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "ImageTypeLimit", value: "1"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "Recursive", value: "true"),
            .init(name: "IncludeItemTypes", value: itemTypes),
            .init(name: "Limit", value: "\(limit)"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode([JellyfinItemResponse].self, from: data).map { $0.toMediaItem() }
    }

    /// "Up next" across all shows the user is watching, not scoped to one series.
    public func getNextUp(
        credential: ServerCredential,
        authHeader: String,
        limit: Int = 12
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Shows/NextUp"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImages", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// Library items sorted by premiere/air date — "Recently Released Movies" / "Recently Aired Episodes".
    public func getRecentlyPremiered(
        credential: ServerCredential,
        authHeader: String,
        itemType: String,
        limit: Int = 16
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "SortBy", value: "PremiereDate"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "IncludeItemTypes", value: itemType),
            .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,SeriesName,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// Already-watched items sorted by most recently played — "Watch Again".
    public func getWatchAgain(
        credential: ServerCredential,
        authHeader: String,
        limit: Int = 16
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "SortBy", value: "DatePlayed"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "IncludeItemTypes", value: "Movie,Series"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
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
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,SeriesName,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
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
        let path: String
        switch type {
        case .backdrop:
            path = "Items/\(itemID)/Images/Backdrop/0"
        case .logo:
            path = "Items/\(itemID)/Images/Logo/0"
        case .primary:
            path = "Items/\(itemID)/Images/Primary"
        case .thumb:
            path = "Items/\(itemID)/Images/Thumb"
        }
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "fillWidth", value: "\(fillWidth)"),
            .init(name: "quality", value: "90"),
            .init(name: "tag", value: tag),
            .init(name: "api_key", value: token),
        ]
        return comps.url!
    }

    public func getLibraries(credential: ServerCredential, authHeader: String) async throws -> [JellyfinLibrary] {
        let url = credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Views")
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try JSONDecoder().decode(LibraryViewsResponse.self, from: data)
        return page.items.map {
            JellyfinLibrary(id: $0.id, name: $0.name,
                           collectionType: JellyfinLibrary.LibraryType(apiValue: $0.collectionType ?? ""),
                           primaryImageTag: $0.imageTags?["Primary"])
        }
    }

    /// Fetch the Jellyfin server UUID (needed for Streamystats jellyfinServerId param).
    public func getServerID(credential: ServerCredential) async throws -> String {
        let url = credential.baseURL.appendingPathComponent("System/Info/Public")
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Info: Decodable {
            let id: String
            enum CodingKeys: String, CodingKey { case id = "Id" }
        }
        return try JSONDecoder().decode(Info.self, from: data).id
    }

    public func getTopPlayed(
        credential: ServerCredential,
        authHeader: String,
        itemType: String,
        limit: Int = 6
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "SortBy", value: "PlayCount"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "IncludeItemTypes", value: itemType),
            .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try JSONDecoder().decode(ItemsPage.self, from: data)
        return page.items.map { $0.toMediaItem() }
    }

    public func getPlayedCount(
        credential: ServerCredential,
        authHeader: String,
        itemType: String
    ) async throws -> Int {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "IncludeItemTypes", value: itemType),
            .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "1"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        struct CountPage: Decodable {
            let totalRecordCount: Int
            enum CodingKeys: String, CodingKey { case totalRecordCount = "TotalRecordCount" }
        }
        return (try? JSONDecoder().decode(CountPage.self, from: data).totalRecordCount) ?? 0
    }

    public func getItemDetail(
        credential: ServerCredential,
        authHeader: String,
        itemId: String
    ) async throws -> MediaItemDetail {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/\(itemId)"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Fields", value: "Overview,People,MediaStreams,Genres,Studios,OfficialRating,RunTimeTicks,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating,SeriesName,SeriesId,SeriesPrimaryImageTag,Taglines,ProviderIds"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ItemDetailResponse.self, from: data).toDetail()
    }

    public func getSimilarItems(
        credential: ServerCredential,
        authHeader: String,
        itemId: String,
        limit: Int = 10
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Items/\(itemId)/Similar"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    public func getSeasons(
        credential: ServerCredential,
        authHeader: String,
        seriesId: String
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Shows/\(seriesId)/Seasons"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "Fields", value: "UserData,PrimaryImageTags,ProductionYear,IndexNumber"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    public func getEpisodes(
        credential: ServerCredential,
        authHeader: String,
        seriesId: String,
        seasonId: String
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Shows/\(seriesId)/Episodes"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "SeasonId", value: seasonId),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImages", value: "true"),
            .init(name: "ImageTypeLimit", value: "1"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    public func getNextEpisode(
        credential: ServerCredential,
        authHeader: String,
        seriesId: String
    ) async throws -> MediaItem? {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Shows/NextUp"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "SeriesId", value: seriesId),
            .init(name: "Limit", value: "1"),
            .init(name: "Fields", value: "UserData,Overview"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.first?.toMediaItem()
    }

    public func markWatched(
        credential: ServerCredential,
        authHeader: String,
        itemId: String,
        watched: Bool
    ) async throws {
        let url = credential.baseURL.appendingPathComponent("Users/\(credential.userID)/PlayedItems/\(itemId)")
        var req = URLRequest(url: url)
        req.httpMethod = watched ? "POST" : "DELETE"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        _ = try await URLSession.shared.data(for: req)
    }

    public func getLibraryItems(
        credential: ServerCredential,
        authHeader: String,
        libraryId: String,
        startIndex: Int = 0,
        limit: Int = 100,
        recursive: Bool = true,
        includeItemTypes: String? = nil
    ) async throws -> (items: [MediaItem], total: Int) {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            .init(name: "ParentId", value: libraryId),
            .init(name: "Recursive", value: recursive ? "true" : "false"),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "SortOrder", value: "Ascending"),
            .init(name: "StartIndex", value: "\(startIndex)"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,CommunityRating,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableTotalRecordCount", value: "true"),
        ]
        if let types = includeItemTypes {
            queryItems.append(.init(name: "IncludeItemTypes", value: types))
        }
        comps.queryItems = queryItems
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try JSONDecoder().decode(ItemsPage.self, from: data)
        return (items: page.items.map { $0.toMediaItem() }, total: page.totalRecordCount ?? 0)
    }

    public func search(credential: ServerCredential, authHeader: String, query: String, limit: Int = 20) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "SearchTerm", value: query),
            .init(name: "IncludeItemTypes", value: "Movie,Series,Episode"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,SeriesName"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try JSONDecoder().decode(ItemsPage.self, from: data)
        return page.items.map { $0.toMediaItem() }
    }

    /// Local trailers attached to a specific item.
    /// Uses /Items/{itemId}/LocalTrailers which returns a bare array (not wrapped in Items).
    public func getTrailers(
        credential: ServerCredential,
        authHeader: String,
        itemId: String,
        limit: Int = 6
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Items/\(itemId)/LocalTrailers"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "Fields", value: "Overview,PrimaryImageTags,BackdropImageTags,ProductionYear"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let items = (try? JSONDecoder().decode([JellyfinItemResponse].self, from: data)) ?? []
        return Array(items.prefix(limit).map { $0.toMediaItem() })
    }
}

// MARK: - Private response types

private struct ItemsPage: Decodable {
    let items: [JellyfinItemResponse]
    let totalRecordCount: Int?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
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
    let seriesId: String?
    let seriesPrimaryImageTag: String?
    let parentBackdropItemId: String?
    let parentBackdropImageTags: [String]?

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
        case seriesId = "SeriesId"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case parentBackdropItemId = "ParentBackdropItemId"
        case parentBackdropImageTags = "ParentBackdropImageTags"
    }

    func toMediaItem() -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            overview: overview,
            type: MediaType(rawValue: type) ?? .unknown,
            backdropImageTags: backdropImageTags ?? [],
            primaryImageTag: imageTags?["Primary"],
            thumbImageTag: imageTags?["Thumb"],
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
            parentIndexNumber: parentIndexNumber,
            seriesId: seriesId,
            seriesPrimaryImageTag: seriesPrimaryImageTag,
            parentBackdropItemId: parentBackdropItemId,
            parentBackdropImageTags: parentBackdropImageTags ?? []
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

private struct ItemDetailResponse: Decodable {
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
    let seriesId: String?
    let seriesPrimaryImageTag: String?
    let people: [PersonResponse]?
    let mediaStreams: [MediaStreamResponse]?
    let genres: [String]?
    let studios: [StudioResponse]?
    let officialRating: String?
    let runTimeTicks: Int64?
    let taglines: [String]?
    let providerIds: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", type = "Type", overview = "Overview"
        case imageTags = "ImageTags", backdropImageTags = "BackdropImageTags"
        case userData = "UserData", productionYear = "ProductionYear"
        case communityRating = "CommunityRating", seriesName = "SeriesName"
        case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber"
        case seriesId = "SeriesId", seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case people = "People", mediaStreams = "MediaStreams"
        case genres = "Genres", studios = "Studios"
        case officialRating = "OfficialRating", runTimeTicks = "RunTimeTicks"
        case taglines = "Taglines", providerIds = "ProviderIds"
    }

    func toDetail() -> MediaItemDetail {
        let mediaItem = MediaItem(
            id: id, name: name, overview: overview,
            type: MediaType(rawValue: type) ?? .unknown,
            backdropImageTags: backdropImageTags ?? [],
            primaryImageTag: imageTags?["Primary"],
            thumbImageTag: imageTags?["Thumb"],
            userData: userData.map { ud in
                UserData(playbackPositionTicks: ud.playbackPositionTicks ?? 0,
                         playCount: ud.playCount ?? 0,
                         isFavorite: ud.isFavorite ?? false,
                         played: ud.played ?? false,
                         playedPercentage: ud.playedPercentage)
            },
            productionYear: productionYear,
            communityRating: communityRating,
            seriesName: seriesName,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber,
            seriesId: seriesId,
            seriesPrimaryImageTag: seriesPrimaryImageTag,
            tmdbId: providerIds.flatMap { Int($0["Tmdb"] ?? "") }
        )
        return MediaItemDetail(
            item: mediaItem,
            people: people?.compactMap { p in
                MediaPerson(id: p.id, name: p.name, role: p.role,
                            primaryImageTag: p.primaryImageTag, type: p.type ?? "Actor")
            } ?? [],
            mediaStreams: mediaStreams?.compactMap { s in
                MediaStream(type: s.type ?? "Video", codec: s.codec, displayTitle: s.displayTitle,
                            width: s.width, height: s.height, bitRate: s.bitRate, isDefault: s.isDefault ?? false)
            } ?? [],
            genres: genres ?? [],
            studios: studios?.map { $0.name } ?? [],
            officialRating: officialRating,
            runTimeTicks: runTimeTicks,
            taglines: taglines ?? []
        )
    }
}

private struct PersonResponse: Decodable {
    let id: String
    let name: String
    let role: String?
    let primaryImageTag: String?
    let type: String?
    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", role = "Role"
        case primaryImageTag = "PrimaryImageTag", type = "Type"
    }
}

private struct MediaStreamResponse: Decodable {
    let type: String?
    let codec: String?
    let displayTitle: String?
    let width: Int?
    let height: Int?
    let bitRate: Int?
    let isDefault: Bool?
    enum CodingKeys: String, CodingKey {
        case type = "Type", codec = "Codec", displayTitle = "DisplayTitle"
        case width = "Width", height = "Height", bitRate = "BitRate", isDefault = "IsDefault"
    }
}

private struct StudioResponse: Decodable {
    let name: String
    enum CodingKeys: String, CodingKey { case name = "Name" }
}

private struct LibraryViewsResponse: Decodable {
    let items: [LibraryViewItem]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct LibraryViewItem: Decodable {
    let id: String
    let name: String
    let collectionType: String?
    let imageTags: [String: String]?
    enum CodingKeys: String, CodingKey {
        case id = "Id"; case name = "Name"
        case collectionType = "CollectionType"; case imageTags = "ImageTags"
    }
}
