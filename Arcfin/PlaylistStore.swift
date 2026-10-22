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
        ContainingSets.shared.invalidate()
        await load(credential: credential, authHeader: authHeader)
    }

    func create(named name: String, with items: [MediaItem], credential: ServerCredential, authHeader: String) async throws {
        try await client.createPlaylist(credential: credential, authHeader: authHeader, name: name, itemIds: items.map(\.id))
        ContainingSets.shared.invalidate()
        await load(credential: credential, authHeader: authHeader)
    }

    func clear() {
        playlists = []
        hasLoaded = false
        addingItem = nil
        PlayQueue.clear()
    }
}

/// Which collections and playlists hold each title, for its page. Jellyfin can list what a
/// collection or playlist holds but not the reverse, so this reads every one once (ids only,
/// eight at a time) and keeps the answer for ten minutes, or until a playlist changes here.
@MainActor
final class ContainingSets {
    static let shared = ContainingSets()

    private var collections: [String: [MediaItem]] = [:]
    private var playlists: [String: [MediaItem]] = [:]
    private var builtAt: Date?
    private var builtFor: String?
    private var building: Task<Void, Never>?
    private let client = JellyfinMediaClient()

    /// The collections and playlists holding any of `ids` (a title, and an episode's show).
    func sets(containing ids: [String], credential: ServerCredential, authHeader: String) async -> (collections: [MediaItem], playlists: [MediaItem]) {
        await ensureBuilt(credential: credential, authHeader: authHeader)
        func unique(_ found: [MediaItem]) -> [MediaItem] {
            var seen = Set<String>()
            return found.filter { seen.insert($0.id).inserted }
        }
        return (unique(ids.flatMap { collections[$0] ?? [] }), unique(ids.flatMap { playlists[$0] ?? [] }))
    }

    func invalidate() { builtAt = nil }

    private func ensureBuilt(credential: ServerCredential, authHeader: String) async {
        if let builtAt, builtFor == credential.userID, Date().timeIntervalSince(builtAt) < 600 { return }
        if let building { return await building.value }
        let task = Task { await build(credential: credential, authHeader: authHeader) }
        building = task
        await task.value
        building = nil
    }

    private func build(credential: ServerCredential, authHeader: String) async {
        async let fetchedCollections = client.getCollections(credential: credential, authHeader: authHeader)
        async let fetchedPlaylists = client.getPlaylists(credential: credential, authHeader: authHeader)
        let boxSets = (try? await fetchedCollections) ?? []
        let lists = ((try? await fetchedPlaylists) ?? []).map {
            MediaItem(id: $0.id, name: $0.name, type: .playlist, primaryImageTag: $0.primaryImageTag)
        }
        collections = await index(boxSets, credential: credential, authHeader: authHeader)
        playlists = await index(lists, credential: credential, authHeader: authHeader)
        builtAt = Date()
        builtFor = credential.userID
    }

    private func index(_ parents: [MediaItem], credential: ServerCredential, authHeader: String) async -> [String: [MediaItem]] {
        let client = client
        var result: [String: [MediaItem]] = [:]
        for batch in stride(from: 0, to: parents.count, by: 8).map({ Array(parents[$0..<min($0 + 8, parents.count)]) }) {
            await withTaskGroup(of: (MediaItem, [String]).self) { group in
                for parent in batch {
                    group.addTask {
                        (parent, (try? await client.getChildIds(credential: credential, authHeader: authHeader, parentId: parent.id)) ?? [])
                    }
                }
                for await (parent, childIds) in group {
                    for id in childIds { result[id, default: []].append(parent) }
                }
            }
        }
        return result
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
