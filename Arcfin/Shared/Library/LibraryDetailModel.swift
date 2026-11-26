// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore
import Telemetry
import os

/// One library's or playlist's titles, with its filters, sort, paging and letter jumps, and a
/// playlist's edits and playback, shared by every platform's `LibraryDetailView`.
@MainActor @Observable
final class LibraryDetailModel {
    let library: JellyfinLibrary
    /// Set when this shows a playlist: the same grid, filters and sort as any library, plus
    /// playlist order, playing through it, and adding and removing titles.
    let playlist: MediaPlaylist?
    /// Opens the title picker straight away, for a playlist that was just created.
    let startsAddingTitles: Bool

    /// The Playlists tile Browse shows before the server has a Playlists library of its own.
    static let allPlaylistsID = "arcfin.playlists"

    // Playlist
    var playlistName: String?
    /// Playlist entry ids by item id, which removing a row needs.
    private(set) var entryIds: [String: String] = [:]
    var playlistPlayback: MediaDetailView.PlaybackRequest?
    var showAddTitles = false
    /// A whole show's episodes waiting for the person to confirm removing them.
    var pendingGroupRemoval: [MediaItem]?
    var showRename = false
    var renameText = ""
    var confirmDeletePlaylist = false
    var playlistError: String?
    var showNewPlaylist = false
    var newPlaylistName = ""
    var createdPlaylist: MediaPlaylist?
    private(set) var playlistTint: Color?
    /// The playlist itself, for artwork of its own.
    private(set) var playlistItem: MediaItem?
    private var checkedPlaylistItem = false

    private(set) var items: [MediaItem] = [] {
        didSet { gridEntries = makeGridEntries() }
    }
    /// The grid's cells, rebuilt when the titles or the sort change rather than on every
    /// render of a grid that can hold the whole library.
    private(set) var gridEntries: [GridEntry] = []
    private(set) var isLoading = true
    private(set) var isLoadingMore = false
    /// The last next-page request failed; the grid offers to try it again, since the cell
    /// that triggered it has already appeared.
    private(set) var loadMoreFailed = false
    /// The first page couldn't be fetched, as opposed to the library or filters having no titles.
    private(set) var loadFailed = false
    private(set) var totalItems = 0
    /// Where the next server page starts. Equals `items.count` unless genres are matched
    /// with "all", where the client drops titles from each server page.
    private var serverOffset = 0
    private var hasLoaded = false
    /// Set by the letter index; the grid scrolls (on Apple TV, moves focus) to this title.
    var jumpTarget: MediaItem.ID?
    private var isJumping = false
    /// The newest letter asked for while a jump or page load was still running; dragging
    /// along the index asks for every letter it passes.
    private var pendingJumpLetter: String?
    private let pageSize = 100
    /// Every filter/sort change spawns its own uncancelled fetchFirstPage() Task (see the
    /// onChange handlers in each LibraryDetailView) — nothing stopped an older, still-in-flight
    /// request from overwriting a newer one's results once it finally responded. Clicking
    /// through several filters quickly (easy with a mouse, less so with touch) could land a
    /// stale response for an earlier, narrower selection last, silently blanking out the
    /// correct one.
    private var fetchGeneration = 0
    private var filterReloadTask: Task<Void, Never>?

    // Filters
    private(set) var availableGenres: [String] = []
    private(set) var availableYears: [Int] = []
    private(set) var availableRatings: [String] = []
    private(set) var availableTags: [String] = []
    var extraFilters = LibraryExtraFilters()
    var selectedGenres: Set<String> = []
    var selectedYears: Set<Int> = []
    var watchedFilter: LibraryWatchedFilter
    var favoritesOnly = false
    var sortOption: LibrarySortOption = .nameAsc {
        didSet { gridEntries = makeGridEntries() }
    }
    var randomPick: MediaItem?
    private(set) var isPickingRandom = false
    /// Set while load() restores the saved sort, so the resulting onChange doesn't fire a
    /// second fetch on top of the initial one.
    private var restoringSort = false

