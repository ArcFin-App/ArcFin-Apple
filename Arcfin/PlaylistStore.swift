// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import AuthCore
import JellyfinAPI

/// The signed-in user's Jellyfin playlists, plus the "Add to Playlist" sheet's target. Shared
/// rather than injected: the add action lives in long-press menus all over the app, and the
/// sheet itself is hosted once at the tab root.
@Observable
@MainActor
final class PlaylistStore {
    static let shared = PlaylistStore()

    var playlists: [MediaPlaylist] = []
    var hasLoaded = false
    /// Set to show the Add to Playlist sheet for this title.
    var addingItem: MediaItem?

    private let client = JellyfinMediaClient()

    func load(credential: ServerCredential, authHeader: String) async {
        guard let fetched = try? await client.getPlaylists(credential: credential, authHeader: authHeader) else { return }
        playlists = fetched
        hasLoaded = true
    }

    func add(_ item: MediaItem, to playlist: MediaPlaylist, credential: ServerCredential, authHeader: String) async throws {
        try await client.addToPlaylist(credential: credential, authHeader: authHeader, playlistId: playlist.id, itemIds: [item.id])
        await load(credential: credential, authHeader: authHeader)
    }

    func create(named name: String, with items: [MediaItem], credential: ServerCredential, authHeader: String) async throws {
        try await client.createPlaylist(credential: credential, authHeader: authHeader, name: name, itemIds: items.map(\.id))
        await load(credential: credential, authHeader: authHeader)
    }

    func clear() {
        playlists = []
        hasLoaded = false
        addingItem = nil
        PlayQueue.clear()
    }
}

/// What plays after the current title when playing a playlist. The player asks it for the
/// next title before falling back to the series' own next episode.
@MainActor
enum PlayQueue {
    private(set) static var items: [MediaItem] = []

    static func start(_ items: [MediaItem]) { self.items = items }

    static func clear() { items = [] }

    static func item(after id: String) -> MediaItem? {
        guard let index = items.firstIndex(where: { $0.id == id }), index + 1 < items.count else { return nil }
        return items[index + 1]
    }

    static func item(before id: String) -> MediaItem? {
        guard let index = items.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return items[index - 1]
    }

    static func contains(_ id: String) -> Bool { items.contains { $0.id == id } }
}
