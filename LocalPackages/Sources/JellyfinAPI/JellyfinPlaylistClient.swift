// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

public struct MediaPlaylist: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var itemCount: Int
    public var primaryImageTag: String?

    public init(id: String, name: String, itemCount: Int, primaryImageTag: String? = nil) {
        self.id = id
        self.name = name
        self.itemCount = itemCount
        self.primaryImageTag = primaryImageTag
    }
}

/// One row of a playlist. `entryId` is the playlist's own id for that row, which removal and
/// reordering need; the same title can appear twice with two different entry ids.
public struct PlaylistEntry: Sendable, Identifiable, Equatable, Hashable {
    public var id: String { entryId }
    public let entryId: String
    public let item: MediaItem
}

/// A subtitle file one of the server's subtitle providers (e.g. the OpenSubtitles plugin)
/// can fetch for an item.
public struct RemoteSubtitle: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let providerName: String?
    public let format: String?
    public let author: String?
    public let downloadCount: Int?
    public let communityRating: Double?
    public let isHashMatch: Bool
    public let isForced: Bool
    public let isHearingImpaired: Bool
    public let isMachineTranslated: Bool
}

public enum JellyfinRequestError: Error, LocalizedError, Sendable {
    case status(Int)

    public var errorDescription: String? {
        switch self {
        case .status(401), .status(403): "Your account doesn't have permission to do that on this server."
        case .status(404): "The server couldn't find that item."
        case .status(let code): "The server returned an error (HTTP \(code))."
        }
    }
}

extension JellyfinMediaClient {

    // MARK: - Playlists

    public func getPlaylists(credential: ServerCredential, authHeader: String) async throws -> [MediaPlaylist] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "IncludeItemTypes", value: "Playlist"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "Fields", value: "ChildCount,PrimaryImageAspectRatio"),
        ]
        let data = try await send(request(comps.url!, authHeader: authHeader))
        return try JSONDecoder().decode(PlaylistsPage.self, from: data).items.map {
            MediaPlaylist(id: $0.id, name: $0.name, itemCount: $0.childCount ?? 0, primaryImageTag: $0.imageTags?["Primary"])
        }
    }

    /// The user's collections.
    public func getCollections(credential: ServerCredential, authHeader: String) async throws -> [MediaItem] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "IncludeItemTypes", value: "BoxSet"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "Fields", value: "PrimaryImageTags,BackdropImageTags,ProductionYear"),
            .init(name: "EnableUserData", value: "false"),
        ]
        let data = try await send(request(comps.url!, authHeader: authHeader))
        return try JSONDecoder().decode(ItemsPage.self, from: data).items.map { $0.toMediaItem() }
    }

    /// Only the ids of what a collection or playlist holds: enough to tell what's in it.
    public func getChildIds(credential: ServerCredential, authHeader: String, parentId: String) async throws -> [String] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "ParentId", value: parentId),
            .init(name: "EnableImages", value: "false"),
            .init(name: "EnableUserData", value: "false"),
        ]
        struct Page: Decodable {
            struct Row: Decodable { let id: String; enum CodingKeys: String, CodingKey { case id = "Id" } }
            let items: [Row]
            enum CodingKeys: String, CodingKey { case items = "Items" }
        }
        let data = try await send(request(comps.url!, authHeader: authHeader))
        return try JSONDecoder().decode(Page.self, from: data).items.map(\.id)
    }

    public func getPlaylistEntries(credential: ServerCredential, authHeader: String, playlistId: String) async throws -> [PlaylistEntry] {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Playlists/\(playlistId)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "UserId", value: credential.userID),
            .init(name: "Fields", value: "Overview,UserData,PrimaryImageTags,BackdropImageTags,ThumbImageTags,ProductionYear,SeriesName,SeriesId,SeriesPrimaryImageTag,ParentBackdropImageTags,ParentBackdropItemId"),
            .init(name: "EnableUserData", value: "true"),
        ]
        let data = try await send(request(comps.url!, authHeader: authHeader))
        // Decoded twice from the same body: the shared item type stays as it is, and the
        // entry ids come from a second, tiny decode of the same rows.
        let items = try JSONDecoder().decode(ItemsPage.self, from: data).items
        let ids = try JSONDecoder().decode(EntryIdsPage.self, from: data).items
        return zip(items, ids).map { item, entry in
            PlaylistEntry(entryId: entry.playlistItemId ?? item.id, item: item.toMediaItem())
        }
    }

    @discardableResult
    public func createPlaylist(credential: ServerCredential, authHeader: String, name: String, itemIds: [String],
                               mediaType: String = "Video") async throws -> String {
        var req = request(credential.baseURL.appendingPathComponent("Playlists"), authHeader: authHeader, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "Name": name, "Ids": itemIds, "UserId": credential.userID, "MediaType": mediaType,
        ])
        let data = try await send(req)
        struct Created: Decodable { let Id: String }
        return try JSONDecoder().decode(Created.self, from: data).Id
    }

    public func addToPlaylist(credential: ServerCredential, authHeader: String, playlistId: String, itemIds: [String]) async throws {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Playlists/\(playlistId)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "ids", value: itemIds.joined(separator: ",")),
            .init(name: "userId", value: credential.userID),
        ]
        try await send(request(comps.url!, authHeader: authHeader, method: "POST"))
    }

    public func removeFromPlaylist(credential: ServerCredential, authHeader: String, playlistId: String, entryIds: [String]) async throws {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Playlists/\(playlistId)/Items"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "entryIds", value: entryIds.joined(separator: ","))]
        try await send(request(comps.url!, authHeader: authHeader, method: "DELETE"))
    }

    public func movePlaylistEntry(credential: ServerCredential, authHeader: String, playlistId: String, entryId: String, toIndex: Int) async throws {
        let url = credential.baseURL.appendingPathComponent("Playlists/\(playlistId)/Items/\(entryId)/Move/\(toIndex)")
        try await send(request(url, authHeader: authHeader, method: "POST"))
    }

    public func renamePlaylist(credential: ServerCredential, authHeader: String, playlistId: String, name: String) async throws {
        var req = request(credential.baseURL.appendingPathComponent("Playlists/\(playlistId)"), authHeader: authHeader, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["Name": name])
        try await send(req)
    }

    public func deletePlaylist(credential: ServerCredential, authHeader: String, playlistId: String) async throws {
        try await send(request(credential.baseURL.appendingPathComponent("Items/\(playlistId)"), authHeader: authHeader, method: "DELETE"))
    }

    // MARK: - Subtitle search

    /// `language` is a three-letter ISO 639-2 code ("eng"). Needs a subtitle provider plugin
    /// on the server and an account allowed to manage subtitles.
    public func searchRemoteSubtitles(credential: ServerCredential, authHeader: String, itemId: String, language: String) async throws -> [RemoteSubtitle] {
        let url = credential.baseURL.appendingPathComponent("Items/\(itemId)/RemoteSearch/Subtitles/\(language)")
        let data = try await send(request(url, authHeader: authHeader, timeout: 30))
        return try JSONDecoder().decode([RemoteSubtitleResponse].self, from: data).map(\.model)
    }

    /// Asks the server to fetch the file and attach it to the item as a new external track.
    public func downloadRemoteSubtitle(credential: ServerCredential, authHeader: String, itemId: String, subtitleId: String) async throws {
        let url = credential.baseURL.appendingPathComponent("Items/\(itemId)/RemoteSearch/Subtitles/\(subtitleId)")
        try await send(request(url, authHeader: authHeader, method: "POST", timeout: 60))
    }

    // MARK: - Helpers

    private func request(_ url: URL, authHeader: String, method: String = "GET", timeout: TimeInterval = 15) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout
        return req
    }

    @discardableResult
    private func send(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.arcfin.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw JellyfinRequestError.status(http.statusCode)
        }
        return data
    }
}