    private let client = JellyfinMediaClient()

    init(library: JellyfinLibrary, playlist: MediaPlaylist?, startsAddingTitles: Bool) {
        self.library = library
        self.playlist = playlist
        self.startsAddingTitles = startsAddingTitles
        // Settings › Appearance › Hide Watched in Libraries; a playlist always shows everything.
        let hidesWatched = UserDefaults.standard.bool(forKey: "libraryHideWatched") && library.collectionType != .playlists
        watchedFilter = hidesWatched ? .unwatched : .all
    }

    /// The Playlists library itself (its titles are playlists), as opposed to one playlist.
    var isPlaylistsLibrary: Bool { library.collectionType == .playlists && playlist == nil }
    private var parentId: String { library.id == Self.allPlaylistsID ? "" : library.id }

    private var sortDefaultsKey: String { "librarySort.\(library.id)" }

    var filtersActive: Bool {
        !selectedGenres.isEmpty || !selectedYears.isEmpty || watchedFilter != .all || favoritesOnly
            || extraFilters.isActive
    }

    func clearFilters() {
        selectedGenres.removeAll()
        selectedYears.removeAll()
        extraFilters = LibraryExtraFilters()
        watchedFilter = .all
        favoritesOnly = false
    }

    /// The search field above the grid; the server matches it against the titles' names.
    var searchText = ""
    private var searchTerm: String? {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? nil : term
    }
    var isSearching: Bool { searchTerm != nil }
    var searchPrompt: LocalizedStringResource {
        if playlist != nil { return "Search This Playlist" }
        switch library.collectionType {
        case .movies:    return "Search Movies"
        case .tvshows:   return "Search Shows"
        case .boxsets:   return "Search Collections"
        case .playlists: return "Search Playlists"
        default:         return "Search This Library"
        }
    }

    private var matchesAllGenres: Bool { extraFilters.matchAllGenres && selectedGenres.count > 1 }
    private var hasMore: Bool { serverOffset < totalItems }
    var showsLetterIndex: Bool {
        sortOption == .nameAsc && playlist == nil && !matchesAllGenres && !isSearching && totalItems >= 50
    }
    var isCollections: Bool { library.collectionType == .boxsets }

    // Maps the library type to the items it should show.
    // .unknown = BoxSet contents (Movie+Series from within a collection).
    private var includeTypes: String? {
        switch library.collectionType {
        case .movies:  return "Movie"
        case .tvshows: return "Series"
        case .boxsets: return "BoxSet"
        case .music:   return "MusicAlbum"
        case .unknown: return "Movie,Series"   // inside a BoxSet
        case .playlists: return playlist == nil ? "Playlist" : nil
        default:       return nil
        }
    }

    var sortOptions: [LibrarySortOption] {
        playlist != nil ? LibrarySortOption.allCases : LibrarySortOption.standard
    }

    /// One grid cell: a title, or in a playlist a run of episodes from one show.
    struct GridEntry: Identifiable {
        let items: [MediaItem]
        var id: String { items[0].id }
    }

    /// A playlist holds a show as all of its episodes. In playlist order, three or more in a
    /// row from one show become a single card, so a whole series doesn't fill the page;
    /// one or two stay as they are, since those were most likely added one by one.
    private func makeGridEntries() -> [GridEntry] {
        guard playlist != nil, sortOption == .playlistOrder else { return items.map { GridEntry(items: [$0]) } }
        var entries: [GridEntry] = []
        var run: [MediaItem] = []
        func flush() {
            if run.count >= 3 {
                entries.append(GridEntry(items: run))
            } else {
                entries += run.map { GridEntry(items: [$0]) }
            }
            run = []
        }
        for item in items {
            if item.type == .episode, let seriesId = item.seriesId, run.first?.seriesId == seriesId {
                run.append(item)
            } else {
                flush()
                if item.type == .episode, item.seriesId != nil {
                    run = [item]
                } else {
                    entries.append(GridEntry(items: [item]))
                }
            }
        }
        flush()
        return entries
    }

