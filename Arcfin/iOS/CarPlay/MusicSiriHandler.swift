// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import AVFoundation
import Foundation
import Intents
import JellyfinAPI
import os
import Telemetry

/// "Play … in Arcfin" from Siri, in the car or anywhere: a song, album, artist, playlist or
/// genre found on the server, or everything shuffled when nothing is named. A movie or show
/// opens the app and plays there.
final class MusicSiriHandler: NSObject, INPlayMediaIntentHandling {
    func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
        // Back from Siri asking which one: the song picked.
        if let picked = intent.mediaItems?.first, picked.identifier?.contains(":") == true {
            return INPlayMediaMediaItemResolutionResult.successes(with: [picked])
        }
        switch await MusicSiriSearch.find(MusicSiriSearch.Query(intent.mediaSearch)) {
        case .found(let found):
            return INPlayMediaMediaItemResolutionResult.successes(with: [found.item])
        case .choices(let choices):
            // Not by the artist asked for: Siri reads out the ones there are and asks.
            return [.disambiguation(with: choices.map(\.item))]
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
        // Siri still holds the audio while it answers, so the music starts once it's quiet.
        await MusicSiriSearch.hold(identifier, shuffled: intent.playShuffled == true)
        return .init(code: .success, userActivity: nil)
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
        var artist: String?

        var item: INMediaItem {
            INMediaItem(identifier: identifier, title: title, type: type, artwork: nil, artist: artist)
        }
    }

    enum Result: Sendable { case found(Found), choices([Found]), signedOut, nothing }

    private static let log = Telemetry.logger(category: "Siri")
    private static var held: (identifier: String, shuffled: Bool)?

    static func hold(_ identifier: String, shuffled: Bool) {
        log.notice("Siri asked for \(identifier, privacy: .public)")
        held = (identifier, shuffled)
        Task {
            try? await Task.sleep(for: .seconds(1))
            // Siri's answer is other audio: wait for it to finish, but not for ever.
            for _ in 0..<16 where AVAudioSession.sharedInstance().isOtherAudioPlaying {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard held?.identifier == identifier else { return }
            _ = await playHeld()
        }
    }

    /// What Siri asked for, now that it's done with the audio.
    static func playHeld() async -> Bool {
        guard let request = held else { return false }
        held = nil
        let played = await play(request.identifier, shuffled: request.shuffled)
        log.notice("Siri's \(request.identifier, privacy: .public): \(played ? "playing" : "nothing to play", privacy: .public)")
        return played
    }

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
        var songs = results.songs
        var albums = results.albums
        // "… by <artist>": only theirs. When the name finds none of theirs, their own songs and
        // albums are looked through too, then Siri is told what there is instead.
        if let by = query.artist, query.name != nil || query.album != nil {
            func theirs(_ line: String?) -> Bool { line?.localizedCaseInsensitiveContains(by) == true }
            songs = results.songs.filter { theirs($0.artistLine) }
            albums = results.albums.filter { theirs($0.albumArtist) }
            if songs.isEmpty || albums.isEmpty,
               let more = try? await MusicAPI.call({ try await $0.searchMusic(credential: $1, authHeader: $2, term: by) }) {
                if songs.isEmpty, let name = query.name {
                    songs = more.songs.filter { theirs($0.artistLine) && $0.name.localizedCaseInsensitiveContains(name) }
                }
                if albums.isEmpty, let name = query.album ?? query.name {
                    albums = more.albums.filter { theirs($0.albumArtist) && $0.name.localizedCaseInsensitiveContains(name) }
                }
            }
            let wantsAlbum = query.kind == .album || (query.name == nil && query.album != nil)
            if wantsAlbum ? albums.isEmpty : songs.isEmpty {
                let others = wantsAlbum
                    ? results.albums.prefix(3).map { Found(identifier: "album:\($0.id)", title: $0.name, type: .album, artist: $0.albumArtist) }
                    : results.songs.prefix(3).map { Found(identifier: "song:\($0.id)", title: $0.name, type: .song, artist: $0.artistLine) }
                log.notice("Siri: nothing called \(term, privacy: .public) by \(by, privacy: .public); offering \(others.count, privacy: .public)")
                return others.isEmpty ? .nothing : .choices(others)
            }
        }
        let song = (best(songs, named: query.name ?? term, \.name) ?? songs.first).map { Found(identifier: "song:\($0.id)", title: $0.name, type: .song, artist: $0.artistLine) }
        let album = best(albums, named: query.album ?? term, \.name)
            .map { Found(identifier: "album:\($0.id)", title: $0.name, type: .album, artist: $0.albumArtist) }
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
                : exact(song?.title, term) ? song
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
