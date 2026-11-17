// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI

/// A song's lyrics: the server's, or LRCLIB's when the server has none and Find Missing
/// Lyrics is on. What LRCLIB finds, or doesn't, is kept for the session so each song is only
/// looked up once.
@MainActor @Observable
final class MusicLyricsSource {
    static let shared = MusicLyricsSource()

    private var found: [String: Lyrics] = [:]
    @ObservationIgnored private var missing: Set<String> = []
    @ObservationIgnored private var lookups: [String: Task<Lyrics?, Never>] = [:]

    /// The lyrics button can be offered: the server has some, or LRCLIB found some.
    func isAvailable(_ song: MusicSong) -> Bool { song.hasLyrics || found[song.id] != nil }

    func lyrics(for song: MusicSong) async -> Lyrics? {
        if song.hasLyrics, let lyrics = try? await MusicAPI.call({
            try await $0.getLyrics(credential: $1, authHeader: $2, trackId: song.id)
        }) ?? nil, !lyrics.lines.isEmpty {
            return lyrics
        }
        return await lookUp(song)
    }

    /// Looks up a song that just started, so the lyrics button is ready.
    func prefetch(_ song: MusicSong) {
        guard !song.hasLyrics else { return }
        Task { _ = await lookUp(song) }
    }

    private func lookUp(_ song: MusicSong) async -> Lyrics? {
        guard MusicSettings.findsLyricsOnline, let artist = song.artists.first?.name ?? song.albumArtist,
              !missing.contains(song.id) else { return nil }
        if let lyrics = found[song.id] { return lyrics }
        if let lookup = lookups[song.id] { return await lookup.value }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let task = Task { [weak self] () -> Lyrics? in
            let result = try? await LRCLIBClient(clientVersion: version)
                .lyrics(track: song.name, artist: artist, album: song.albumName, duration: song.duration)
            guard let self else { return nil }
            lookups[song.id] = nil
            switch result {
            case .found(let lyrics):
                found[song.id] = lyrics
                return lyrics
            case .notFound:
                missing.insert(song.id)
                return nil
            case nil:
                // Couldn't ask, or asked to wait: tried again next time.
                return nil
            }
        }
        lookups[song.id] = task
        return await task.value
    }
}