    /// A title changed from its long-press menu, so its card shows the new state.
    func replace(_ item: MediaItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    func navTarget(for item: MediaItem) -> LibraryNavTarget {
        switch item.type {
        case .boxSet: .collection(item)
        case .playlist: .playlist(item)
        default: .media(item)
        }
    }

    func shouldLoadMore(after item: MediaItem) -> Bool {
        item.id == items.last?.id && hasMore && !isLoadingMore
    }

    /// The playlist's own backdrop when it has one, else its first title's.
    func playlistHeroURL(in mediaRepo: MediaRepository) -> URL? {
        // Not the first title's while the playlist's own may still come.
        guard checkedPlaylistItem else { return nil }
        if let own = playlistItem, !own.backdropImageTags.isEmpty {
            return mediaRepo.imageURL(for: own, type: .backdrop, fillWidth: 1200)
        }
        guard let first = items.first else { return nil }
        return mediaRepo.imageURL(for: first, type: .backdrop, fillWidth: 1200)
    }

    func loadPlaylistTint(mediaRepo: MediaRepository) async {
        guard playlist != nil, let url = playlistHeroURL(in: mediaRepo) else { return }
        playlistTint = await AverageColor.load(from: url)
    }

    // MARK: - Playlist playback and edits

    private var playableItems: [MediaItem] {
        items.filter { $0.type == .movie || $0.type == .episode }
    }

    func playAllFromStart() {
        guard let first = playableItems.first else { return }
        let ticks = first.userData?.played == true ? 0 : (first.userData?.playbackPositionTicks ?? 0)
        startPlaylistPlayback(from: first, startTicks: ticks)
    }

    func shufflePlaylist() {
        let shuffled = playableItems.shuffled()
        guard let first = shuffled.first else { return }
        PlayQueue.start(shuffled)
        playlistPlayback = MediaDetailView.PlaybackRequest(item: first, startTicks: 0)
    }

    /// Plays from `item` through the rest of the playlist in the order shown.
    func startPlaylistPlayback(from item: MediaItem, startTicks: Int64) {
        let playable = playableItems
        let start = playable.firstIndex(of: item) ?? 0
        PlayQueue.start(playable.isEmpty ? [item] : Array(playable[start...]))
        playlistPlayback = MediaDetailView.PlaybackRequest(item: item, startTicks: startTicks)
    }

    /// Creates it empty, then opens it straight into picking titles.
    func createPlaylist(authManager: AuthManager, mediaRepo: MediaRepository) {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaylistName = ""
        guard !name.isEmpty, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        Task {
            do {
                let id = try await client.createPlaylist(credential: cred, authHeader: header, name: name, itemIds: [])
                ContainingSets.shared.invalidate()
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
                await reload(authManager: authManager, mediaRepo: mediaRepo)
                createdPlaylist = MediaPlaylist(id: id, name: name, itemCount: 0)
            } catch {
                playlistError = error.localizedDescription
            }
        }
    }

    func removeFromPlaylist(_ item: MediaItem, authManager: AuthManager, mediaRepo: MediaRepository) {
        removeFromPlaylist([item], authManager: authManager, mediaRepo: mediaRepo)
    }

    func removeFromPlaylist(_ removed: [MediaItem], authManager: AuthManager, mediaRepo: MediaRepository) {
        let entries = removed.compactMap { entryIds[$0.id] }
        guard let playlist, !entries.isEmpty, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let removedIds = Set(removed.map(\.id))
        items.removeAll { removedIds.contains($0.id) }
        Task {
            do {
                try await client.removeFromPlaylist(credential: cred, authHeader: header, playlistId: playlist.id, entryIds: entries)
                ContainingSets.shared.invalidate()
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
            } catch {
                playlistError = error.localizedDescription
                await reload(authManager: authManager, mediaRepo: mediaRepo)
            }
        }
    }

    func renamePlaylist(_ name: String, authManager: AuthManager) {
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let playlist, !newName.isEmpty, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let oldName = playlistName
        playlistName = newName
        Task {
            do {
                try await client.renamePlaylist(credential: cred, authHeader: header, playlistId: playlist.id, name: newName)
                ContainingSets.shared.invalidate()
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
            } catch {
                playlistName = oldName
                playlistError = error.localizedDescription
            }
        }
    }

    func deletePlaylist(authManager: AuthManager, onDeleted: @escaping @MainActor () -> Void) {
        guard let playlist, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        Task {
            do {
                try await client.deletePlaylist(credential: cred, authHeader: header, playlistId: playlist.id)
                ContainingSets.shared.invalidate()
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
                onDeleted()
            } catch {
                playlistError = error.localizedDescription
            }
        }
    }

    // MARK: - Loading

    func load(authManager: AuthManager, mediaRepo: MediaRepository) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if playlistName == nil { playlistName = playlist?.name }
        let saved = UserDefaults.standard.string(forKey: sortDefaultsKey).flatMap(LibrarySortOption.init(rawValue:))
            ?? (playlist != nil ? .playlistOrder : nil)
        if let saved, saved != sortOption, sortOptions.contains(saved) {
            restoringSort = true
            sortOption = saved
        }
        if startsAddingTitles { showAddTitles = true }
        async let own: Void = loadPlaylistItem(authManager: authManager)
        await fetchFirstPage(authManager: authManager, mediaRepo: mediaRepo)
        await own
    }

