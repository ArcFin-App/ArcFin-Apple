// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import Intents
import JellyfinAPI

/// "Play … in Arcfin" from Siri, in the car or anywhere: a song, album, artist, playlist or
/// genre found on the server, or everything shuffled when nothing is named. A movie or show
/// opens the app and plays there.
final class MusicSiriHandler: NSObject, INPlayMediaIntentHandling {
    func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
        switch await MusicSiriSearch.find(MusicSiriSearch.Query(intent.mediaSearch)) {
        case .found(let found):
            let item = INMediaItem(identifier: found.identifier, title: found.title, type: found.type, artwork: nil)
            return INPlayMediaMediaItemResolutionResult.successes(with: [item])
        case .signedOut:
            return [.unsupported(forReason: .loginRequired)]
        case .nothing:
            return [.unsupported()]
        }
    }

    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        guard let identifier = intent.mediaItems?.first?.identifier else { return .init(code: .failure, userActivity: nil) }
        // Video can't start in the background: the app comes forward and Home plays it.
        if identifier.hasPrefix("video:") {
            WatchRoute.open(id: String(identifier.dropFirst("video:".count)))
            return .init(code: .continueInApp, userActivity: nil)
        }
        let played = await MusicSiriSearch.play(identifier, shuffled: intent.playShuffled == true)
        return .init(code: played ? .success : .failureNoUnplayedContent, userActivity: nil)
    }
}

@MainActor
enum MusicSiriSearch {
    enum Kind: Sendable { case any, song, album, artist, playlist, genre, video }

    /// What Siri heard, as plain values so it can cross to the main actor.
    struct Query: Sendable {
        var kind = Kind.any
        var name: String?
        var artist: String?
        var album: String?
        var genre: String?

        nonisolated init(_ search: INMediaSearch?) {
            name = search?.mediaName
            artist = search?.artistName
            album = search?.albumName
            genre = search?.genreNames?.first
            switch search?.mediaType {
            case .song?: kind = .song
            case .album?: kind = .album
            case .artist?: kind = .artist
            case .playlist?: kind = .playlist
            case .genre?: kind = .genre
            case .movie?, .tvShow?, .tvShowEpisode?: kind = .video
            default: kind = .any
            }
        }

        var isEmpty: Bool { [name, artist, album, genre].allSatisfy { $0?.isEmpty ?? true } }
    }

    struct Found: Sendable {
        var identifier: String
        var title: String
        var type: INMediaItemType
    }

    enum Result: Sendable { case found(Found), signedOut, nothing }

    static func find(_ query: Query) async -> Result {
        await AppServices.authManager.checkStoredAuthOnce()
        guard AppServices.authManager.state.credential != nil else { return .signedOut }
        if query.isEmpty { return .found(Found(identifier: "all", title: String(localized: "Shuffle All"), type: .music)) }
        if query.kind == .video {
            guard let name = query.name else { return .nothing }
            return await video(named: name).map(Result.found) ?? .nothing
        }
        if query.kind == .genre || (query.name == nil && query.album == nil && query.artist == nil), let name = query.genre ?? query.name {
            let genres = (try? await MusicAPI.call { try await $0.getMusicGenres(credential: $1, authHeader: $2, libraryId: nil) }) ?? []
            if let genre = best(genres, named: name, \.name) {
                return .found(Found(identifier: "genre:\(genre.id)", title: genre.name, type: .genre))
            }
        }
        if query.kind == .playlist, let name = query.name, let playlist = await playlist(named: name) {
            return .found(Found(identifier: "playlist:\(playlist.id)", title: playlist.name, type: .playlist))
        }
        guard let term = query.name ?? query.album ?? query.artist else { return .nothing }
        guard let results = try? await MusicAPI.call({ try await $0.searchMusic(credential: $1, authHeader: $2, term: term) })
        else { return await video(named: term).map(Result.found) ?? .nothing }
        let songs = query.artist.map { artist in
            results.songs.filter { $0.artistLine?.localizedCaseInsensitiveContains(artist) == true }
        }.flatMap { $0.isEmpty ? nil : $0 } ?? results.songs
        let song = songs.first.map { Found(identifier: "song:\($0.id)", title: $0.name, type: .song) }
        let album = best(results.albums, named: query.album ?? term, \.name)
            .map { Found(identifier: "album:\($0.id)", title: $0.name, type: .album) }
        let artist = best(results.artists, named: query.artist ?? term, \.name)
            .map { Found(identifier: "artist:\($0.id)", title: $0.name, type: .artist) }
        let picked: Found? = switch query.kind {
        case .song: song
        case .album: album
        case .artist: artist
        default:
            // Named only an album or only an artist, that's what's wanted; otherwise the song.
            query.name == nil && query.album != nil ? album ?? song
                : query.name == nil ? artist ?? song
                : exact(songs.first?.name, term) ? song
                : exact(album?.title, term) ? album
                : exact(artist?.title, term) ? artist
                : song ?? album ?? artist
        }
        // Asked for by name only: a movie or show called exactly that wins over music that isn't.
        if query.kind == .any, query.artist == nil, query.album == nil, !exact(picked?.title, term),
           let video = await video(named: term), exact(video.title, term) || picked == nil {
            return .found(video)
        }
        if let picked { return .found(picked) }
        if let playlist = await playlist(named: term) {
            return .found(Found(identifier: "playlist:\(playlist.id)", title: playlist.name, type: .playlist))
        }
        return .nothing
    }

