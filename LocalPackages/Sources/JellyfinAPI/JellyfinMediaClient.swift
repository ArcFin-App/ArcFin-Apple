import Foundation
import AuthCore

// MARK: - Image type

public enum JellyfinImageType: String, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case logo = "Logo"
    case thumb = "Thumb"
}

// MARK: - Public server info

public struct JellyfinPublicServerInfo: Decodable, Sendable {
    public let localAddress: String?
    public let serverName: String?
    public let version: String?
    public let productName: String?
    public let operatingSystem: String?
    public let id: String
    public let startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case localAddress = "LocalAddress"
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
        case operatingSystem = "OperatingSystem"
        case id = "Id"
        case startupWizardCompleted = "StartupWizardCompleted"
    }
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
        seriesId: String? = nil,
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
        if let seriesId { comps.queryItems?.append(.init(name: "SeriesId", value: seriesId)) }
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

    /// The original media file, for downloads — requires the signed-in account to have the
    /// "Allow media downloading" permission granted server-side; a 403 means it isn't.
    public static func originalFileDownloadURL(baseURL: URL, itemID: String, token: String) -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("Items/\(itemID)/Download"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "api_key", value: token)]
        return comps.url!
    }

    /// Containers AVFoundation can actually open locally — notably not Matroska. This is an
    /// iOS platform limitation (AVFoundation only supports the QuickTime/MP4 family), not
    /// something fixable client-side short of a full third-party demuxer.
    public static let avFoundationCompatibleContainers: Set<String> = ["mp4", "m4v", "mov"]

    /// Whether a download needs the server-side remux (forced to h264 output) rather than
    /// the original file verbatim. Container incompatibility is the obvious case; HEVC is
    /// the other one — sources are routinely tagged hev1 instead of the hvc1 AVFoundation
    /// requires, which plays audio with a black video screen, and originalFileDownloadURL
    /// serves the file byte-for-byte with whatever tag it already has. The online player
    /// sidesteps this for direct play by asking the server not to advertise mistagged hevc
    /// (see JellyfinPlaybackClient's DeviceProfile), but a download has no such negotiation —
    /// forcing the same h264 remux is the only way to guarantee it plays.
    public static func downloadNeedsRemux(container: String?, videoCodec: String?) -> Bool {
        let container = (container ?? "").lowercased()
        let videoCodec = (videoCodec ?? "").lowercased()
        return !avFoundationCompatibleContainers.contains(container) || videoCodec == "hevc"
    }

    /// A single progressively-downloadable file, remuxed (or transcoded, if the source codec
    /// itself needs it) into MP4 — used for downloads when the source container is
    /// something AVFoundation can't open (e.g. mkv), where originalFileDownloadURL's
    /// output would silently fail to play. Static=false with an .mp4 extension makes
    /// Jellyfin return a normal progressive stream, not HLS segments, so it downloads the
    /// same way as a plain file.
    public static func remuxDownloadURL(baseURL: URL, itemID: String, mediaSourceId: String, token: String) -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(itemID)/stream.mp4"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Static", value: "false"),
            .init(name: "mediaSourceId", value: mediaSourceId),
            .init(name: "VideoCodec", value: "h264"),
            .init(name: "AudioCodec", value: "aac"),
            .init(name: "api_key", value: token),
        ]
        return comps.url!
    }

    public static func userImageURL(baseURL: URL, userID: String, tag: String, fillWidth: Int = 100, token: String) -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("Users/\(userID)/Images/Primary"),
            resolvingAgainstBaseURL: false)!
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
                           primaryImageTag: $0.imageTags?["Primary"],
                           backdropImageTag: $0.backdropImageTags?.first)
        }
    }

    /// Fetch the Jellyfin server UUID (needed for Streamystats jellyfinServerId param).
    public func getServerID(credential: ServerCredential) async throws -> String {
        try await getPublicInfo(baseURL: credential.baseURL).id
    }

    /// GET /System/Info/Public — unauthenticated, used both for the server UUID and
    /// for the Server Settings screen's read-only server info display.
    public func getPublicInfo(baseURL: URL) async throws -> JellyfinPublicServerInfo {
        let url = baseURL.appendingPathComponent("System/Info/Public")
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(JellyfinPublicServerInfo.self, from: data)
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
            .init(name: "Fields", value: "Overview,People,MediaStreams,Genres,Studios,OfficialRating,RunTimeTicks,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating,SeriesName,SeriesId,SeriesPrimaryImageTag,Taglines,ProviderIds,Chapters,Trickplay"),
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

    /// Uses /Search/Hints rather than a plain /Items SearchTerm filter — Hints also
    /// matches on cast/crew names (searching an actor surfaces their filmography), which
    /// the plain Items text search only does against title/overview, not people metadata.
    public func search(credential: ServerCredential, authHeader: String, query: String, limit: Int = 20) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Search/Hints"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "searchTerm", value: query),
            .init(name: "includeItemTypes", value: "Movie,Series,Episode,BoxSet"),
            .init(name: "limit", value: "\(limit)"),
            .init(name: "includePeople", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        let page = try JSONDecoder().decode(SearchHintsResponse.self, from: data)
        return page.searchHints.compactMap { $0.toMediaItem() }
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
    let chapters: [ChapterResponse]?
    /// MediaSourceId -> width -> info. A completely different location from PlaybackInfo's
    /// MediaSources[].TrickplayInfo, which Jellyfin does not reliably populate — the general
    /// item-detail endpoint is the one that actually carries this.
    let trickplay: [String: [String: TrickplayInfoResponse]]?

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
        case chapters = "Chapters", trickplay = "Trickplay"
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
            taglines: taglines ?? [],
            chapters: chapters?.map { MediaChapter(startPositionTicks: $0.startPositionTicks, name: $0.name) } ?? [],
            trickplay: trickplay?.compactMapValues { $0.preferred } ?? [:]
        )
    }
}