    private func loadPlaylistItem(authManager: AuthManager) async {
        guard let playlist, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        playlistItem = try? await client.getItemDetail(credential: cred, authHeader: header, itemId: playlist.id).item
        checkedPlaylistItem = true
    }

    /// Re-fetches from the top with the current filter/sort selection — used whenever a
    /// filter or sort option changes, not just on first appearance.
    func reload(authManager: AuthManager, mediaRepo: MediaRepository) async {
        await fetchFirstPage(authManager: authManager, mediaRepo: mediaRepo)
    }

    /// Filter changes come in bursts (a slider dragged across its range, Clear All resetting
    /// five filters): only the last of a burst fetches.
    func filtersChanged(authManager: AuthManager, mediaRepo: MediaRepository) {
        filterReloadTask?.cancel()
        filterReloadTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await reload(authManager: authManager, mediaRepo: mediaRepo)
        }
    }

    /// Remembers the sort for this library, and reloads unless load() just restored it.
    func sortChanged(authManager: AuthManager, mediaRepo: MediaRepository) {
        UserDefaults.standard.set(sortOption.rawValue, forKey: sortDefaultsKey)
        if restoringSort { restoringSort = false; return }
        Task { await reload(authManager: authManager, mediaRepo: mediaRepo) }
    }

    private func fetchFirstPage(authManager: AuthManager, mediaRepo: MediaRepository) async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoading = true
        loadMoreFailed = false
        fetchGeneration += 1
        let generation = fetchGeneration
        // try? previously swallowed whatever went wrong here outright — a filter/sort
        // combination that made the server reject the request (or any other failure) just
        // silently rendered an empty grid with nothing to point at. Logged now so a real
        // report of that has something concrete behind it instead of another guess.
        var fetched: (items: [MediaItem], nextOffset: Int, total: Int)?
        if let playlist,
           let entries = try? await client.getPlaylistEntries(credential: cred, authHeader: header, playlistId: playlist.id) {
            entryIds = Dictionary(entries.map { ($0.item.id, $0.entryId) }, uniquingKeysWith: { first, _ in first })
            // Playlist order with no filters is the playlist itself, as it was put together.
            if sortOption == .playlistOrder, !filtersActive, !isSearching {
                guard generation == fetchGeneration else { return }
                loadFailed = false
                items = entries.map(\.item)
                serverOffset = items.count
                totalItems = items.count
                isLoading = false
                return
            }
        }
        do {
            fetched = try await fetchPage(credential: cred, header: header, startIndex: 0)
        } catch {
            let nsError = error as NSError
            Telemetry.logger(category: "LibraryView").error(
                "getLibraryItems failed for library \(self.library.id, privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
            )
        }
        // A newer filter/sort change already started another fetch while this one was still
        // in flight — applying this now-stale response would overwrite that newer request's
        // correct result with whatever this older, possibly narrower selection matched.
        guard generation == fetchGeneration else { return }
        loadFailed = fetched == nil
        items = fetched?.items ?? []
        serverOffset = fetched?.nextOffset ?? 0
        totalItems = fetched?.total ?? 0
        mediaRepo.prefetchQuickLookAssets(for: items)
        isLoading = false
    }

    /// One page under the current filters. With "match all genres" the server can only
    /// return titles matching *any* selected genre, so pages are narrowed here and further
    /// server pages are pulled until this one is reasonably full.
    private func fetchPage(
        credential: ServerCredential, header: String, startIndex: Int,
        limit: Int? = nil, sortBy: String? = nil, sortOrder: String? = nil, nameLessThan: String? = nil
    ) async throws -> (items: [MediaItem], nextOffset: Int, total: Int) {
        let limit = limit ?? pageSize
        var offset = startIndex
        var collected: [MediaItem] = []
        var total = 0
        var requests = 0
        repeat {
            let page = try await client.getLibraryItems(
                credential: credential, authHeader: header,
                libraryId: parentId, startIndex: offset, limit: limit,
                recursive: true,
                includeItemTypes: includeTypes,
                genres: Array(selectedGenres), requireAllGenres: matchesAllGenres,
                years: Array(selectedYears),
                officialRatings: Array(extraFilters.officialRatings), minCommunityRating: extraFilters.minRating,
                tags: Array(extraFilters.tags),
                isHD: extraFilters.quality == .hd ? true : nil,
                is4K: extraFilters.quality == .uhd ? true : nil,
                hasSubtitles: extraFilters.hasSubtitles ? true : nil,
                isPlayed: watchedFilter == .all ? nil : watchedFilter == .watched,
                isFavorite: favoritesOnly ? true : nil,
                nameLessThan: nameLessThan,
                searchTerm: searchTerm,
                sortBy: sortBy ?? sortOption.sortBy, sortOrder: sortOrder ?? sortOption.sortOrder
            )
            total = page.total
            offset += page.consumed
            collected += page.items
            requests += 1
            if page.consumed == 0 { offset = total }
        } while matchesAllGenres && collected.count < limit / 2 && offset < total && requests < 5
        return (collected, offset, total)
    }

    func loadMore(authManager: AuthManager) async {
        guard hasMore, !isLoadingMore else { return }
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoadingMore = true
        loadMoreFailed = false
        let generation = fetchGeneration
        let fetched = try? await fetchPage(credential: cred, header: header, startIndex: serverOffset)
        isLoadingMore = false
        // The filters or sort changed while this page loaded: it belongs to the old query.
        if generation == fetchGeneration {
            if let fetched {
                items.append(contentsOf: fetched.items)
                serverOffset = fetched.nextOffset
                totalItems = fetched.total
            } else {
                loadMoreFailed = true
            }
        }
        await runPendingJump(authManager: authManager)
    }

    /// The server counts the titles that sort before the letter, which is where it starts in
    /// the grid; the grid loads through that point if it hasn't yet, then jumps there.
    func jump(to letter: String, authManager: AuthManager) async {
        guard let cred = authManager.state.credential else { return }
        guard !isJumping, !isLoadingMore else {
            pendingJumpLetter = letter
            return
        }
        isJumping = true
        await performJump(to: letter, credential: cred, authManager: authManager)
        isJumping = false
        await runPendingJump(authManager: authManager)
    }

    private func runPendingJump(authManager: AuthManager) async {
        guard let next = pendingJumpLetter, !isJumping, !isLoadingMore else { return }
        pendingJumpLetter = nil
        await jump(to: next, authManager: authManager)
    }

    private func performJump(to letter: String, credential cred: ServerCredential, authManager: AuthManager) async {
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let generation = fetchGeneration
        var index = 0
        if letter != "#" {
            guard let counted = try? await fetchPage(
                credential: cred, header: header, startIndex: 0, limit: 1, nameLessThan: letter)
            else { return }
            index = counted.total
        }
        if index >= items.count, hasMore {
            isLoadingMore = true
            let fetched = try? await fetchPage(
                credential: cred, header: header, startIndex: serverOffset, limit: index - serverOffset + pageSize)
            isLoadingMore = false
            guard generation == fetchGeneration, let fetched else { return }
            items.append(contentsOf: fetched.items)
            serverOffset = fetched.nextOffset
            totalItems = fetched.total
        }
        guard generation == fetchGeneration, !items.isEmpty else { return }
        jumpTarget = items[min(index, items.count - 1)].id
    }

    /// Honors the active filters, so "Surprise me" on an unwatched-only view picks something
    /// unwatched.
    func pickRandom(authManager: AuthManager) async {
        guard let cred = authManager.state.credential else { return }
        isPickingRandom = true
        defer { isPickingRandom = false }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let result = try? await fetchPage(
            credential: cred, header: header, startIndex: 0, limit: matchesAllGenres ? pageSize : 1,
            sortBy: "Random", sortOrder: "Ascending")
        if let pick = result?.items.first {
            HapticManager.impact(.light)
            randomPick = pick
        }
    }

    func loadFilterOptions(authManager: AuthManager) async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let options: (genres: [String], years: [Int], officialRatings: [String], tags: [String])?
        do {
            options = try await client.getLibraryFilterOptions(
                credential: cred, authHeader: header, libraryId: parentId, includeItemTypes: includeTypes
            )
        } catch {
            Telemetry.logger(category: "LibraryView").error(
                "getLibraryFilterOptions failed for library \(self.library.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            options = nil
        }
        availableGenres = options?.genres ?? []
        availableYears = options?.years ?? []
        availableRatings = options?.officialRatings ?? []
        availableTags = options?.tags ?? []
    }
}

