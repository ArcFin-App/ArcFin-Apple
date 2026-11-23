// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Music models (#386)

public struct MusicArtistRef: Sendable, Identifiable, Equatable, Hashable, Codable {
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MusicAlbum: Sendable, Identifiable, Equatable, Hashable, Codable {
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
    /// From the album's own page only; lists leave them out.
    public var overview: String?
    public var credits: [MusicCredit]?
    /// When it came out, and its label, from the album's own page.
    public var releaseDate: Date?
    public var label: String?

    public init(id: String, name: String, albumArtist: String? = nil, albumArtists: [MusicArtistRef] = [],
                productionYear: Int? = nil, primaryImageTag: String? = nil, trackCount: Int? = nil,
                runTimeTicks: Int64? = nil, genres: [String] = [], isFavorite: Bool = false,
                overview: String? = nil, credits: [MusicCredit]? = nil) {
        self.id = id; self.name = name; self.albumArtist = albumArtist; self.albumArtists = albumArtists
        self.productionYear = productionYear; self.primaryImageTag = primaryImageTag; self.trackCount = trackCount
        self.runTimeTicks = runTimeTicks; self.genres = genres; self.isFavorite = isFavorite
        self.overview = overview; self.credits = credits
    }

    /// Three songs or fewer: a single or an EP rather than an album.
    public var isSingle: Bool { (trackCount ?? .max) <= 3 }
}

/// Someone credited on an album: a composer, producer, performer and the like.
public struct MusicCredit: Sendable, Equatable, Hashable, Codable {
    public var name: String
    /// What they did, e.g. "Composer"; the role when the server has one, else the kind.
    public var role: String?

    public init(name: String, role: String? = nil) {
        self.name = name; self.role = role
    }
}

public struct MusicArtist: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var overview: String?
    public var primaryImageTag: String?
    public var backdropImageTags: [String]
    public var logoImageTag: String?
    public var genres: [String]
    public var isFavorite: Bool

    public init(id: String, name: String, overview: String? = nil, primaryImageTag: String? = nil,
                backdropImageTags: [String] = [], logoImageTag: String? = nil, genres: [String] = [], isFavorite: Bool = false) {
        self.id = id; self.name = name; self.overview = overview; self.primaryImageTag = primaryImageTag
        self.backdropImageTags = backdropImageTags; self.logoImageTag = logoImageTag
        self.genres = genres; self.isFavorite = isFavorite
    }
}

public struct MusicSong: Sendable, Identifiable, Equatable, Hashable, Codable {
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
    /// Its place in a playlist, which removing it from the playlist needs.
    public var playlistEntryId: String?
    /// The change in dB that brings it to the server's common loudness (Jellyfin 10.9+).
    public var normalizationGain: Double?
    /// Liked (true), disliked (false), or neither.
    public var likes: Bool?

    public init(id: String, name: String, albumId: String? = nil, albumName: String? = nil, albumArtist: String? = nil,
                artists: [MusicArtistRef] = [], trackNumber: Int? = nil, discNumber: Int? = nil,
                runTimeTicks: Int64? = nil, primaryImageTag: String? = nil, albumPrimaryImageTag: String? = nil,
                isFavorite: Bool = false, playCount: Int = 0, hasLyrics: Bool = false, container: String? = nil,
                playlistEntryId: String? = nil, normalizationGain: Double? = nil, likes: Bool? = nil) {
        self.normalizationGain = normalizationGain
        self.likes = likes
        self.container = container
        self.playlistEntryId = playlistEntryId
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

public struct MusicPlaylist: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var primaryImageTag: String?
    public var songCount: Int?

    public init(id: String, name: String, primaryImageTag: String? = nil, songCount: Int? = nil) {
        self.id = id; self.name = name; self.primaryImageTag = primaryImageTag; self.songCount = songCount
    }
}

/// What a search found in music.
public struct MusicSearchResults: Sendable, Equatable {
    public var artists: [MusicArtist] = []
    public var albums: [MusicAlbum] = []
    public var songs: [MusicSong] = []
    public var isEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty }
    public init(artists: [MusicArtist] = [], albums: [MusicAlbum] = [], songs: [MusicSong] = []) {
        self.artists = artists; self.albums = albums; self.songs = songs
    }
}

public struct MusicGenre: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var primaryImageTag: String?

    public init(id: String, name: String, primaryImageTag: String? = nil) {
        self.id = id; self.name = name; self.primaryImageTag = primaryImageTag
    }
}