private struct ChapterResponse: Decodable {
    let startPositionTicks: Int64
    let name: String?
    enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks", name = "Name"
    }
}

struct TrickplayInfoResponse: Decodable {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailCount: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case width = "Width", height = "Height"
        case tileWidth = "TileWidth", tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount", interval = "Interval"
    }

    var toTrickplayInfo: JellyfinTrickplayInfo {
        JellyfinTrickplayInfo(width: width, height: height, tileWidth: tileWidth,
                              tileHeight: tileHeight, thumbnailCount: thumbnailCount, intervalMs: interval)
    }
}

private extension [String: TrickplayInfoResponse] {
    /// Smallest available resolution per media source — this is only ever shown at
    /// thumbnail size, so a small, fast-loading image is preferable.
    var preferred: JellyfinTrickplayInfo? {
        values.min(by: { $0.width < $1.width })?.toTrickplayInfo
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

private struct SearchHintsResponse: Decodable {
    let searchHints: [SearchHintResponse]
    enum CodingKeys: String, CodingKey { case searchHints = "SearchHints" }
}

private struct SearchHintResponse: Decodable {
    let itemId: String
    let name: String
    let type: String
    let primaryImageTag: String?
    let thumbImageTag: String?
    let backdropImageTag: String?
    let productionYear: Int?
    let series: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId", name = "Name", type = "Type"
        case primaryImageTag = "PrimaryImageTag", thumbImageTag = "ThumbImageTag"
        case backdropImageTag = "BackdropImageTag", productionYear = "ProductionYear"
        case series = "Series", indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber"
    }

    /// Person hints (an actor/director entry itself, not a title) have no playable
    /// destination in this app yet — filtered out rather than shown as a dead tap target.
    func toMediaItem() -> MediaItem? {
        let mappedType: MediaType
        switch type {
        case "Movie":   mappedType = .movie
        case "Series":  mappedType = .series
        case "Episode": mappedType = .episode
        case "BoxSet":  mappedType = .boxSet
        default:        return nil
        }
        return MediaItem(
            id: itemId, name: name, type: mappedType,
            backdropImageTags: backdropImageTag.map { [$0] } ?? [],
            primaryImageTag: primaryImageTag,
            thumbImageTag: thumbImageTag,
            productionYear: productionYear,
            seriesName: series,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber
        )
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
    let backdropImageTags: [String]?
    enum CodingKeys: String, CodingKey {
        case id = "Id"; case name = "Name"
        case collectionType = "CollectionType"; case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
    }
}
