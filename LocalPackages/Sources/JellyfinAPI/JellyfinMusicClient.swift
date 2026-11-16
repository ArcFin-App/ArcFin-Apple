// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Music models (#386)

public struct MusicArtistRef: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MusicAlbum: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    /// The album's own artist line ("Various Artists" for a compilation).
    public var albumArtist: String?
    public var albumArtists: [MusicArtistRef]
    public var productionYear: Int?
    public var primaryImageTag: String?
    public var trackCount: Int?
    public var runTimeTicks: Int64?
    public var genres: [String]
    public var isFavorite: Bool

    public init(id: String, name: String, albumArtist: String? = nil, albumArtists: [MusicArtistRef] = [],
                productionYear: Int? = nil, primaryImageTag: String? = nil, trackCount: Int? = nil,
                runTimeTicks: Int64? = nil, genres: [String] = [], isFavorite: Bool = false) {
        self.id = id; self.name = name; self.albumArtist = albumArtist; self.albumArtists = albumArtists
        self.productionYear = productionYear; self.primaryImageTag = primaryImageTag; self.trackCount = trackCount
        self.runTimeTicks = runTimeTicks; self.genres = genres; self.isFavorite = isFavorite
    }
}

public struct MusicArtist: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var overview: String?
    public var primaryImageTag: String?
    public var backdropImageTags: [String]
    public var genres: [String]
    public var isFavorite: Bool

    public init(id: String, name: String, overview: String? = nil, primaryImageTag: String? = nil,
                backdropImageTags: [String] = [], genres: [String] = [], isFavorite: Bool = false) {
        self.id = id; self.name = name; self.overview = overview; self.primaryImageTag = primaryImageTag
        self.backdropImageTags = backdropImageTags; self.genres = genres; self.isFavorite = isFavorite
    }
}

public struct MusicSong: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var albumId: String?
    public var albumName: String?
    public var albumArtist: String?
    public var artists: [MusicArtistRef]
    /// The track's number on its disc.
    public var trackNumber: Int?
    public var discNumber: Int?
    public var runTimeTicks: Int64?
    /// The track's own art; most tracks have none and use the album's.
    public var primaryImageTag: String?
    public var albumPrimaryImageTag: String?
    public var isFavorite: Bool
    public var playCount: Int
    public var hasLyrics: Bool
    /// The file's container as the server names it, e.g. "flac" or "mov,mp4,m4a,3gp,3g2,mj2".
    public var container: String?

    public init(id: String, name: String, albumId: String? = nil, albumName: String? = nil, albumArtist: String? = nil,
                artists: [MusicArtistRef] = [], trackNumber: Int? = nil, discNumber: Int? = nil,
                runTimeTicks: Int64? = nil, primaryImageTag: String? = nil, albumPrimaryImageTag: String? = nil,
                isFavorite: Bool = false, playCount: Int = 0, hasLyrics: Bool = false, container: String? = nil) {
        self.container = container
        self.id = id; self.name = name; self.albumId = albumId; self.albumName = albumName
        self.albumArtist = albumArtist; self.artists = artists; self.trackNumber = trackNumber
        self.discNumber = discNumber; self.runTimeTicks = runTimeTicks; self.primaryImageTag = primaryImageTag
        self.albumPrimaryImageTag = albumPrimaryImageTag; self.isFavorite = isFavorite
        self.playCount = playCount; self.hasLyrics = hasLyrics
    }

    /// The artists as one line, falling back to the album's.
    public var artistLine: String? {
        let names = artists.map(\.name)
        return names.isEmpty ? albumArtist : names.joined(separator: ", ")
    }

    public var duration: TimeInterval? { runTimeTicks.map { Double($0) / 10_000_000 } }
}

public struct MusicGenre: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var primaryImageTag: String?

    public init(id: String, name: String, primaryImageTag: String? = nil) {
        self.id = id; self.name = name; self.primaryImageTag = primaryImageTag
    }
}

public struct Lyrics: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        /// Seconds from the start; nil for lyrics without timing.
        public var start: TimeInterval?
        public var text: String

        public init(start: TimeInterval?, text: String) {
            self.start = start; self.text = text
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) { self.lines = lines }

    /// Every line has a time, so the player can follow along.
    public var isSynced: Bool { !lines.isEmpty && lines.allSatisfy { $0.start != nil } }

    /// The line being sung at this point, for synced lyrics.
    public func lineIndex(at seconds: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        return lines.lastIndex { ($0.start ?? 0) <= seconds }
    }
}

