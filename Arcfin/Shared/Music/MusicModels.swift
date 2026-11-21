// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import MediaEngine
import Observation
import os
import SwiftUI
import Telemetry

/// Where a music screen leads.
enum MusicRoute: Hashable {
    case artists(libraryID: String)
    case albums(libraryID: String, title: String, genreID: String? = nil)
    case songs(libraryID: String)
    case favorites(libraryID: String)
    case genres(libraryID: String)
    case playlists
    case playlist(MusicPlaylist)
    case album(MusicAlbum)
    case artist(MusicArtist, libraryID: String?)
}

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
        MusicDownloads.shared.coverURL(albumID: album.id) ?? imageURL(itemID: album.id, tag: album.primaryImageTag, width: width)
    }

    static func artworkURL(_ artist: MusicArtist, width: Int = 400) -> URL? {
        imageURL(itemID: artist.id, tag: artist.primaryImageTag, width: width)
    }

    static func artworkURL(_ playlist: MusicPlaylist, width: Int = 400) -> URL? {
        imageURL(itemID: playlist.id, tag: playlist.primaryImageTag, width: width)
    }

    static func artworkURL(_ song: MusicSong, width: Int = 200) -> URL? {
        song.albumId.flatMap(MusicDownloads.shared.coverURL(albumID:)) ?? AppServices.music.artworkURL(for: song, width: width)
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
    /// The next page, when there's more: for jumping to something not loaded yet.
    func loadMore() async {
        guard hasLoaded, !isLoading, items.count < total else { return }
        await loadPage()
    }

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

/// Favourites changed here, over what the server sent, so every menu and button agrees.
@MainActor @Observable
final class MusicFavorites {
    static let shared = MusicFavorites()
    private var changed: [String: Bool] = [:]
    @ObservationIgnored private var edits = MusicEdits()

    func isFavorite(_ id: String, server: Bool) -> Bool { changed[id] ?? server }

    /// What the server said when asked at `asked`, unless it's been changed here since.
    func sync(_ id: String, isFavorite: Bool, asked: Date) {
        guard !edits.changed(id, since: asked) else { return }
        changed[id] = isFavorite
    }

    func toggle(_ id: String, server: Bool) {
        let before = isFavorite(id, server: server), favorite = !before
        changed[id] = favorite
        let edit = edits.begin(id)
        AppServices.music.ratingsChanged()
        Task {
            let saved = await MusicActions.setFavorite(id, favorite)
            edits.end(id, edit)
            if !saved, changed[id] == favorite {
                changed[id] = before
                AppServices.music.ratingsChanged()
            }
        }
        if favorite, MusicSettings.keepsFavoritesDownloaded {
            Task { await MusicDownloads.shared.downloadFavorite(id) }
        }
    }
}

/// Which favourites and ratings are being saved, so an older answer from the server can't
/// put back what was just changed.
struct MusicEdits {
    private var pending: [String: Int] = [:]
    private var last: [String: Date] = [:]
    private var count = 0

    mutating func begin(_ id: String) -> Int {
        count += 1
        pending[id] = count
        last[id] = .now
        return count
    }

    mutating func end(_ id: String, _ edit: Int) {
        if pending[id] == edit { pending[id] = nil }
    }

    func changed(_ id: String, since asked: Date) -> Bool {
        pending[id] != nil || (last[id].map { $0 >= asked } ?? false)
    }
}

/// Likes and dislikes changed here, over what the server sent. Saved to Jellyfin, and loved
/// or hated on ListenBrainz when the profile has it.
@MainActor @Observable
final class MusicRatings {
    static let shared = MusicRatings()
    private var changed: [String: Bool?] = [:]
    @ObservationIgnored private var edits = MusicEdits()

    func likes(_ id: String, server: Bool?) -> Bool? {
        if let local = changed[id] { return local }
        return server
    }

    /// What the server said when asked at `asked`, unless it's been changed here since.
    func sync(_ id: String, likes: Bool?, asked: Date) {
        guard !edits.changed(id, since: asked) else { return }
        changed[id] = .some(likes)
    }

    /// Rated elsewhere (ListenBrainz): shown here and saved to Jellyfin, not sent back.
    func adopt(_ id: String, likes: Bool) {
        save(id, likes, before: changed[id] ?? nil)
    }

    /// Tapping the one already chosen clears it.
    func set(_ id: String, likes: Bool, server: Bool?) {
        let before = self.likes(id, server: server)
        let value: Bool? = before == likes ? nil : likes
        save(id, value, before: before)
        AppServices.music.scrobbler.rated(id, likes: value)
    }

    private func save(_ id: String, _ value: Bool?, before: Bool?) {
        changed[id] = .some(value)
        let edit = edits.begin(id)
        AppServices.music.ratingsChanged()
        Task {
            let saved = await MusicActions.setLikes(id, value)
            edits.end(id, edit)
            if !saved, changed[id] == .some(value) {
                changed[id] = .some(before)
                AppServices.music.ratingsChanged()
            }
        }
    }
}

/// What Play, Shuffle and a row's menu do with songs.
@MainActor
enum MusicActions {
    static var player: MusicQueuePlayer { AppServices.music.player }

    static func play(_ songs: [MusicSong], from index: Int = 0) {
        AppServices.music.play(songs, startingAt: index)
    }

    static func shuffle(_ songs: [MusicSong]) {
        AppServices.music.play(songs, startingAt: Int.random(in: 0..<max(songs.count, 1)), shuffled: true)
    }

    static func playNext(_ songs: [MusicSong]) { AppServices.music.playNext(songs) }

    static func addToQueue(_ songs: [MusicSong]) { AppServices.music.addToQueue(songs) }

    static func playlistSongs(_ playlist: MusicPlaylist) async -> [MusicSong] {
        (try? await MusicAPI.call { try await $0.getPlaylistSongs(credential: $1, authHeader: $2, playlistId: playlist.id) }) ?? []
    }

    static func albumSongs(_ album: MusicAlbum) async -> [MusicSong] {
        (try? await MusicAPI.call { try await $0.getAlbumTracks(credential: $1, authHeader: $2, albumId: album.id) }) ?? []
    }

    static func instantMix(from itemID: String) async {
        let songs = (try? await MusicAPI.call { try await $0.getInstantMix(credential: $1, authHeader: $2, itemId: itemID) }) ?? []
        guard !songs.isEmpty else { return }
        play(songs)
    }

    private static let ratingLog = Telemetry.logger(category: "MusicRatings")

    /// Whether Jellyfin saved it.
    @discardableResult
    static func setFavorite(_ itemID: String, _ isFavorite: Bool) async -> Bool {
        do {
            try await MusicAPI.call { try await $0.markFavorite(credential: $1, authHeader: $2, itemId: itemID, favorite: isFavorite) }
            ratingLog.notice("Saved \(itemID, privacy: .public) as favorite \(isFavorite, privacy: .public)")
            return true
        } catch {
            ratingLog.error("Couldn't save \(itemID, privacy: .public) as favorite \(isFavorite, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Whether Jellyfin saved it; nil clears the like or dislike.
    static func setLikes(_ itemID: String, _ likes: Bool?) async -> Bool {
        let value = likes.map(String.init) ?? "-"
        do {
            try await MusicAPI.call { try await $0.setLikes(credential: $1, authHeader: $2, itemId: itemID, likes: likes) }
            ratingLog.notice("Saved \(itemID, privacy: .public) as likes \(value, privacy: .public)")
            return true
        } catch {
            ratingLog.error("Couldn't save \(itemID, privacy: .public) as likes \(value, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// Favorite, Like and Dislike as icons, for the players.
struct MusicRatingButtons: View {
    let song: MusicSong
    var showsFavorite = true
    var spacing: CGFloat = DT.Spacing.sm

    private var isFavorite: Bool { MusicFavorites.shared.isFavorite(song.id, server: song.isFavorite) }
    private var likes: Bool? { MusicRatings.shared.likes(song.id, server: song.likes) }

    var body: some View {
        HStack(spacing: spacing) {
            if showsFavorite {
                Button { MusicFavorites.shared.toggle(song.id, server: song.isFavorite) } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            Button { MusicRatings.shared.set(song.id, likes: true, server: song.likes) } label: {
                Image(systemName: likes == true ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .accessibilityLabel("Like")
            .accessibilityAddTraits(likes == true ? .isSelected : [])
            Button { MusicRatings.shared.set(song.id, likes: false, server: song.likes) } label: {
                Image(systemName: likes == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .accessibilityLabel("Dislike")
            .accessibilityAddTraits(likes == false ? .isSelected : [])
        }
        .contentTransition(.symbolEffect(.replace))
    }
}

/// Add to Favorites or Remove from Favorites, as it stands now.
struct MusicFavoriteButton: View {
    let id: String
    let server: Bool
    private var isFavorite: Bool { MusicFavorites.shared.isFavorite(id, server: server) }

    var body: some View {
        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
            MusicFavorites.shared.toggle(id, server: server)
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

/// Music in Browse search: artists, albums and songs, a moment after typing stops.
@MainActor @Observable
final class MusicSearchModel {
    private(set) var results = MusicSearchResults()
    /// Songs the server doesn't have, from Apple Music, when that's turned on.
    private(set) var appleMusic: [AppleMusicCatalog.Song] = []
    private(set) var isSearching = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func search(_ term: String) {
        task?.cancel()
        let term = term.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            results = MusicSearchResults()
            appleMusic = []
            isSearching = false
            return
        }
        isSearching = true
        task = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = try? await MusicAPI.call { try await $0.searchMusic(credential: $1, authHeader: $2, term: term) }
            guard !Task.isCancelled else { return }
            results = found ?? MusicSearchResults()
            isSearching = false
            let catalog = await AppleMusicCatalog.shared.search(term, excluding: results.songs)
            guard !Task.isCancelled else { return }
            appleMusic = catalog
        }
    }
}
