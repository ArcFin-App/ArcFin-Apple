// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
import MusicKit
import os
import Telemetry

/// Apple Music for the songs the server doesn't have, for a subscriber who turned it on:
/// found in search, and played by Apple Music's own player, with Arcfin's paused.
@MainActor @Observable
final class AppleMusicCatalog {
    static let shared = AppleMusicCatalog()

    struct Song: Identifiable, Hashable {
        let id: String
        let title: String
        let artist: String
        let album: String?
        let artworkURL: URL?
    }

    /// The person allowed it and their subscription plays the catalog.
    private(set) var canPlay = false
    /// Set when it's turned on and something stands in the way.
    private(set) var problem: String?
    @ObservationIgnored private var songs: [String: MusicKit.Song] = [:]
    @ObservationIgnored private let log = Telemetry.logger(category: "AppleMusic")

    func requestAccess() async {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            canPlay = false
            problem = String(localized: "Arcfin isn't allowed to use Apple Music. Allow it in Settings › Privacy & Security › Media & Apple Music.")
            return
        }
        await refreshSubscription()
    }

    private func refreshSubscription() async {
        do {
            canPlay = try await MusicSubscription.current.canPlayCatalogContent
            problem = canPlay ? nil : String(localized: "Your Apple ID doesn't have an Apple Music subscription that plays songs.")
        } catch {
            canPlay = false
            problem = String(localized: "Apple Music couldn't be reached. \(error.localizedDescription)")
            log.error("Subscription check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Up to ten catalog songs for the term, leaving out what the library already has.
    func search(_ term: String, excluding library: [MusicSong]) async -> [Song] {
        guard MusicSettings.usesAppleMusic, MusicAuthorization.currentStatus == .authorized else { return [] }
        if !canPlay { await refreshSubscription() }
        guard canPlay else { return [] }
        var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
        request.limit = 10
        guard let response = try? await request.response() else { return [] }
        let owned = Set(library.map { Self.key($0.name, $0.artistLine ?? "") })
        return response.songs.compactMap { song in
            guard !owned.contains(Self.key(song.title, song.artistName)) else { return nil }
            songs[song.id.rawValue] = song
            return Song(id: song.id.rawValue, title: song.title, artist: song.artistName, album: song.albumTitle,
                        artworkURL: song.artwork?.url(width: 200, height: 200))
        }
    }

    private static func key(_ title: String, _ artist: String) -> String {
        "\(title.lowercased())\u{1F}\(artist.lowercased())"
    }

    /// Plays it in Apple Music's player; Arcfin's music pauses first.
    func play(_ song: Song) async {
        guard let catalogSong = songs[song.id] else { return }
        AppServices.music.pause()
        let player = ApplicationMusicPlayer.shared
        player.queue = [catalogSong]
        do {
            try await player.play()
        } catch {
            problem = String(localized: "Apple Music couldn't play it. \(error.localizedDescription)")
            log.error("Couldn't play \(song.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
