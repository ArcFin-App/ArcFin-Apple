// SPDX-License-Identifier: AGPL-3.0-or-later

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
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,CommunityRating,ParentBackdropImageTags,ParentBackdropItemId,RunTimeTicks,Genres"),
            .init(name: "ImageTypeLimit", value: "1"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "Recursive", value: "true"),
            .init(name: "IncludeItemTypes", value: itemTypes),
            .init(name: "Limit", value: "\(limit)"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
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
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId,RunTimeTicks,Genres"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImages", value: "true"),
        ]
        if let seriesId { comps.queryItems?.append(.init(name: "SeriesId", value: seriesId)) }
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
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
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,SeriesName,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId,RunTimeTicks,Genres"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
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
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// Titles the server considers similar to `itemId`, for "Because You Watched".
    public func getSimilar(
        credential: ServerCredential,
        authHeader: String,
        itemId: String,
        limit: Int = 24
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Items/\(itemId)/Similar"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// Random genres that actually have movies or shows, each with some unwatched titles —
    /// the "Comedy", "Thrillers" rows on Home. Genres with nothing unwatched are dropped.
    public func getGenreShelves(
        credential: ServerCredential,
        authHeader: String,
        genreCount: Int = 3,
        itemsPerGenre: Int = 16
    ) async throws -> [(genre: String, items: [MediaItem])] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Genres"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "IncludeItemTypes", value: "Movie,Series"),
            .init(name: "SortBy", value: "Random"),
            .init(name: "Limit", value: "\(genreCount + 2)"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let names = try JSONDecoder().decode(ItemsPage.self, from: data).items.map(\.name)

        var shelves: [(genre: String, items: [MediaItem])] = []
        for name in names where shelves.count < genreCount {
            var itemComps = URLComponents(
                url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
                resolvingAgainstBaseURL: false)!
            itemComps.queryItems = [
                .init(name: "Genres", value: name),
                .init(name: "IncludeItemTypes", value: "Movie,Series"),
                .init(name: "Recursive", value: "true"),
                .init(name: "Filters", value: "IsUnplayed"),
                .init(name: "SortBy", value: "Random"),
                .init(name: "Limit", value: "\(itemsPerGenre)"),
                .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear"),
                .init(name: "EnableUserData", value: "true"),
            ]
            var itemReq = URLRequest(url: itemComps.url!)
            itemReq.setValue(authHeader, forHTTPHeaderField: "Authorization")
            itemReq.timeoutInterval = 15
            guard let (itemData, _) = try? await URLSession.arcfin.data(for: itemReq),
                  let page = try? JSONDecoder().decode(ItemsPage.self, from: itemData),
                  page.items.count >= 4
            else { continue }
            shelves.append((name, page.items.map { $0.toMediaItem() }))
        }
        return shelves
    }

    /// Movies and series the user has favorited, for Home's Favorites shelf.
    public func getFavorites(
        credential: ServerCredential,
        authHeader: String,
        limit: Int = 20
    ) async throws -> [MediaItem] {
        try await getHomeShelfItems(
            credential: credential, authHeader: authHeader, limit: limit,
            extra: [.init(name: "Filters", value: "IsFavorite"),
                    .init(name: "SortBy", value: "SortName"),
                    .init(name: "SortOrder", value: "Ascending")])
    }

    /// Highly rated titles the user hasn't watched — "what should I watch tonight" picks.
    public func getTopRatedUnwatched(
        credential: ServerCredential,
        authHeader: String,
        limit: Int = 16
    ) async throws -> [MediaItem] {
        try await getHomeShelfItems(
            credential: credential, authHeader: authHeader, limit: limit,
            extra: [.init(name: "IsPlayed", value: "false"),
                    .init(name: "MinCommunityRating", value: "7"),
                    .init(name: "SortBy", value: "CommunityRating"),
                    .init(name: "SortOrder", value: "Descending")])
    }

    private func getHomeShelfItems(
        credential: ServerCredential,
        authHeader: String,
        limit: Int,
        extra: [URLQueryItem]
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "IncludeItemTypes", value: "Movie,Series"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,CommunityRating"),
            .init(name: "EnableUserData", value: "true"),
        ] + extra
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
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
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,SeriesName,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId,RunTimeTicks,Genres"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "IncludeItemTypes", value: "Movie,Episode"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let page = try JSONDecoder().decode(ItemsPage.self, from: data)
        return page.items.map { $0.toMediaItem() }
    }

    /// The same image at its original size, or nil when the URL asks for no resize.
    public static func unresizedImageURL(_ url: URL) -> URL? {
        let resizeParams: Set<String> = ["fillWidth", "fillHeight", "maxWidth", "maxHeight", "quality"]
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, items.contains(where: { resizeParams.contains($0.name) })
        else { return nil }
        comps.queryItems = items.filter { !resizeParams.contains($0.name) }
        return comps.url
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

    /// A single progressively-downloadable file, remuxed (or transcoded, if the source codec
    /// itself needs it) into MP4 — used for downloads when the source container is
    /// something AVFoundation can't open (e.g. mkv), where originalFileDownloadURL's
    /// output would silently fail to play. Static=false with an .mp4 extension makes
    /// Jellyfin return a normal progressive stream, not HLS segments, so it downloads the
    /// same way as a plain file.
    ///
    /// VideoBitRate must be passed explicitly — without it Jellyfin's transcoder falls back
    /// to a low default bitrate regardless of source quality, which is what actually made
    /// remuxed downloads look bad, not the codec change itself. Callers decide the value:
    /// source bitrate (with a generous fallback) for an unrequested remux, or the user's
    /// own picked cap when they deliberately asked for a smaller download.
    public static func remuxDownloadURL(baseURL: URL, itemID: String, mediaSourceId: String, videoBitRate: Int, token: String) -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("Videos/\(itemID)/stream.mp4"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Static", value: "false"),
            .init(name: "mediaSourceId", value: mediaSourceId),
            .init(name: "VideoCodec", value: "h264"),
            .init(name: "AudioCodec", value: "aac"),
            .init(name: "VideoBitRate", value: "\(videoBitRate)"),
            .init(name: "AudioBitRate", value: "320000"),
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
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let page = try JSONDecoder().decode(LibraryViewsResponse.self, from: data)
        return page.items.map {
            JellyfinLibrary(id: $0.id, name: $0.name,
                           collectionType: JellyfinLibrary.LibraryType(apiValue: $0.collectionType ?? ""),
                           primaryImageTag: $0.imageTags?["Primary"],
                           backdropImageTag: $0.backdropImageTags?.first)
        }
    }

    /// How many titles of its main kind a library holds: movies, shows, collections and so on.
    /// Asks for the total only (`Limit=0`).
    public func getLibraryItemCount(credential: ServerCredential, authHeader: String, library: JellyfinLibrary) async throws -> Int {
        if library.collectionType == .livetv {
            return try await getLiveTVChannelCount(credential: credential, authHeader: authHeader)
        }
        let itemTypes: String = switch library.collectionType {
        case .movies: "Movie"
        case .tvshows: "Series"
        case .boxsets: "BoxSet"
        case .playlists: "Playlist"
        case .homevideos: "Video"
        case .photos: "Photo"
        case .books: "Book"
        case .music: "MusicAlbum"
        case .livetv, .unknown: "Movie,Series"
        }
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "ParentId", value: library.id),
            .init(name: "IncludeItemTypes", value: itemTypes),
            .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "0"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).totalRecordCount ?? 0
    }

    /// The Jellyfin server's UUID, from its public info.
    public func getServerID(credential: ServerCredential) async throws -> String {
        try await getPublicInfo(baseURL: credential.baseURL).id
    }

    /// GET /System/Info/Public — unauthenticated, used both for the server UUID and
    /// for the Server Settings screen's read-only server info display.
    public func getPublicInfo(baseURL: URL) async throws -> JellyfinPublicServerInfo {
        let url = baseURL.appendingPathComponent("System/Info/Public")
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(JellyfinPublicServerInfo.self, from: data)
    }

    public func getItemDetail(
        credential: ServerCredential,
        authHeader: String,
        itemId: String
    ) async throws -> MediaItemDetail {
        try Self.decodeItemDetail(await getItemDetailData(credential: credential, authHeader: authHeader, itemId: itemId))
    }

    /// The server's response as is, so a download can keep it and show the full page offline.
    public func getItemDetailData(
        credential: ServerCredential,
        authHeader: String,
        itemId: String
    ) async throws -> Data {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/\(itemId)"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Fields", value: "Overview,People,MediaStreams,Genres,Studios,OfficialRating,RunTimeTicks,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating,SeriesName,SeriesId,SeriesPrimaryImageTag,Taglines,ProviderIds,Chapters,Trickplay,RemoteTrailers,OriginalTitle,ProductionLocations,ExternalUrls,Tags,MediaSources,AirTime"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return data
    }

    public static func decodeItemDetail(_ data: Data) throws -> MediaItemDetail {
        try JSONDecoder().decode(ItemDetailResponse.self, from: data).toDetail()
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
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// Server-wide "recommended movies" categories (e.g. "because you watched X", "more with
    /// an actor you like") — NOT scoped to one item; Jellyfin has no per-movie recommendations
    /// endpoint, only this library-wide one. Callers that want something tied to a specific
    /// movie should filter the returned categories by baselineItemName.
    public func getMovieRecommendations(
        credential: ServerCredential,
        authHeader: String,
        categoryLimit: Int = 5,
        itemLimit: Int = 8
    ) async throws -> [MovieRecommendationCategory] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Movies/Recommendations"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "userId", value: credential.userID),
            .init(name: "categoryLimit", value: "\(categoryLimit)"),
            .init(name: "itemLimit", value: "\(itemLimit)"),
            .init(name: "fields", value: "Overview,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode([MovieRecommendationResponse].self, from: data).map { $0.toCategory() }
    }

    /// The server's own picks for this user, from what they've watched and liked.
    public func getSuggestions(credential: ServerCredential, authHeader: String, limit: Int = 20) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Items/Suggestions"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "userId", value: credential.userID),
            .init(name: "type", value: "Movie"),
            .init(name: "type", value: "Series"),
            .init(name: "limit", value: "\(limit)"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// Other titles credited to a person (actor/director/writer), in the user's library.
    public func getPersonItems(
        credential: ServerCredential,
        authHeader: String,
        personId: String,
        limit: Int = 50
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "PersonIds", value: personId),
            .init(name: "Recursive", value: "true"),
            .init(name: "IncludeItemTypes", value: "Movie,Series"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating,ProviderIds"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// The library's own copy of a TMDB title (Seerr identifies media by TMDB id), or nil when
    /// the server doesn't have it. Tries the item's ProviderIds first; when the library's
    /// metadata never stored a TMDB id, falls back to an exact (normalized) title match
    /// within a year of `year`, so a missing id doesn't hide a title that is really there.
    /// Either lookup returns nil rather than guess when it finds more than one candidate.
    public func findItem(
        credential: ServerCredential,
        authHeader: String,
        tmdbId: Int,
        isSeries: Bool,
        title: String? = nil,
        year: Int? = nil
    ) async throws -> MediaItem? {
        if let byId = try await findItemByProviderId(
            credential: credential, authHeader: authHeader, tmdbId: tmdbId, isSeries: isSeries) {
            return byId
        }
        guard let title, !title.isEmpty else { return nil }
        return try await findItemByTitle(
            credential: credential, authHeader: authHeader, title: title, year: year, isSeries: isSeries)
    }

    private func findItemByTitle(
        credential: ServerCredential,
        authHeader: String,
        title: String,
        year: Int?,
        isSeries: Bool
    ) async throws -> MediaItem? {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "SearchTerm", value: title),
            .init(name: "Recursive", value: "true"),
            .init(name: "IncludeItemTypes", value: isSeries ? "Series" : "Movie"),
            .init(name: "Limit", value: "10"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating,ProviderIds"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let candidates = try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
        func normalized(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let wanted = normalized(title)
        let matches = candidates.filter { candidate in
            guard normalized(candidate.name) == wanted else { return false }
            guard let year, let candidateYear = candidate.productionYear else { return true }
            return abs(candidateYear - year) <= 1
        }
        // More than one plausible match means a guess — better no button than the wrong title.
        return matches.count == 1 ? matches.first : nil
    }

    /// The key `getLibraryTMDBKeys` stores a title under.
    public static func libraryKey(tmdbId: Int, isSeries: Bool) -> String {
        "\(isSeries ? "tv" : "movie"):\(tmdbId)"
    }

    /// Every movie and show in the library that has a TMDB id, as `libraryKey`s, so a list of
    /// Seerr titles (identified by TMDB id) can be told which of them the server already has.
    /// Ids only, without images or user data, to keep a large library's answer small.
    public func getLibraryTMDBKeys(credential: ServerCredential, authHeader: String) async throws -> Set<String> {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "IncludeItemTypes", value: "Movie,Series"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Fields", value: "ProviderIds"),
            .init(name: "EnableImages", value: "false"),
            .init(name: "EnableUserData", value: "false"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let items = try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
        return Set(items.compactMap { item in
            item.tmdbId.map { Self.libraryKey(tmdbId: $0, isSeries: item.type == .series) }
        })
    }

    private func findItemByProviderId(
        credential: ServerCredential,
        authHeader: String,
        tmdbId: Int,
        isSeries: Bool
    ) async throws -> MediaItem? {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "AnyProviderIdEquals", value: "tmdb.\(tmdbId)"),
            .init(name: "Recursive", value: "true"),
            .init(name: "IncludeItemTypes", value: isSeries ? "Series" : "Movie"),
            .init(name: "Limit", value: "2"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ProductionYear,CommunityRating,ProviderIds"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let items = try JSONDecoder().decode(ItemsPage.self, from: data).items
        return items.count == 1 ? items.first?.toMediaItem() : nil
    }

    /// A Person is a regular Jellyfin item under the hood, fetched the same way as a
    /// movie/series — just a much smaller field set. Separate from getItemDetail/
    /// MediaItemDetail (which decodes many movie/series-only fields a Person never has)
    /// rather than overloading that type for a different kind of thing.
    public func getPersonDetail(
        credential: ServerCredential,
        authHeader: String,
        personId: String
    ) async throws -> MediaPersonDetail {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/\(personId)"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Fields", value: "Overview,ProviderIds,PremiereDate"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(PersonDetailResponse.self, from: data).toDetail()
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
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    public func getEpisodes(
        credential: ServerCredential,
        authHeader: String,
        seriesId: String,
        seasonId: String?
    ) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Shows/\(seriesId)/Episodes"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "Fields", value: "Overview,PremiereDate,UserData,PrimaryImageTags,BackdropImageTags,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImages", value: "true"),
            .init(name: "ImageTypeLimit", value: "1"),
        ]
        // Without a season, every episode of the series in season and episode order.
        if let seasonId { comps.queryItems?.append(.init(name: "SeasonId", value: seasonId)) }
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// The series' next episode to watch and the ones after it, in order. Next Up itself only
    /// ever returns one episode per series, whatever the limit.
    public func getUpcomingEpisodes(
        credential: ServerCredential,
        authHeader: String,
        seriesId: String,
        count: Int
    ) async throws -> [MediaItem] {
        guard let next = try await getNextEpisode(credential: credential, authHeader: authHeader, seriesId: seriesId) else {
            // Next Up leaves out shows past the server's Next Up cutoff, shows with nothing
            // watched yet on some versions, and shows with a later season marked watched.
            let all = try await getEpisodes(credential: credential, authHeader: authHeader, seriesId: seriesId, seasonId: nil)
            return Self.upcoming(in: all, count: count)
        }
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Shows/\(seriesId)/Episodes"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "StartItemId", value: next.id),
            .init(name: "Limit", value: "\(count)"),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let episodes = try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
        return episodes.isEmpty ? [next] : episodes.filter { $0.userData?.played != true }
    }

    /// From a series' full episode list, the unwatched episodes after the one watched most
    /// recently (or, without dates, after the last one marked watched). Next Up goes from the
    /// furthest episode marked watched instead, so a show with later seasons marked watched
    /// from an earlier run had nothing up next. Specials are left out.
    public static func upcoming(in all: [MediaItem], count: Int) -> [MediaItem] {
        let played = all.indices.filter { all[$0].userData?.played == true && all[$0].parentIndexNumber != 0 }
        let latest = played.compactMap { i in all[i].userData?.lastPlayedDate.map { (i, $0) } }.max { $0.1 < $1.1 }?.0
        let start = (latest ?? played.last).map { $0 + 1 } ?? 0
        return Array(all.dropFirst(start).filter { $0.userData?.played != true && $0.parentIndexNumber != 0 }.prefix(count))
    }

    /// Next Up, plus the shows it leaves out that were watched lately: one with a later season
    /// marked watched gets the episode after the one watched most recently, in the place its
    /// last watch puts it.
    public func getNextUpIncludingRecent(
        credential: ServerCredential,
        authHeader: String,
        limit: Int = 12
    ) async throws -> [MediaItem] {
        async let serverNextUp = getNextUp(credential: credential, authHeader: authHeader, limit: limit)
        let recent = (try? await getRecentlyPlayedEpisodes(credential: credential, authHeader: authHeader)) ?? []
        var items = try await serverNextUp
        let recentSeries = recent.compactMap(\.seriesId).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let covered = Set(items.compactMap(\.seriesId))
        for seriesId in recentSeries.filter({ !covered.contains($0) }).prefix(3) {
            // One already part-way through is in Continue Watching instead.
            guard let next = try? await getUpcomingEpisodes(credential: credential, authHeader: authHeader, seriesId: seriesId, count: 1).first,
                  (next.userData?.playbackPositionTicks ?? 0) == 0 else { continue }
            items.append(next)
        }
        let rank = Dictionary(recentSeries.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = items.enumerated().sorted {
            let a = $0.element.seriesId.flatMap { rank[$0] } ?? Int.max
            let b = $1.element.seriesId.flatMap { rank[$0] } ?? Int.max
            return a != b ? a < b : $0.offset < $1.offset
        }
        return Array(ordered.map(\.element).prefix(limit))
    }

    /// Episodes finished lately, newest first, for the shows being watched now.
    private func getRecentlyPlayedEpisodes(credential: ServerCredential, authHeader: String) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Recursive", value: "true"),
            .init(name: "IncludeItemTypes", value: "Episode"),
            .init(name: "Filters", value: "IsPlayed"),
            .init(name: "SortBy", value: "DatePlayed"),
            .init(name: "SortOrder", value: "Descending"),
            .init(name: "Limit", value: "40"),
            .init(name: "Fields", value: "SeriesId,UserData"),
            .init(name: "EnableImages", value: "false"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        // Older than Jellyfin's own Next Up cutoff (a year) isn't being watched now.
        let cutoff = Date().addingTimeInterval(-365 * 24 * 3600)
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
            .filter { ($0.userData?.lastPlayedDate ?? .distantFuture) > cutoff }
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
        let (data, _) = try await URLSession.arcfin.data(for: req)
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
        _ = try await URLSession.arcfin.data(for: req)
    }

    /// Jellyfin has no dedicated "remove from Continue Watching" call — zeroing the saved
    /// position is what its own web client does, and it drops the item from the shelf
    /// without marking it watched.
    public func clearResumePosition(
        credential: ServerCredential,
        authHeader: String,
        itemId: String
    ) async throws {
        let url = credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/\(itemId)/UserData")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["PlaybackPositionTicks": 0])
        req.timeoutInterval = 15
        _ = try await URLSession.arcfin.data(for: req)
    }

    /// Writes a resume position and watched state straight to the user's data for an item —
    /// how progress recorded offline is handed back, since a late "playback stopped" report
    /// isn't reliably applied to an item that has no session playing it.
    public func updateUserData(
        credential: ServerCredential,
        authHeader: String,
        itemId: String,
        positionTicks: Int64,
        played: Bool,
        lastPlayed: Date = Date()
    ) async throws {
        let url = credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/\(itemId)/UserData")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "PlaybackPositionTicks": played ? 0 : positionTicks,
            "Played": played,
            "LastPlayedDate": ISO8601DateFormatter().string(from: lastPlayed),
        ])
        req.timeoutInterval = 15
        let (_, response) = try await URLSession.arcfin.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
    }

    /// Position and watched state for many items in a few requests, keyed by item id.
    public func getUserData(credential: ServerCredential, authHeader: String, itemIds: [String]) async throws -> [String: UserData] {
        var result: [String: UserData] = [:]
        for start in stride(from: 0, to: itemIds.count, by: 100) {
            let ids = itemIds[start..<min(start + 100, itemIds.count)]
            var comps = URLComponents(
                url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
                resolvingAgainstBaseURL: false)!
            comps.queryItems = [
                .init(name: "Ids", value: ids.joined(separator: ",")),
                .init(name: "EnableUserData", value: "true"),
                .init(name: "EnableImages", value: "false"),
            ]
            var req = URLRequest(url: comps.url!)
            req.setValue(authHeader, forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 15
            let (data, response) = try await URLSession.arcfin.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            for item in try JSONDecoder().decode(ItemsPage.self, from: data).items {
                if let userData = item.toMediaItem().userData { result[item.id] = userData }
            }
        }
        return result
    }

    /// An item's resume position and watched state for this user, if the server answers.
    public func getUserData(credential: ServerCredential, authHeader: String, itemId: String) async throws -> UserData? {
        let url = credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/\(itemId)")
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 4
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode(JellyfinItemResponse.self, from: data).toMediaItem().userData
    }

    public func markFavorite(
        credential: ServerCredential,
        authHeader: String,
        itemId: String,
        favorite: Bool
    ) async throws {
        let url = credential.baseURL.appendingPathComponent("Users/\(credential.userID)/FavoriteItems/\(itemId)")
        var req = URLRequest(url: url)
        req.httpMethod = favorite ? "POST" : "DELETE"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        _ = try await URLSession.arcfin.data(for: req)
    }

    /// Thumbs rating: `true` likes, `false` dislikes, `nil` clears it.
    public func setRating(
        credential: ServerCredential,
        authHeader: String,
        itemId: String,
        likes: Bool?
    ) async throws {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items/\(itemId)/Rating"),
            resolvingAgainstBaseURL: false)!
        if let likes {
            comps.queryItems = [.init(name: "likes", value: likes ? "true" : "false")]
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = likes == nil ? "DELETE" : "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        _ = try await URLSession.arcfin.data(for: req)
    }

    public func getLibraryItems(
        credential: ServerCredential,
        authHeader: String,
        libraryId: String,
        startIndex: Int = 0,
        limit: Int = 100,
        recursive: Bool = true,
        includeItemTypes: String? = nil,
        genres: [String] = [],
        requireAllGenres: Bool = false,
        years: [Int] = [],
        officialRatings: [String] = [],
        minCommunityRating: Double? = nil,
        tags: [String] = [],
        isHD: Bool? = nil,
        is4K: Bool? = nil,
        hasSubtitles: Bool? = nil,
        isPlayed: Bool? = nil,
        isFavorite: Bool? = nil,
        nameLessThan: String? = nil,
        sortBy: String = "SortName",
        sortOrder: String = "Ascending"
    ) async throws -> (items: [MediaItem], total: Int, consumed: Int) {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        // An empty libraryId searches everything the user can see (e.g. every playlist).
        var queryItems: [URLQueryItem] = (libraryId.isEmpty ? [] : [.init(name: "ParentId", value: libraryId)]) + [
            .init(name: "Recursive", value: recursive ? "true" : "false"),
            .init(name: "SortBy", value: sortBy),
            .init(name: "SortOrder", value: sortOrder),
            .init(name: "StartIndex", value: "\(startIndex)"),
            .init(name: "Limit", value: "\(limit)"),
            .init(name: "Fields", value: "Overview,Genres,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,CommunityRating,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableTotalRecordCount", value: "true"),
        ]
        if let types = includeItemTypes {
            queryItems.append(.init(name: "IncludeItemTypes", value: types))
        }
        if !genres.isEmpty {
            queryItems.append(.init(name: "Genres", value: genres.joined(separator: "|")))
        }
        if !years.isEmpty {
            queryItems.append(.init(name: "Years", value: years.map(String.init).joined(separator: ",")))
        }
        if !officialRatings.isEmpty {
            queryItems.append(.init(name: "OfficialRatings", value: officialRatings.joined(separator: "|")))
        }
        if let minCommunityRating {
            queryItems.append(.init(name: "MinCommunityRating", value: String(minCommunityRating)))
        }
        if !tags.isEmpty {
            queryItems.append(.init(name: "Tags", value: tags.joined(separator: "|")))
        }
        if let isHD {
            queryItems.append(.init(name: "IsHD", value: isHD ? "true" : "false"))
        }
        if let is4K {
            queryItems.append(.init(name: "Is4K", value: is4K ? "true" : "false"))
        }
        if let hasSubtitles {
            queryItems.append(.init(name: "HasSubtitles", value: hasSubtitles ? "true" : "false"))
        }
        if let isPlayed {
            queryItems.append(.init(name: "IsPlayed", value: isPlayed ? "true" : "false"))
        }
        if let isFavorite {
            queryItems.append(.init(name: "IsFavorite", value: isFavorite ? "true" : "false"))
        }
        if let nameLessThan {
            queryItems.append(.init(name: "NameLessThan", value: nameLessThan))
        }
        comps.queryItems = queryItems
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let page = try JSONDecoder().decode(ItemsPage.self, from: data)
        // The server's Genres filter is "any of"; narrowing to "all of" happens here, so
        // `consumed` reports how many server rows were read for paging.
        let rows = requireAllGenres && genres.count > 1
            ? page.items.filter { Set(genres).isSubset(of: $0.genres ?? []) }
            : page.items
        return (items: rows.map { $0.toMediaItem() }, total: page.totalRecordCount ?? 0, consumed: page.items.count)
    }

    /// Available filter facets (genres/years) for a library — from /Items/Filters2, scoped
    /// to what's actually present under this ParentId rather than a global, mostly-empty list.
    public func getLibraryFilterOptions(
        credential: ServerCredential,
        authHeader: String,
        libraryId: String,
        includeItemTypes: String? = nil
    ) async throws -> (genres: [String], years: [Int], officialRatings: [String], tags: [String]) {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Items/Filters2"),
            resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = libraryId.isEmpty ? [] : [.init(name: "ParentId", value: libraryId)]
        if let types = includeItemTypes {
            queryItems.append(.init(name: "IncludeItemTypes", value: types))
        }
        comps.queryItems = queryItems
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let response = try JSONDecoder().decode(LibraryFiltersResponse.self, from: data)
        return (genres: response.genres.map(\.name).sorted(), years: response.years.sorted(by: >),
                officialRatings: (response.officialRatings ?? []).sorted(),
                tags: (response.tags ?? []).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
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
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let page = try JSONDecoder().decode(SearchHintsResponse.self, from: data)
        var results = page.searchHints.compactMap { $0.toMediaItem() }

        // Search/Hints' own schema has no SeriesId/SeriesPrimaryImageTag (only a plain
        // Series name string) — episode results would otherwise have no way to show their
        // series' portrait poster instead of the episode's own landscape screenshot. One
        // batched follow-up call (by id, not per-episode) fills that in when there are any.
        let episodeIds = results.filter { $0.type == .episode }.map(\.id)
        if !episodeIds.isEmpty,
           let seriesInfo = try? await episodeSeriesPosterInfo(credential: credential, authHeader: authHeader, episodeIds: episodeIds) {
            for i in results.indices {
                guard let info = seriesInfo[results[i].id] else { continue }
                results[i].seriesId = info.seriesId
                results[i].seriesPrimaryImageTag = info.seriesPrimaryImageTag
            }
        }
        return results
    }

    private func episodeSeriesPosterInfo(
        credential: ServerCredential,
        authHeader: String,
        episodeIds: [String]
    ) async throws -> [String: (seriesId: String?, seriesPrimaryImageTag: String?)] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "Ids", value: episodeIds.joined(separator: ",")),
            .init(name: "Fields", value: "SeriesId,SeriesPrimaryImageTag"),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let page = try JSONDecoder().decode(ItemsPage.self, from: data)
        return Dictionary(uniqueKeysWithValues: page.items.map { item in
            (item.id, (seriesId: item.seriesId, seriesPrimaryImageTag: item.seriesPrimaryImageTag))
        })
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
        let (data, _) = try await URLSession.arcfin.data(for: req)
        let items = (try? JSONDecoder().decode([JellyfinItemResponse].self, from: data)) ?? []
        return Array(items.prefix(limit).map { $0.toMediaItem() })
    }
}

// MARK: - Private response types

struct ItemsPage: Decodable {
    let items: [JellyfinItemResponse]
    let totalRecordCount: Int?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

private struct LibraryFiltersResponse: Decodable {
    /// Servers differ: Filters2 sends genres as `{Name, Id}` objects, older/legacy ones as
    /// plain strings. One odd shape must not blank out every facet.
    struct NamedFacet: Decodable {
        let name: String
        init(from decoder: Decoder) throws {
            if let plain = try? decoder.singleValueContainer().decode(String.self) {
                name = plain
            } else {
                name = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .name)
            }
        }
        enum CodingKeys: String, CodingKey { case name = "Name" }
    }
    let genres: [NamedFacet]
    let years: [Int]
    let officialRatings: [String]?
    let tags: [String]?
    enum CodingKeys: String, CodingKey {
        case tags = "Tags"
        case genres = "Genres"
        case years = "Years"
        case officialRatings = "OfficialRatings"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        genres = (try? c.decodeIfPresent([NamedFacet].self, forKey: .genres)) ?? []
        years = (try? c.decodeIfPresent([Int].self, forKey: .years)) ?? []
        officialRatings = try? c.decodeIfPresent([String].self, forKey: .officialRatings)
        tags = try? c.decodeIfPresent([String].self, forKey: .tags)
    }
}

struct JellyfinItemResponse: Decodable {
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
    let providerIds: [String: String]?
    let genres: [String]?
    let runTimeTicks: Int64?
    let premiereDate: String?
    let locationType: String?

    enum CodingKeys: String, CodingKey {
        case premiereDate = "PremiereDate"
        case locationType = "LocationType"
        case genres = "Genres"
        case runTimeTicks = "RunTimeTicks"
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
        case providerIds = "ProviderIds"
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
                    playedPercentage: $0.playedPercentage,
                    likes: $0.likes,
                    lastPlayedDate: $0.lastPlayed
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
            parentBackdropImageTags: parentBackdropImageTags ?? [],
            tmdbId: providerIds.flatMap { Int($0["Tmdb"] ?? "") },
            premiereDate: premiereDate.flatMap(Self.parseDay),
            runTimeTicks: runTimeTicks,
            genres: genres ?? [],
            isVirtual: locationType == "Virtual"
        )
    }

    /// Jellyfin sends 7-digit fractional seconds that ISO8601DateFormatter is unreliable
    /// with; only the calendar day matters here, so just that prefix is parsed.
    private static func parseDay(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: String(raw.prefix(10)))
    }
}

/// Jellyfin writes seven fractional digits, which ISO8601DateFormatter won't read.
enum JellyfinDate {
    static func parse(_ raw: String) -> Date? {
        var text = raw
        if let dot = text.firstIndex(of: "."), let end = text[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let fraction = text[text.index(after: dot)..<end]
            text.replaceSubrange(dot..<end, with: "." + fraction.prefix(3))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func string(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

struct UserDataResponse: Decodable {
    let playbackPositionTicks: Int64?
    let playCount: Int?
    let isFavorite: Bool?
    let played: Bool?
    let playedPercentage: Double?
    let likes: Bool?
    let lastPlayedDate: String?

    var lastPlayed: Date? { lastPlayedDate.flatMap(JellyfinDate.parse) }

    enum CodingKeys: String, CodingKey {
        case likes = "Likes"
        case lastPlayedDate = "LastPlayedDate"
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
    let remoteTrailers: [RemoteTrailerResponse]?
    let criticRating: Double?
    let originalTitle: String?
    let productionLocations: [String]?
    let tags: [String]?
    let status: String?
    let airDays: [String]?
    let airTime: String?
    let premiereDate: String?
    let endDate: String?
    let externalUrls: [ExternalUrlResponse]?
    let mediaSources: [MediaSourceSummary]?
    let locationType: String?

    struct ExternalUrlResponse: Decodable {
        let name: String?
        let url: String?
        enum CodingKeys: String, CodingKey { case name = "Name", url = "Url" }
    }

    struct MediaSourceSummary: Decodable {
        let id: String
        let name: String?
        let container: String?
        let size: Int64?
        let bitrate: Int?
        enum CodingKeys: String, CodingKey { case id = "Id", name = "Name", container = "Container", size = "Size", bitrate = "Bitrate" }
    }

    enum CodingKeys: String, CodingKey {
        case criticRating = "CriticRating", originalTitle = "OriginalTitle"
        case productionLocations = "ProductionLocations", tags = "Tags", status = "Status"
        case airDays = "AirDays", airTime = "AirTime", premiereDate = "PremiereDate", endDate = "EndDate"
        case externalUrls = "ExternalUrls", mediaSources = "MediaSources", locationType = "LocationType"
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
        case remoteTrailers = "RemoteTrailers"
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
                         playedPercentage: ud.playedPercentage,
                         likes: ud.likes,
                         lastPlayedDate: ud.lastPlayed)
            },
            productionYear: productionYear,
            communityRating: communityRating,
            seriesName: seriesName,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber,
            seriesId: seriesId,
            seriesPrimaryImageTag: seriesPrimaryImageTag,
            tmdbId: providerIds.flatMap { Int($0["Tmdb"] ?? "") },
            premiereDate: premiereDate.flatMap(Self.parseDay),
            isVirtual: locationType == "Virtual"
        )
        var detail = MediaItemDetail(
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
            trickplay: trickplay?.compactMapValues { $0.preferred } ?? [:],
            remoteTrailers: remoteTrailers?.compactMap { t in
                t.url.flatMap { URL(string: $0) }.map { RemoteTrailer(url: $0, name: t.name) }
            } ?? [],
            criticRating: criticRating
        )
        detail.originalTitle = originalTitle
        detail.productionLocations = productionLocations ?? []
        detail.tags = tags ?? []
        detail.status = status
        detail.airDays = airDays ?? []
        detail.airTime = airTime
        detail.premiereDate = premiereDate.flatMap(Self.parseDay)
        detail.endDate = endDate.flatMap(Self.parseDay)
        detail.externalLinks = (externalUrls ?? []).compactMap { link in
            guard let name = link.name, let url = link.url.flatMap(URL.init(string:)) else { return nil }
            return ExternalLink(name: name, url: url)
        }
        detail.files = (mediaSources ?? []).map {
            MediaFileInfo(id: $0.id, name: $0.name, container: $0.container, sizeBytes: $0.size, bitrate: $0.bitrate)
        }
        return detail
    }

    private static func parseDay(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: String(raw.prefix(10)))
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

private struct PersonDetailResponse: Decodable {
    let id: String
    let overview: String?
    let providerIds: [String: String]?
    let premiereDate: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", overview = "Overview"
        case providerIds = "ProviderIds", premiereDate = "PremiereDate"
    }

    func toDetail() -> MediaPersonDetail {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        return MediaPersonDetail(
            id: id,
            overview: (overview?.isEmpty ?? true) ? nil : overview,
            tmdbId: providerIds.flatMap { Int($0["Tmdb"] ?? "") },
            birthDate: premiereDate.flatMap {
                fractionalFormatter.date(from: $0) ?? plainFormatter.date(from: $0)
            }
        )
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
    let thumbImageItemId: String?
    let backdropImageTag: String?
    let backdropImageItemId: String?
    let productionYear: Int?
    let series: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId", name = "Name", type = "Type"
        case primaryImageTag = "PrimaryImageTag", thumbImageTag = "ThumbImageTag"
        case thumbImageItemId = "ThumbImageItemId", backdropImageItemId = "BackdropImageItemId"
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
        // An episode's thumb and backdrop are usually the series' own, named by these ids;
        // read as the episode's they asked for images it doesn't have and loaded nothing.
        let ownsThumb = thumbImageItemId == nil || thumbImageItemId == itemId
        let ownsBackdrop = backdropImageItemId == nil || backdropImageItemId == itemId
        return MediaItem(
            id: itemId, name: name, type: mappedType,
            backdropImageTags: ownsBackdrop ? backdropImageTag.map { [$0] } ?? [] : [],
            primaryImageTag: primaryImageTag,
            thumbImageTag: ownsThumb ? thumbImageTag : nil,
            productionYear: productionYear,
            seriesName: series,
            indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber,
            parentBackdropItemId: ownsBackdrop ? nil : backdropImageItemId,
            parentBackdropImageTags: ownsBackdrop ? [] : backdropImageTag.map { [$0] } ?? []
        )
    }
}

private struct StudioResponse: Decodable {
    let name: String
    enum CodingKeys: String, CodingKey { case name = "Name" }
}

private struct RemoteTrailerResponse: Decodable {
    let url: String?
    let name: String?
    enum CodingKeys: String, CodingKey { case url = "Url", name = "Name" }
}

private struct MovieRecommendationResponse: Decodable {
    let items: [JellyfinItemResponse]?
    let recommendationType: String
    let baselineItemName: String?
    let categoryId: String

    enum CodingKeys: String, CodingKey {
        case items = "Items", recommendationType = "RecommendationType"
        case baselineItemName = "BaselineItemName", categoryId = "CategoryId"
    }

    func toCategory() -> MovieRecommendationCategory {
        MovieRecommendationCategory(
            id: categoryId,
            recommendationType: recommendationType,
            baselineItemName: baselineItemName,
            items: items?.map { $0.toMediaItem() } ?? []
        )
    }
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