public enum MusicSort: String, Sendable, CaseIterable {
    case name, artist, album, year, dateAdded, playCount, random

    /// Jellyfin's SortBy, with tie-breakers so equal values keep a stable order.
    var sortBy: String {
        switch self {
        case .name: "SortName"
        case .artist: "AlbumArtist,SortName"
        case .album: "Album,ParentIndexNumber,IndexNumber,SortName"
        case .year: "ProductionYear,PremiereDate,SortName"
        case .dateAdded: "DateCreated,SortName"
        case .playCount: "PlayCount,SortName"
        case .random: "Random"
        }
    }
}

/// What to narrow a list to.
public struct MusicFilter: Sendable, Equatable {
    public var favoritesOnly = false
    public var genreId: String?
    public var artistId: String?

    public init(favoritesOnly: Bool = false, genreId: String? = nil, artistId: String? = nil) {
        self.favoritesOnly = favoritesOnly; self.genreId = genreId; self.artistId = artistId
    }
}

// MARK: - Music client

extension JellyfinMediaClient {

    /// Albums in a music library, a page at a time.
    public func getMusicAlbums(credential: ServerCredential, authHeader: String, libraryId: String,
                               sort: MusicSort = .name, ascending: Bool = true, filter: MusicFilter = .init(),
                               startIndex: Int = 0, limit: Int = 100) async throws -> (albums: [MusicAlbum], total: Int) {
        var query = musicItemsQuery(credential: credential, types: "MusicAlbum", parentId: libraryId, sort: sort,
                                    ascending: ascending, filter: filter, startIndex: startIndex, limit: limit)
        if let artistId = filter.artistId { query.append(.init(name: "AlbumArtistIds", value: artistId)) }
        let page: MusicPage = try await getMusic("Items", query: query, credential: credential, authHeader: authHeader)
        let albums = page.items.map { $0.asAlbum }
        return (albums, page.totalRecordCount ?? startIndex + albums.count)
    }

    /// Songs in a music library, a page at a time.
    public func getMusicTracks(credential: ServerCredential, authHeader: String, libraryId: String,
                               sort: MusicSort = .name, ascending: Bool = true, filter: MusicFilter = .init(),
                               startIndex: Int = 0, limit: Int = 100) async throws -> (tracks: [MusicSong], total: Int) {
        var query = musicItemsQuery(credential: credential, types: "Audio", parentId: libraryId, sort: sort,
                                    ascending: ascending, filter: filter, startIndex: startIndex, limit: limit)
        if let artistId = filter.artistId { query.append(.init(name: "ArtistIds", value: artistId)) }
        let page: MusicPage = try await getMusic("Items", query: query, credential: credential, authHeader: authHeader)
        let tracks = page.items.map { $0.asTrack }
        return (tracks, page.totalRecordCount ?? startIndex + tracks.count)
    }