public struct Lyrics: Sendable, Equatable, Codable {
    public struct Line: Sendable, Equatable, Codable {
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
    case name, artist, album, year, dateAdded, playCount, datePlayed, random

    /// Jellyfin's SortBy, with tie-breakers so equal values keep a stable order.
    var sortBy: String {
        switch self {
        case .name: "SortName"
        case .artist: "AlbumArtist,SortName"
        case .album: "Album,ParentIndexNumber,IndexNumber,SortName"
        case .year: "ProductionYear,PremiereDate,SortName"
        case .dateAdded: "DateCreated,SortName"
        case .playCount: "PlayCount,SortName"
        case .datePlayed: "DatePlayed,SortName"
        case .random: "Random"
        }
    }
}

/// What to narrow a list to.
public struct MusicFilter: Sendable, Equatable {
    public var favoritesOnly = false
    public var genreId: String?
    public var artistId: String?
    /// Only what this profile has played.
    public var playedOnly = false
    /// Only what this profile has never played.
    public var unplayedOnly = false
    /// Only names that match, as the server searches them.
    public var searchTerm: String?

    public init(favoritesOnly: Bool = false, genreId: String? = nil, artistId: String? = nil, playedOnly: Bool = false,
                unplayedOnly: Bool = false, searchTerm: String? = nil) {
        self.favoritesOnly = favoritesOnly; self.genreId = genreId; self.artistId = artistId
        self.playedOnly = playedOnly
        self.unplayedOnly = unplayedOnly
        self.searchTerm = searchTerm
    }
}

// MARK: - Music client

extension JellyfinMediaClient {

    /// Albums in a music library, a page at a time.
    /// No library looks in all of them.
    public func getMusicAlbums(credential: ServerCredential, authHeader: String, libraryId: String?,
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
    public func getMusicTracks(credential: ServerCredential, authHeader: String, libraryId: String?,
                               sort: MusicSort = .name, ascending: Bool = true, filter: MusicFilter = .init(),
                               startIndex: Int = 0, limit: Int = 100) async throws -> (tracks: [MusicSong], total: Int) {
        var query = musicItemsQuery(credential: credential, types: "Audio", parentId: libraryId, sort: sort,
                                    ascending: ascending, filter: filter, startIndex: startIndex, limit: limit)
        if let artistId = filter.artistId { query.append(.init(name: "ArtistIds", value: artistId)) }
        let page: MusicPage = try await getMusic("Items", query: query, credential: credential, authHeader: authHeader)
        let tracks = page.items.map { $0.asTrack }
        return (tracks, page.totalRecordCount ?? startIndex + tracks.count)
    }

    /// Artists in a music library, or in all of them. Album artists only leaves out everyone
    /// who only guests on a track.
    public func getMusicArtists(credential: ServerCredential, authHeader: String, libraryId: String?,
                                albumArtistsOnly: Bool = true, filter: MusicFilter = .init(),
                                startIndex: Int = 0, limit: Int = 100) async throws -> (artists: [MusicArtist], total: Int) {
        var query = baseQuery(credential: credential, startIndex: startIndex, limit: limit)
        if let libraryId { query.append(.init(name: "ParentId", value: libraryId)) }
        query += [
            .init(name: "SortBy", value: "SortName"),
            .init(name: "SortOrder", value: "Ascending"),
            .init(name: "Fields", value: "Overview,Genres,PrimaryImageAspectRatio"),
        ]
        if filter.favoritesOnly { query.append(.init(name: "IsFavorite", value: "true")) }
        if let genreId = filter.genreId { query.append(.init(name: "GenreIds", value: genreId)) }
        if let term = filter.searchTerm { query.append(.init(name: "SearchTerm", value: term)) }
        let page: MusicPage = try await getMusic(albumArtistsOnly ? "Artists/AlbumArtists" : "Artists", query: query,
                                                 credential: credential, authHeader: authHeader)
        let artists = page.items.map { $0.asArtist }
        return (artists, page.totalRecordCount ?? startIndex + artists.count)
    }

    /// A music library's genres, or every music library's.
    public func getMusicGenres(credential: ServerCredential, authHeader: String, libraryId: String?) async throws -> [MusicGenre] {
        var query = baseQuery(credential: credential, startIndex: 0, limit: 500)
        if let libraryId { query.append(.init(name: "ParentId", value: libraryId)) }
        query.append(.init(name: "SortBy", value: "SortName"))
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
                                                         query: [.init(name: "Fields", value: Self.musicFields + ",Overview,People,Studios")],
                                                         credential: credential, authHeader: authHeader)
        var album = item.asAlbum
        album.overview = item.overview
        album.releaseDate = item.premiereDate.flatMap(Self.date)
        album.label = item.studios?.first?.name
        album.credits = item.people?.compactMap { person in
            person.name.map { MusicCredit(name: $0, role: person.role?.isEmpty == false ? person.role : person.type) }
        }
        return album
    }

