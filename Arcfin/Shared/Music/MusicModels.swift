// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import MediaEngine
import Observation

/// Music calls as the signed-in profile.
@MainActor
enum MusicAPI {
    static let client = JellyfinMediaClient()

    static func call<T: Sendable>(
        _ body: (JellyfinMediaClient, ServerCredential, String) async throws -> T
    ) async throws -> T {
        let auth = AppServices.authManager
        guard let credential = auth.state.credential else { throw URLError(.userAuthenticationRequired) }
        return try await body(client, credential, auth.authClient.authHeader(token: credential.accessToken))
    }

    static func imageURL(itemID: String, tag: String?, width: Int) -> URL? {
        guard let tag, let credential = AppServices.authManager.state.credential else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: itemID, tag: tag,
                                            fillWidth: width, token: credential.accessToken)
    }

    static func artworkURL(_ album: MusicAlbum, width: Int = 400) -> URL? {
        imageURL(itemID: album.id, tag: album.primaryImageTag, width: width)
    }

    static func artworkURL(_ artist: MusicArtist, width: Int = 400) -> URL? {
        imageURL(itemID: artist.id, tag: artist.primaryImageTag, width: width)
    }

    static func artworkURL(_ song: MusicSong, width: Int = 200) -> URL? {
        AppServices.music.artworkURL(for: song, width: width)
    }
}

/// A list the server sends a page at a time; the next page loads as the end comes into view.
@MainActor @Observable
final class MusicPagedList<Item: Identifiable & Sendable> {
    private(set) var items: [Item] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var hasFailed = false
    private(set) var hasLoaded = false

    @ObservationIgnored private let fetch: (Int) async throws -> ([Item], Int)
    @ObservationIgnored private var generation = 0

    init(fetch: @escaping (_ startIndex: Int) async throws -> ([Item], Int)) {
        self.fetch = fetch
    }

    func reload() async {
        generation += 1
        items = []
        total = 0
        hasLoaded = false
        await loadPage()
    }

    func loadIfNeeded() async {
        if !hasLoaded, !isLoading { await loadPage() }
    }

    /// Call from each row's onAppear.
    func rowAppeared(_ item: Item) async {
        guard !isLoading, items.count < total,
              let index = items.lastIndex(where: { $0.id == item.id }), index >= items.count - 20 else { return }
        await loadPage()
    }

    private func loadPage() async {
        let started = generation
        isLoading = true
        defer { if started == generation { isLoading = false } }
        do {
            let (page, total) = try await fetch(items.count)
            guard started == generation else { return }
            items += page
            self.total = total
            hasFailed = false
        } catch {
            guard started == generation, !(error is CancellationError) else { return }
            hasFailed = true
        }
        hasLoaded = true
    }
}

/// What Play, Shuffle and a row's menu do with songs.
@MainActor
enum MusicActions {
    static var player: MusicQueuePlayer { AppServices.music.player }

    static func play(_ songs: [MusicSong], from index: Int = 0) {
        player.play(songs, startingAt: index)
    }

    static func shuffle(_ songs: [MusicSong]) {
        player.play(songs, startingAt: Int.random(in: 0..<max(songs.count, 1)), shuffled: true)
    }

    static func playNext(_ songs: [MusicSong]) { player.playNext(songs) }

    static func addToQueue(_ songs: [MusicSong]) { player.addToQueue(songs) }

    static func albumSongs(_ album: MusicAlbum) async -> [MusicSong] {
        (try? await MusicAPI.call { try await $0.getAlbumTracks(credential: $1, authHeader: $2, albumId: album.id) }) ?? []
    }

    static func instantMix(from itemID: String) async {
        let songs = (try? await MusicAPI.call { try await $0.getInstantMix(credential: $1, authHeader: $2, itemId: itemID) }) ?? []
        guard !songs.isEmpty else { return }
        play(songs)
    }

    static func setFavorite(_ itemID: String, _ isFavorite: Bool) async {
        _ = try? await MusicAPI.call {
            try await $0.markFavorite(credential: $1, authHeader: $2, itemId: itemID, favorite: isFavorite)
        }
    }
}

extension TimeInterval {
    /// 3:07, or 1:02:07 past an hour.
    var musicTime: String {
        let total = Int(self.rounded(.down))
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                         : String(format: "%d:%02d", minutes, seconds)
    }
}
