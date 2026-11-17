// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SwiftUI
import JellyfinAPI
import os
import Telemetry

/// A song's lyrics: the server's, or LRCLIB's when the server has none and Find Missing
/// Lyrics is on. What LRCLIB finds, or doesn't, is kept for the session so each song is only
/// looked up once.
@MainActor @Observable
final class MusicLyricsSource {
    static let shared = MusicLyricsSource()

    private var found: [String: Lyrics] = [:]
    @ObservationIgnored private var missing: Set<String> = []
    @ObservationIgnored private var lookups: [String: Task<Lyrics?, Never>] = [:]
    @ObservationIgnored private let log = Telemetry.logger(category: "MusicLyrics")

    /// The lyrics button can be offered: the server has some, or LRCLIB found some.
    func isAvailable(_ song: MusicSong) -> Bool {
        song.hasLyrics || MusicDownloads.shared.hasLyrics(song.id)
            || (MusicSettings.findsLyricsOnline && found[song.id] != nil)
    }

    func lyrics(for song: MusicSong) async -> Lyrics? {
        // Saved with a download, so they're there offline.
        if let saved = MusicDownloads.shared.lyrics(for: song.id) { return saved }
        if song.hasLyrics, let lyrics = try? await MusicAPI.call({
            try await $0.getLyrics(credential: $1, authHeader: $2, trackId: song.id)
        }) ?? nil, !lyrics.lines.isEmpty {
            return lyrics
        }
        return await lookUp(song)
    }

    /// The lyrics to save with a download: the server's, or LRCLIB's when the setting is on.
    func lyricsToSave(for song: MusicSong) async -> Lyrics? {
        if song.hasLyrics, let lyrics = try? await MusicAPI.call({
            try await $0.getLyrics(credential: $1, authHeader: $2, trackId: song.id)
        }) ?? nil, !lyrics.lines.isEmpty {
            return lyrics
        }
        return await lookUp(song)
    }

    // MARK: Timing

    /// How much later than LRCLIB's times each song's lines should show, in seconds, for a
    /// recording that starts later or earlier than the one they were timed to.
    private(set) var delays: [String: Double] = UserDefaults.standard.dictionary(forKey: delaysKey) as? [String: Double] ?? [:]
    private static let delaysKey = "musicLyricsDelays"

    func delay(_ songID: String) -> Double { delays[songID] ?? 0 }

    /// Sets a song's timing so this line is the one being sung now.
    func align(_ songID: String, line: Lyrics.Line, to position: Double) {
        guard let start = line.start else { return }
        let value = ((position - start) * 10).rounded() / 10
        delays[songID] = value == 0 ? nil : value
        UserDefaults.standard.set(delays, forKey: Self.delaysKey)
    }

    /// Moves a song's lines later (positive) or earlier, or back (nil).
    func adjust(_ songID: String, by step: Double?) {
        let value = step.map { ((delay(songID) + $0) * 10).rounded() / 10 } ?? 0
        delays[songID] = value == 0 ? nil : value
        UserDefaults.standard.set(delays, forKey: Self.delaysKey)
    }

    /// The line being sung, with the song's timing applied.
    func lineIndex(_ lyrics: Lyrics, songID: String, at position: Double) -> Int? {
        lyrics.isSynced ? lyrics.lineIndex(at: position - delay(songID)) : nil
    }

    /// Looks up a song that just started, so the lyrics button is ready.
    func prefetch(_ song: MusicSong) {
        guard !song.hasLyrics else { return }
        Task { _ = await lookUp(song) }
    }

    private func lookUp(_ song: MusicSong) async -> Lyrics? {
        guard MusicSettings.findsLyricsOnline else {
            log.notice("Lyrics: none on the server for \(song.id, privacy: .public), and Find Missing Lyrics is off")
            return nil
        }
        guard let artist = song.artists.first?.name ?? song.albumArtist, !missing.contains(song.id) else { return nil }
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
                log.notice("Lyrics: LRCLIB found \(lyrics.lines.count, privacy: .public) lines (\(lyrics.isSynced ? "synced" : "plain", privacy: .public)) for \(song.id, privacy: .public)")
                return lyrics
            case .notFound:
                missing.insert(song.id)
                log.notice("Lyrics: LRCLIB has none for \(song.id, privacy: .public)")
                return nil
            case nil:
                log.notice("Lyrics: LRCLIB couldn't be reached for \(song.id, privacy: .public)")
                // Couldn't ask, or asked to wait: tried again next time.
                return nil
            }
        }
        lookups[song.id] = task
        return await task.value
    }
}

/// Shows a song's synced lines earlier or later, for a recording that runs ahead of or behind
/// the times they came with. Kept for the song on this device.
struct MusicLyricsTimingMenu: View {
    let songID: String
    private var delay: Double { MusicLyricsSource.shared.delay(songID) }

    var body: some View {
        Menu {
            Section {
                Button("Show Lines 2 s Earlier", systemImage: "backward") { MusicLyricsSource.shared.adjust(songID, by: -2) }
                Button("Show Lines 0.5 s Earlier", systemImage: "backward.frame") { MusicLyricsSource.shared.adjust(songID, by: -0.5) }
                Button("Show Lines 0.5 s Later", systemImage: "forward.frame") { MusicLyricsSource.shared.adjust(songID, by: 0.5) }
                Button("Show Lines 2 s Later", systemImage: "forward") { MusicLyricsSource.shared.adjust(songID, by: 2) }
            }
            if delay != 0 {
                Button("Reset Timing", systemImage: "arrow.counterclockwise") { MusicLyricsSource.shared.adjust(songID, by: nil) }
            }
        } label: {
            Label {
                if delay == 0 {
                    Text("Timing")
                } else {
                    Text(verbatim: delay.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " s")
                }
            } icon: {
                Image(systemName: "timer")
            }
        }
        .accessibilityLabel("Lyrics Timing")
    }
}