    /// Jellyfin's dates, with or without fractions of a second.
    static func date(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Albums by others that the artist is on.
    public func getAppearsOn(credential: ServerCredential, authHeader: String, artistId: String,
                             libraryId: String?, limit: Int = 30) async throws -> [MusicAlbum] {
        var query = musicItemsQuery(credential: credential, types: "MusicAlbum", parentId: libraryId, sort: .year,
                                    ascending: false, filter: .init(), startIndex: 0, limit: limit)
        query.append(.init(name: "ContributingArtistIds", value: artistId))
        let page: MusicPage = try await getMusic("Items", query: query, credential: credential, authHeader: authHeader)
        return page.items.map(\.asAlbum).filter { !$0.albumArtists.contains { $0.id == artistId } }
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

    /// Artists the server finds like this one: from shared genres, or from ListenBrainz when
    /// the library has it switched on for artists.
    public func getSimilarArtists(credential: ServerCredential, authHeader: String, artistId: String,
                                  limit: Int = 12) async throws -> [MusicArtist] {
        var query = baseQuery(credential: credential, startIndex: 0, limit: limit)
        query.append(.init(name: "Fields", value: "Overview,Genres,PrimaryImageAspectRatio"))
        let page: MusicPage = try await getMusic("Items/\(artistId)/Similar", query: query,
                                                 credential: credential, authHeader: authHeader)
        return page.items.filter { $0.type == "MusicArtist" }.map { $0.asArtist }
    }

    /// Artists, albums and songs whose names match, in every music library.
    public func searchMusic(credential: ServerCredential, authHeader: String, term: String,
                            limit: Int = 24) async throws -> MusicSearchResults {
        var query = baseQuery(credential: credential, startIndex: 0, limit: limit)
        query += [
            .init(name: "SearchTerm", value: term),
            .init(name: "IncludeItemTypes", value: "MusicArtist,MusicAlbum,Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "Fields", value: Self.musicFields),
        ]
        let page: MusicPage = try await getMusic("Items", query: query, credential: credential, authHeader: authHeader)
        return Self.searchResults(page.items)
    }

    static func searchResults(_ items: [MusicItemResponse]) -> MusicSearchResults {
        var results = MusicSearchResults()
        for item in items {
            switch item.type {
            case "MusicArtist": results.artists.append(item.asArtist)
            case "MusicAlbum": results.albums.append(item.asAlbum)
            case "Audio": results.songs.append(item.asTrack)
            default: break
            }
        }
        return results
    }

    /// These items, in the order given, when every one is a song; nil when any isn't.
    public func getSongs(credential: ServerCredential, authHeader: String, ids: [String]) async throws -> [MusicSong]? {
        var query = baseQuery(credential: credential, startIndex: 0, limit: ids.count)
        query += [.init(name: "Ids", value: ids.joined(separator: ",")), .init(name: "Fields", value: Self.musicFields)]
        let page: MusicPage = try await getMusic("Items", query: query, credential: credential, authHeader: authHeader)
        return Self.songs(page.items, inOrder: ids)
    }

    /// The song's file and its audio: format, bit depth, sample rate and bitrate.
    public func getAudioFormat(credential: ServerCredential, authHeader: String, songId: String) async throws -> MusicAudioFormat? {
        let item: AudioItemResponse = try await getMusic("Users/\(credential.userID)/Items/\(songId)", query: [],
                                                         credential: credential, authHeader: authHeader)
        return item.format
    }

    static func songs(_ items: [MusicItemResponse], inOrder ids: [String]) -> [MusicSong]? {
        guard !items.isEmpty, items.allSatisfy({ $0.type == "Audio" }) else { return nil }
        let byID = Dictionary(items.map { ($0.id, $0.asTrack) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// The profile's playlists of music.
    public func getMusicPlaylists(credential: ServerCredential, authHeader: String) async throws -> [MusicPlaylist] {
        var query = baseQuery(credential: credential, startIndex: 0, limit: 500)
        query += [
            .init(name: "IncludeItemTypes", value: "Playlist"),
            .init(name: "MediaTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "SortName"),
            .init(name: "Fields", value: "ChildCount"),
        ]
        let page: MusicPage = try await getMusic("Items", query: query, credential: credential, authHeader: authHeader)
        return page.items.map { MusicPlaylist(id: $0.id, name: $0.name ?? "", primaryImageTag: $0.imageTags?["Primary"],
                                              songCount: $0.childCount) }
    }

    public func createMusicPlaylist(credential: ServerCredential, authHeader: String, name: String,
                                    songIds: [String]) async throws {
        try await createPlaylist(credential: credential, authHeader: authHeader, name: name, itemIds: songIds, mediaType: "Audio")
    }

    /// A playlist's songs in its own order.
    public func getPlaylistSongs(credential: ServerCredential, authHeader: String, playlistId: String) async throws -> [MusicSong] {
        var query = baseQuery(credential: credential, startIndex: 0, limit: 1000)
        query.append(.init(name: "Fields", value: Self.musicFields))
        let page: MusicPage = try await getMusic("Playlists/\(playlistId)/Items", query: query,
                                                 credential: credential, authHeader: authHeader)
        return page.items.filter { $0.type == nil || $0.type == "Audio" }.map { $0.asTrack }
    }

    /// Likes (true) or dislikes (false) a song for the profile, or clears either (nil).
    public func setLikes(credential: ServerCredential, authHeader: String, itemId: String, likes: Bool?) async throws {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("UserItems/\(itemId)/Rating"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [.init(name: "userId", value: credential.userID)] + (likes.map { [.init(name: "likes", value: String($0))] } ?? [])
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = likes == nil ? "DELETE" : "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (_, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
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

    /// Containers AVFoundation opens as they are: Ogg too (Opus and Vorbis) since iOS 17,
    /// so an .opus file plays as it is rather than converted to MP3.
    public static let directAudioContainers: Set<String> = ["mp3", "aac", "m4a", "m4b", "mp4", "flac", "alac", "wav", "aiff", "aif", "caf",
                                                            "ogg", "oga", "opus"]

    /// The song's file as is when AVFoundation plays its container, otherwise MP3 made from it.
    /// The extension is in the path: AVFoundation picks a demuxer from it, and without one it
    /// can't open the stream at all.
    /// Containers a Chromecast plays as they are; M4A can hold ALAC, which it doesn't.
    public static let castAudioContainers: Set<String> = ["mp3", "flac", "wav"]

    public func audioStreamURL(credential: ServerCredential, deviceId: String, trackId: String,
                               container: String?, maxBitrate: Int = 320_000,
                               direct playable: Set<String> = directAudioContainers,
                               bitrateCap: Int? = nil, startSeconds: Double = 0) -> URL? {
        let names = (container ?? "").lowercased().split(separator: ",").map(String.init)
        // A cap converts every song, at that rate.
        let direct = bitrateCap != nil ? nil
            : names.first(where: { $0 == "m4a" && names.count > 1 && playable.contains("m4a") }) ?? names.first(where: playable.contains)
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Audio/\(trackId)/stream.\(direct ?? "mp3")"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = direct != nil
            ? [.init(name: "static", value: "true")]
            : [.init(name: "audioCodec", value: "mp3"), .init(name: "audioBitRate", value: String(bitrateCap ?? maxBitrate))]
                + (startSeconds > 0 ? [.init(name: "StartTimeTicks", value: String(Int64(startSeconds * 10_000_000)))] : [])
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

    func musicItemsQuery(credential: ServerCredential, types: String, parentId: String?, sort: MusicSort,
                                 ascending: Bool, filter: MusicFilter, startIndex: Int, limit: Int) -> [URLQueryItem] {
        var query = baseQuery(credential: credential, startIndex: startIndex, limit: limit)
        if let parentId { query.append(.init(name: "ParentId", value: parentId)) }
        query += [
            .init(name: "IncludeItemTypes", value: types),
            .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: sort.sortBy),
            .init(name: "SortOrder", value: ascending ? "Ascending" : "Descending"),
            .init(name: "Fields", value: Self.musicFields),
        ]
        if filter.favoritesOnly { query.append(.init(name: "IsFavorite", value: "true")) }
        if let genreId = filter.genreId { query.append(.init(name: "GenreIds", value: genreId)) }
        if filter.playedOnly { query.append(.init(name: "IsPlayed", value: "true")) }
        if filter.unplayedOnly { query.append(.init(name: "IsPlayed", value: "false")) }
        if let term = filter.searchTerm { query.append(.init(name: "SearchTerm", value: term)) }
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

/// What a song's file holds, as the server read it.
public struct MusicAudioFormat: Sendable, Equatable {
    public var codec: String?
    public var container: String?
    public var bitrate: Int?
    public var sampleRate: Int?
    public var bitDepth: Int?
    public var channels: Int?

    public init(codec: String? = nil, container: String? = nil, bitrate: Int? = nil, sampleRate: Int? = nil,
                bitDepth: Int? = nil, channels: Int? = nil) {
        self.codec = codec; self.container = container; self.bitrate = bitrate
        self.sampleRate = sampleRate; self.bitDepth = bitDepth; self.channels = channels
    }

    /// Kept bit for bit: FLAC, ALAC, WAV, AIFF and the like.
    public var isLossless: Bool {
        guard let codec = codec?.lowercased() else { return false }
        return ["flac", "alac", "wav", "wavpack", "ape", "tta", "truehd", "mlp"].contains(codec)
            || codec.hasPrefix("pcm") || codec.hasPrefix("dsd")
    }

    /// Past CD quality: more than 16 bits or 48 kHz.
    public var isHighResolution: Bool {
        isLossless && ((bitDepth ?? 0) > 16 || (sampleRate ?? 0) > 48_000)
    }
}

struct AudioItemResponse: Decodable {
    struct Source: Decodable {
        let container: String?
        let bitrate: Int?
        let mediaStreams: [Stream]?
        enum CodingKeys: String, CodingKey {
            case container = "Container", bitrate = "Bitrate", mediaStreams = "MediaStreams"
        }
    }
    struct Stream: Decodable {
        let type: String?
        let codec: String?
        let bitRate: Int?
        let sampleRate: Int?
        let bitDepth: Int?
        let channels: Int?
        enum CodingKeys: String, CodingKey {
            case type = "Type", codec = "Codec", bitRate = "BitRate", sampleRate = "SampleRate",
                 bitDepth = "BitDepth", channels = "Channels"
        }
    }
    let mediaSources: [Source]?
    enum CodingKeys: String, CodingKey { case mediaSources = "MediaSources" }

    var format: MusicAudioFormat? {
        guard let source = mediaSources?.first else { return nil }
        let audio = source.mediaStreams?.first { $0.type == "Audio" }
        return MusicAudioFormat(codec: audio?.codec, container: source.container, bitrate: audio?.bitRate ?? source.bitrate,
                                sampleRate: audio?.sampleRate, bitDepth: audio?.bitDepth, channels: audio?.channels)
    }
}

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
        let likes: Bool?
        enum CodingKeys: String, CodingKey { case isFavorite = "IsFavorite", playCount = "PlayCount", likes = "Likes" }
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
    let type: String?
    let playlistItemId: String?
    let normalizationGain: Double?
    let people: [Person]?
    let premiereDate: String?
    let studios: [NameId]?

    struct Person: Decodable {
        let name: String?
        let role: String?
        let type: String?
        enum CodingKeys: String, CodingKey { case name = "Name", role = "Role", type = "Type" }
    }

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", overview = "Overview", albumArtist = "AlbumArtist"
        case albumArtists = "AlbumArtists", artistItems = "ArtistItems", album = "Album", albumId = "AlbumId"
        case albumPrimaryImageTag = "AlbumPrimaryImageTag", imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags", productionYear = "ProductionYear"
        case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber", runTimeTicks = "RunTimeTicks"
        case childCount = "ChildCount", genres = "Genres", userData = "UserData", hasLyrics = "HasLyrics"
        case container = "Container", type = "Type", playlistItemId = "PlaylistItemId"
        case normalizationGain = "NormalizationGain"
        case people = "People", premiereDate = "PremiereDate", studios = "Studios"
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
                    backdropImageTags: backdropImageTags ?? [], logoImageTag: imageTags?["Logo"], genres: genres ?? [],
                    isFavorite: userData?.isFavorite ?? false)
    }

    var asTrack: MusicSong {
        MusicSong(id: id, name: name ?? "", albumId: albumId, albumName: album, albumArtist: albumArtist,
                   artists: Self.refs(artistItems), trackNumber: indexNumber, discNumber: parentIndexNumber,
                   runTimeTicks: runTimeTicks, primaryImageTag: imageTags?["Primary"],
                   albumPrimaryImageTag: albumPrimaryImageTag, isFavorite: userData?.isFavorite ?? false,
                   playCount: userData?.playCount ?? 0, hasLyrics: hasLyrics ?? false, container: container, playlistEntryId: playlistItemId,
                   normalizationGain: normalizationGain, likes: userData?.likes)
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