    /// A movie, show or episode with that name: a show plays its next episode.
    private static func video(named name: String) async -> Found? {
        let items = ((try? await MusicAPI.call { try await $0.search(credential: $1, authHeader: $2, query: name, limit: 10) }) ?? [])
            .filter { $0.type == .movie || $0.type == .series || $0.type == .episode }
        guard let item = best(items, named: name, \.name) else { return nil }
        let type: INMediaItemType = switch item.type {
        case .movie: .movie
        case .series: .tvShow
        default: .tvShowEpisode
        }
        return Found(identifier: "video:\(item.id)", title: item.name, type: type)
    }

    static func play(_ identifier: String, shuffled: Bool) async -> Bool {
        await AppServices.authManager.checkStoredAuthOnce()
        let parts = identifier.split(separator: ":", maxSplits: 1).map(String.init)
        let id = parts.count > 1 ? parts[1] : ""
        let songs: [MusicSong]
        var shuffles = shuffled
        switch parts.first {
        case "all":
            songs = await tracks(sort: .random, filter: .init(), limit: 200)
        case "song":
            // Autoplay carries on from it with music like it.
            songs = (try? await MusicAPI.call { try await $0.getSongs(credential: $1, authHeader: $2, ids: [id]) }) ?? []
        case "album":
            songs = (try? await MusicAPI.call { try await $0.getAlbumTracks(credential: $1, authHeader: $2, albumId: id) }) ?? []
        case "artist":
            songs = await tracks(sort: .playCount, filter: .init(artistId: id), limit: 200)
            shuffles = true
        case "playlist":
            songs = (try? await MusicAPI.call { try await $0.getPlaylistSongs(credential: $1, authHeader: $2, playlistId: id) }) ?? []
        case "genre":
            songs = (try? await MusicAPI.call { try await $0.getInstantMix(credential: $1, authHeader: $2, itemId: id) }) ?? []
        default:
            songs = []
        }
        guard !songs.isEmpty else { return false }
        shuffles ? MusicActions.shuffle(songs) : MusicActions.play(songs)
        return true
    }

    private static func tracks(sort: MusicSort, filter: MusicFilter, limit: Int) async -> [MusicSong] {
        (try? await MusicAPI.call {
            try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: sort, filter: filter, limit: limit)
        })?.tracks ?? []
    }

    private static func playlist(named name: String) async -> MusicPlaylist? {
        let playlists = (try? await MusicAPI.call { try await $0.getMusicPlaylists(credential: $1, authHeader: $2) }) ?? []
        return best(playlists, named: name, \.name)
    }

    /// The one named exactly, else the first whose name holds it.
    private static func best<T>(_ items: [T], named name: String, _ key: KeyPath<T, String>) -> T? {
        items.first { exact($0[keyPath: key], name) }
            ?? items.first { $0[keyPath: key].localizedCaseInsensitiveContains(name) }
    }

    private static func exact(_ a: String?, _ b: String) -> Bool {
        a?.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