    /// Artists in a music library. Album artists only leaves out everyone who only guests on
    /// a track.
    public func getMusicArtists(credential: ServerCredential, authHeader: String, libraryId: String,
                                albumArtistsOnly: Bool = true, filter: MusicFilter = .init(),
                                startIndex: Int = 0, limit: Int = 100) async throws -> (artists: [MusicArtist], total: Int) {
        var query = baseQuery(credential: credential, startIndex: startIndex, limit: limit)
        query += [
            .init(name: "ParentId", value: libraryId),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "SortOrder", value: "Ascending"),
            .init(name: "Fields", value: "Overview,Genres,PrimaryImageAspectRatio"),
        ]
        if filter.favoritesOnly { query.append(.init(name: "IsFavorite", value: "true")) }
        if let genreId = filter.genreId { query.append(.init(name: "GenreIds", value: genreId)) }
        let page: MusicPage = try await getMusic(albumArtistsOnly ? "Artists/AlbumArtists" : "Artists", query: query,
                                                 credential: credential, authHeader: authHeader)
        let artists = page.items.map { $0.asArtist }
        return (artists, page.totalRecordCount ?? startIndex + artists.count)
    }

    public func getMusicGenres(credential: ServerCredential, authHeader: String, libraryId: String) async throws -> [MusicGenre] {
        var query = baseQuery(credential: credential, startIndex: 0, limit: 500)
        query += [.init(name: "ParentId", value: libraryId), .init(name: "SortBy", value: "SortName")]
        let page: MusicPage = try await getMusic("MusicGenres", query: query, credential: credential, authHeader: authHeader)
        return page.items.map { MusicGenre(id: $0.id, name: $0.name ?? "", primaryImageTag: $0.imageTags?["Primary"]) }
    }

    /// An album's tracks in disc and track order.
    public func getAlbumTracks(credential: ServerCredential, authHeader: String, albumId: String) async throws -> [MusicSong] {
        var query = baseQuery(credential: credential, startIndex: 0, limit: 1000)
        query += [
            .init(name: "ParentId", value: albumId),
            .init(name: "IncludeItemTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName"),
            .init(name: "Fields", value: Self.musicFields),
        ]
        let page: MusicPage = try await getMusic("Items", query: query, credential: credential, authHeader: authHeader)
        return page.items.map { $0.asTrack }
    }

    public func getMusicAlbum(credential: ServerCredential, authHeader: String, albumId: String) async throws -> MusicAlbum {
        let item: MusicItemResponse = try await getMusic("Users/\(credential.userID)/Items/\(albumId)",
                                                         query: [.init(name: "Fields", value: Self.musicFields)],
                                                         credential: credential, authHeader: authHeader)
        return item.asAlbum
    }

    public func getMusicArtist(credential: ServerCredential, authHeader: String, artistId: String) async throws -> MusicArtist {
        let item: MusicItemResponse = try await getMusic("Users/\(credential.userID)/Items/\(artistId)",
                                                         query: [.init(name: "Fields", value: "Overview,Genres")],
                                                         credential: credential, authHeader: authHeader)
        return item.asArtist
    }

    /// Songs like this one, an album or an artist, for a radio-style mix.
    public func getInstantMix(credential: ServerCredential, authHeader: String, itemId: String,
                              limit: Int = 100) async throws -> [MusicSong] {
        var query = baseQuery(credential: credential, startIndex: 0, limit: limit)
        query.append(.init(name: "Fields", value: Self.musicFields))
        let page: MusicPage = try await getMusic("Items/\(itemId)/InstantMix", query: query,
                                                 credential: credential, authHeader: authHeader)
        return page.items.map { $0.asTrack }
    }

    /// The song's lyrics, or nil when the server has none (Jellyfin 10.9+).
    public func getLyrics(credential: ServerCredential, authHeader: String, trackId: String) async throws -> Lyrics? {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Audio/\(trackId)/Lyrics"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try Self.decodeLyrics(data)
    }

    /// Containers AVFoundation opens as they are.
    static let directAudioContainers: Set<String> = ["mp3", "aac", "m4a", "m4b", "mp4", "flac", "alac", "wav", "aiff", "aif", "caf"]

    /// The song's file as is when AVFoundation plays its container, otherwise MP3 made from it.
    /// The extension is in the path: AVFoundation picks a demuxer from it, and without one it
    /// can't open the stream at all.
    public func audioStreamURL(credential: ServerCredential, deviceId: String, trackId: String,
                               container: String?, maxBitrate: Int = 320_000) -> URL? {
        let names = (container ?? "").lowercased().split(separator: ",").map(String.init)
        let direct = names.first(where: { $0 == "m4a" && names.count > 1 })
            ?? names.first(where: Self.directAudioContainers.contains)
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Audio/\(trackId)/stream.\(direct ?? "mp3")"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = direct != nil
            ? [.init(name: "static", value: "true")]
            : [.init(name: "audioCodec", value: "mp3"), .init(name: "audioBitRate", value: String(maxBitrate))]
        comps?.queryItems? += [
            .init(name: "DeviceId", value: deviceId),
            .init(name: "api_key", value: credential.accessToken),
        ]
        return comps?.url
    }

    // MARK: Helpers

    static let musicFields = "Genres,DateCreated,ChildCount,ParentId,PrimaryImageAspectRatio,MediaSourceCount"

    static func decodeLyrics(_ data: Data) throws -> Lyrics {
        let response = try JSONDecoder().decode(LyricsResponse.self, from: data)
        return Lyrics(lines: (response.lyrics ?? []).map {
            Lyrics.Line(start: $0.start.map { Double($0) / 10_000_000 }, text: $0.text ?? "")
        })
    }

    static func decodeMusicPage(_ data: Data) throws -> (items: [MusicItemResponse], total: Int?) {
        let page = try JSONDecoder().decode(MusicPage.self, from: data)
        return (page.items, page.totalRecordCount)
    }

    private func baseQuery(credential: ServerCredential, startIndex: Int, limit: Int) -> [URLQueryItem] {
        [
            .init(name: "UserId", value: credential.userID),
            .init(name: "StartIndex", value: String(startIndex)),
            .init(name: "Limit", value: String(limit)),
            .init(name: "EnableTotalRecordCount", value: "true"),
            .init(name: "EnableUserData", value: "true"),
            .init(name: "EnableImageTypes", value: "Primary,Backdrop"),
            .init(name: "ImageTypeLimit", value: "1"),
        ]
    }

    private func musicItemsQuery(credential: ServerCredential, types: String, parentId: String, sort: MusicSort,
                                 ascending: Bool, filter: MusicFilter, startIndex: Int, limit: Int) -> [URLQueryItem] {
        var query = baseQuery(credential: credential, startIndex: startIndex, limit: limit)
        query += [
            .init(name: "ParentId", value: parentId),
            .init(name: "IncludeItemTypes", value: types),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: sort.sortBy),
            .init(name: "SortOrder", value: ascending ? "Ascending" : "Descending"),
            .init(name: "Fields", value: Self.musicFields),
        ]
        if filter.favoritesOnly { query.append(.init(name: "IsFavorite", value: "true")) }
        if let genreId = filter.genreId { query.append(.init(name: "GenreIds", value: genreId)) }
        return query
    }

    private func getMusic<T: Decodable>(_ path: String, query: [URLQueryItem], credential: ServerCredential,
                                        authHeader: String) async throws -> T {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        comps?.queryItems = query
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Responses

struct MusicPage: Decodable {
    let items: [MusicItemResponse]
    let totalRecordCount: Int?
    enum CodingKeys: String, CodingKey { case items = "Items", totalRecordCount = "TotalRecordCount" }
}

struct MusicItemResponse: Decodable {
    struct NameId: Decodable {
        let id: String?
        let name: String?
        enum CodingKeys: String, CodingKey { case id = "Id", name = "Name" }
    }
    struct UserDataResponse: Decodable {
        let isFavorite: Bool?
        let playCount: Int?
        enum CodingKeys: String, CodingKey { case isFavorite = "IsFavorite", playCount = "PlayCount" }
    }

    let id: String
    let name: String?
    let overview: String?
    let albumArtist: String?
    let albumArtists: [NameId]?
    let artistItems: [NameId]?
    let album: String?
    let albumId: String?
    let albumPrimaryImageTag: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let productionYear: Int?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let runTimeTicks: Int64?
    let childCount: Int?
    let genres: [String]?
    let userData: UserDataResponse?
    let hasLyrics: Bool?
    let container: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", overview = "Overview", albumArtist = "AlbumArtist"
        case albumArtists = "AlbumArtists", artistItems = "ArtistItems", album = "Album", albumId = "AlbumId"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag", imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags", productionYear = "ProductionYear"
        case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber", runTimeTicks = "RunTimeTicks"
        case childCount = "ChildCount", genres = "Genres", userData = "UserData", hasLyrics = "HasLyrics"
        case container = "Container"
    }

    private static func refs(_ items: [NameId]?) -> [MusicArtistRef] {
        (items ?? []).compactMap { item in item.id.map { MusicArtistRef(id: $0, name: item.name ?? "") } }
    }

    var asAlbum: MusicAlbum {
        MusicAlbum(id: id, name: name ?? "", albumArtist: albumArtist, albumArtists: Self.refs(albumArtists),
                   productionYear: productionYear, primaryImageTag: imageTags?["Primary"], trackCount: childCount,
                   runTimeTicks: runTimeTicks, genres: genres ?? [], isFavorite: userData?.isFavorite ?? false)
    }

    var asArtist: MusicArtist {
        MusicArtist(id: id, name: name ?? "", overview: overview, primaryImageTag: imageTags?["Primary"],
                    backdropImageTags: backdropImageTags ?? [], genres: genres ?? [],
                    isFavorite: userData?.isFavorite ?? false)
    }

    var asTrack: MusicSong {
        MusicSong(id: id, name: name ?? "", albumId: albumId, albumName: album, albumArtist: albumArtist,
                   artists: Self.refs(artistItems), trackNumber: indexNumber, discNumber: parentIndexNumber,
                   runTimeTicks: runTimeTicks, primaryImageTag: imageTags?["Primary"],
                   albumPrimaryImageTag: albumPrimaryImageTag, isFavorite: userData?.isFavorite ?? false,
                   playCount: userData?.playCount ?? 0, hasLyrics: hasLyrics ?? false, container: container)
    }
}

private struct LyricsResponse: Decodable {
    struct Line: Decodable {
        let text: String?
        let start: Int64?
        enum CodingKeys: String, CodingKey { case text = "Text", start = "Start" }
    }
    let lyrics: [Line]?
    enum CodingKeys: String, CodingKey { case lyrics = "Lyrics" }
}