/// How a title reads on its grid card.
enum LibraryItemText {
    /// An episode (a playlist holds a show as its episodes) is shown as its show, with the
    /// season, episode and its own name underneath.
    static func title(_ item: MediaItem) -> String {
        item.type == .episode ? (item.seriesName ?? item.name) : item.name
    }

    static func subtitle(_ item: MediaItem) -> String? {
        guard item.type == .episode else { return item.productionYear.map { String($0) } }
        let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }
        return (code + (item.seriesName == nil ? [] : [item.name])).joined(separator: " · ").nilIfEmpty
    }

    @MainActor
    static func posterURL(_ item: MediaItem, in mediaRepo: MediaRepository) -> URL? {
        guard item.type == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag,
              let base = mediaRepo.baseURL, let token = mediaRepo.accessToken
        else { return mediaRepo.imageURL(for: item) }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: seriesId, tag: tag, type: .primary, fillWidth: 300, token: token)
    }

    /// A playlist's run of episodes from one show: how many, and from which seasons.
    static func showGroupSubtitle(_ episodes: [MediaItem]) -> String {
        let seasons = Set(episodes.compactMap(\.parentIndexNumber)).sorted()
        let seasonText = seasons.count > 1 ? "S\(seasons[0])–S\(seasons[seasons.count - 1])"
            : seasons.first.map { String(localized: "Season \($0)") }
        return ([String(localized: "\(episodes.count) episodes")] + [seasonText].compactMap { $0 }).joined(separator: " · ")
    }
}