// MARK: - Response types

private struct PlaylistsPage: Decodable {
    struct Row: Decodable {
        let id: String
        let name: String
        let childCount: Int?
        let imageTags: [String: String]?
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", childCount = "ChildCount", imageTags = "ImageTags"
        }
    }
    let items: [Row]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct EntryIdsPage: Decodable {
    struct Row: Decodable {
        let playlistItemId: String?
        enum CodingKeys: String, CodingKey { case playlistItemId = "PlaylistItemId" }
    }
    let items: [Row]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct RemoteSubtitleResponse: Decodable {
    let id: String
    let name: String?
    let providerName: String?
    let format: String?
    let author: String?
    let downloadCount: Int?
    let communityRating: Double?
    let isHashMatch: Bool?
    let forced: Bool?
    let hearingImpaired: Bool?
    let machineTranslated: Bool?
    let aiTranslated: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", providerName = "ProviderName", format = "Format"
        case author = "Author", downloadCount = "DownloadCount", communityRating = "CommunityRating"
        case isHashMatch = "IsHashMatch", forced = "Forced", hearingImpaired = "HearingImpaired"
        case machineTranslated = "MachineTranslated", aiTranslated = "AiTranslated"
    }

    var model: RemoteSubtitle {
        RemoteSubtitle(
            id: id, name: name ?? "Subtitle", providerName: providerName, format: format, author: author,
            downloadCount: downloadCount, communityRating: communityRating,
            isHashMatch: isHashMatch ?? false, isForced: forced ?? false,
            isHearingImpaired: hearingImpaired ?? false,
            isMachineTranslated: (machineTranslated ?? false) || (aiTranslated ?? false))
    }
}
