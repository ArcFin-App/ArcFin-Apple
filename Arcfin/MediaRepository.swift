// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import AuthCore
import JellyfinAPI
import SeerrAPI
import Telemetry
import Network
import ImageCache
import os

/// Races a one-shot NWPathMonitor read against a timeout — mirrors AuthManager's
/// TimeoutResult, which uses the same lock-guarded resume-once pattern for a system
/// callback with no bounded completion time of its own.
private final class PathWait: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<Void, Never>
    private let monitor = NWPathMonitor()

    init(continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func start(timeoutSeconds: Double) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            self?.finish()
        }
        monitor.start(queue: DispatchQueue(label: "arcfin.mediarepo.pathwait"))
        Task {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            self.finish()
        }
    }

    private func finish() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        monitor.cancel()
        continuation.resume()
    }
}

@Observable
@MainActor
final class MediaRepository {

    var continueWatching: [MediaItem] = []
    var recentlyAdded: [MediaItem] = []
    var nextUp: [MediaItem] = []
    var recentlyAddedMovies: [MediaItem] = []
    var recentlyAddedShows: [MediaItem] = []
    var recentlyReleasedMovies: [MediaItem] = []
    var recentlyAiredEpisodes: [MediaItem] = []
    var watchAgain: [MediaItem] = []
    /// A few random genres, each with unwatched titles — refreshed on every Home load.
    var genreShelves: [(genre: String, items: [MediaItem])] = []
    /// Titles the server admin tagged `arcfin-featured`, and those in collections tagged so,
    /// for the hero.
    var featuredItems: [MediaItem] = []
    /// Collections the server admin tagged `arcfin-promoted`, each its own Home row.
    var promotedCollections: [(collection: MediaItem, items: [MediaItem])] = []
    /// The most recently finished title and unwatched titles similar to it.
    var becauseYouWatched: (source: MediaItem, items: [MediaItem])?
    var favorites: [MediaItem] = []
    var topRatedUnwatched: [MediaItem] = []
    /// The server's picks for this user.
    var suggestions: [MediaItem] = []
    /// The server's recommendation rows: because you watched or liked something, its
    /// director, its cast.
    var recommendations: [MovieRecommendationCategory] = []
    var libraries: [JellyfinLibrary] = []
    /// Titles in each library, by library id, for the Browse tiles.
    var libraryCounts: [String: Int] = [:]
    /// TMDB keys (`JellyfinMediaClient.libraryKey`) of every movie and show the server has.
    var libraryTMDBKeys: Set<String> = []
    /// Whose library `libraryTMDBKeys` holds.
    @ObservationIgnored private var libraryTMDBKeysUserID: String?
    var serverID: String = ""
    var isLoading: Bool = false
    /// True when the last load couldn't reach the server at all (vs. a genuinely empty
    /// library) — HomeView surfaces this instead of silently rendering empty shelves.
    var connectionFailed: Bool = false
    /// Whether there's anything at all to show — MainTabView uses this alongside
    /// connectionFailed to decide between the full-screen NoConnectionView (nothing loaded
    /// yet, e.g. cold launch with no network) and just an inline banner over stale-but-still
    /// -useful content from an earlier successful load.
    var hasAnyContent: Bool {
        !libraries.isEmpty || !recentlyAdded.isEmpty || !continueWatching.isEmpty || !nextUp.isEmpty
    }

    private(set) var baseURL: URL?
    private(set) var accessToken: String?

    private let client = JellyfinMediaClient()
    private(set) var loaded = false
    private var lastLoadedAt: Date?
    private var lastLoadedUserID: String?

    /// Runs in its own task, so a caller being cancelled (pull to refresh ending, a view
    /// going away) can't cancel the requests halfway and leave a half-finished load.
    /// `shelfOrder` is Home's rows as they stand now, shuffled or not: after the hero and the
    /// first rows, the rest load one at a time in that order. Without one, the last is kept.
    func load(credential: ServerCredential, authClient: JellyfinAuthClient, force: Bool = false,
              shelfOrder: [HomeShelf]? = nil) async {
        if let shelfOrder { self.shelfOrder = shelfOrder }
        await Task { await performLoad(credential: credential, authClient: authClient, force: force) }.value
    }

    @ObservationIgnored private var shelfOrder: [HomeShelf] = HomeShelf.allCases
    @ObservationIgnored private var rowsTask: Task<Void, Never>?

    private func performLoad(credential: ServerCredential, authClient: JellyfinAuthClient, force: Bool) async {
        // Skip if already loaded within the last 60 s for the SAME profile — prevents
        // repeated API bursts when the view re-appears (tab switch, background/foreground).
        // A profile switch always reloads regardless of the cooldown. An explicit
        // user-initiated refresh (force: true) always bypasses it too.
        if !force, loaded, credential.userID == lastLoadedUserID,
           let t = lastLoadedAt, Date().timeIntervalSince(t) < 60 { return }
        // A load already running is for whoever asked last; a different profile's load waits
        // for it and then runs, rather than being dropped and leaving the old profile's shelves.
        guard !isLoading else {
            if credential.userID != loadingUserID { pendingLoad = (credential, authClient) }
            return
        }
        isLoading = true
        loadingUserID = credential.userID

        // AuthManager.checkStoredAuth() treats an unreachable validateToken call as "still
        // valid" (by design — a network blip shouldn't force a logout), so the app can reach
        // Home before the network path has actually come up, most visibly right at macOS
        // cold launch. Firing straight into a 13-request burst at that moment reliably lost
        // the race even with the retry backoff below, since a fixed delay is a guess rather
        // than a real check. Wait for NWPathMonitor to actually report a satisfied path first
        // (bounded, so a genuinely unreachable server still fails promptly) instead.
        await Self.waitForNetworkPath()

        var succeeded = await attemptLoad(credential: credential, authClient: authClient, attempt: 1)
        // A couple of silent retries with backoff cover any remaining transient failure
        // (e.g. the server itself still waking up) without masking a genuinely unreachable
        // server, which just fails all of them too.
        for (index, delay) in [1.5, 3].enumerated() where !succeeded {
            try? await Task.sleep(for: .seconds(delay))
            succeeded = await attemptLoad(credential: credential, authClient: authClient, attempt: index + 2)
        }

        isLoading = false
        loadingUserID = nil
        connectionFailed = !succeeded
        // Only cache-guard a successful load — a failed attempt shouldn't block Retry
        // behind the cooldown window.
        if succeeded {
            loaded = true
            lastLoadedAt = Date()
            lastLoadedUserID = credential.userID
        }
        if let next = pendingLoad {
            pendingLoad = nil
            await performLoad(credential: next.credential, authClient: next.authClient, force: true)
        }
    }

    @ObservationIgnored private var loadingUserID: String?
    @ObservationIgnored private var pendingLoad: (credential: ServerCredential, authClient: JellyfinAuthClient)?

    /// Seeded from the latest finished title; unwatched results only, since a "recommendation"
    /// the user has already seen isn't one.
    private func loadBecauseYouWatched(credential: ServerCredential, header: String) async -> (source: MediaItem, items: [MediaItem])? {
        guard let source = watchAgain.first,
              let similar = try? await client.getSimilar(credential: credential, authHeader: header, itemId: source.id)
        else { return nil }
        let items = similar.filter { $0.id != source.id && $0.userData?.played != true }
        return items.isEmpty ? nil : (source, items)
    }

    private static func waitForNetworkPath(timeoutSeconds: Double = 6) async {
        await withCheckedContinuation { continuation in
            PathWait(continuation: continuation).start(timeoutSeconds: timeoutSeconds)
        }
    }

    private func attemptLoad(credential: ServerCredential, authClient: JellyfinAuthClient, attempt: Int) async -> Bool {
        baseURL = credential.baseURL
        accessToken = credential.accessToken
        let header = authClient.authHeader(token: credential.accessToken)

        // A load for another profile, or a refresh, starts the rows over.
        rowsTask?.cancel()

        // First, together: what the hero and the first rows are made of. These also decide
        // whether the server answered at all.
        async let srvID   = client.getServerID(credential: credential)
        async let cw      = client.getContinueWatching(credential: credential, authHeader: header)
        async let nUp     = client.getNextUpIncludingRecent(credential: credential, authHeader: header)
        async let la      = client.getLatestMedia(credential: credential, authHeader: header)
        async let libs    = client.getLibraries(credential: credential, authHeader: header)
        async let featured = client.getTaggedCollections(credential: credential, authHeader: header, tag: "arcfin-featured")
        async let featuredTitles = client.getTaggedTitles(credential: credential, authHeader: header, tag: "arcfin-featured")

        // Every result is gathered first and only shown if the server answered: a failed or
        // cancelled attempt used to replace every shelf with an empty list, which with
        // nothing left to show swapped the whole app for the "Can't reach your server"
        // screen, tearing down even a player that was open on top.
        let succeeded: Bool
        do {
            let id = try await srvID
            succeeded = true
            serverID = id
        } catch {
            succeeded = false
            // getServerID is the pass/fail gate for the whole load — logged here (rather than
            // silently swallowed like the other calls) because "can't reach server" has
            // recurred across several rounds of fixes without a concrete error to point at.
            let nsError = error as NSError
            Telemetry.logger(category: "MediaRepository").error(
                "Home load attempt \(attempt, privacy: .public) failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
            )
        }
        let cwResult = (try? await cw) ?? []
        let nUpResult = (try? await nUp) ?? []
        let laResult = (try? await la) ?? []
        let libsResult = (try? await libs) ?? []
        let featuredResult = try? await featured
        let featuredTitlesResult = try? await featuredTitles
        guard succeeded else { return false }

        // Another profile's rows would otherwise stay up until each of this one's arrives.
        if credential.userID != lastLoadedUserID {
            recentlyAddedMovies = []; recentlyAddedShows = []; recentlyReleasedMovies = []
            recentlyAiredEpisodes = []; watchAgain = []; becauseYouWatched = nil; genreShelves = []
            favorites = []; topRatedUnwatched = []; suggestions = []; recommendations = []
            promotedCollections = []
        }
        continueWatching = cwResult
        nextUp           = nUpResult
        recentlyAdded    = laResult
        libraries        = libsResult
        if featuredResult != nil || featuredTitlesResult != nil {
            var seen = Set<String>()
            featuredItems = ((featuredTitlesResult ?? []) + (featuredResult ?? []).flatMap(\.items)).filter { seen.insert($0.id).inserted }
        }
        Task { await loadLibraryCounts(libsResult, credential: credential, header: header) }

        // Then the other rows one at a time, in Home's order, each shown as it arrives. Rows
        // turned off load last: Search and Spotlight use some of them too.
        let userID = credential.userID
        let order = shelfOrder + HomeShelf.allCases.filter { !shelfOrder.contains($0) }
        // The whole library's TMDB ids are kept until the library changes (LibraryChanged
        // refreshes them in refreshRecentlyAdded), not fetched again on every Home load.
        let needsKeys = libraryTMDBKeysUserID != userID
        rowsTask = Task {
            async let tmdbKeys = needsKeys ? client.getLibraryTMDBKeys(credential: credential, authHeader: header) : nil
            for shelf in order {
                guard !Task.isCancelled else { return }
                await loadRow(shelf, credential: credential, header: header, userID: userID)
            }
            if let keys = try? await tmdbKeys, !Task.isCancelled, lastLoadedUserID == userID || loadingUserID == userID {
                libraryTMDBKeys = keys
                libraryTMDBKeysUserID = userID
            }
        }

        return succeeded
    }

    /// One of Home's rows after the first ones. Rows that aren't from the library (Seerr,
    /// Live TV, Popular Elsewhere) load elsewhere.
    private func loadRow(_ shelf: HomeShelf, credential: ServerCredential, header: String, userID: String) async {
        func current() -> Bool { !Task.isCancelled && (loadingUserID ?? lastLoadedUserID) == userID }
        switch shelf {
        case .recentlyAddedMovies:
            let r = (try? await client.getLatestMedia(credential: credential, authHeader: header, itemTypes: "Movie")) ?? []
            if current() { recentlyAddedMovies = r }
        case .recentlyAddedShows:
            let r = (try? await client.getLatestMedia(credential: credential, authHeader: header, itemTypes: "Series")) ?? []
            if current() { recentlyAddedShows = r }
        case .recentlyReleasedMovies:
            let r = (try? await client.getRecentlyPremiered(credential: credential, authHeader: header, itemType: "Movie")) ?? []
            if current() { recentlyReleasedMovies = r }
        case .recentlyAiredEpisodes:
            let r = (try? await client.getRecentlyPremiered(credential: credential, authHeader: header, itemType: "Episode")) ?? []
            if current() { recentlyAiredEpisodes = r }
        case .watchAgain:
            let r = (try? await client.getWatchAgain(credential: credential, authHeader: header)) ?? []
            if current() { watchAgain = r }
        case .becauseYouWatched:
            // Seeded from Watch Again's first title, so that comes first when it hasn't yet.
            if watchAgain.isEmpty, let r = try? await client.getWatchAgain(credential: credential, authHeader: header), current() {
                watchAgain = r
            }
            let r = await loadBecauseYouWatched(credential: credential, header: header)
            if current() { becauseYouWatched = r }
        case .genreShelves:
            let r = (try? await client.getGenreShelves(credential: credential, authHeader: header)) ?? []
            if current() { genreShelves = r }
        case .favorites:
            let r = (try? await client.getFavorites(credential: credential, authHeader: header)) ?? []
            if current() { favorites = r }
        case .topRatedUnwatched:
            let r = (try? await client.getTopRatedUnwatched(credential: credential, authHeader: header)) ?? []
            if current() { topRatedUnwatched = r }
        case .suggested:
            let r = (try? await client.getSuggestions(credential: credential, authHeader: header)) ?? []
            if current() { suggestions = r }
        case .recommendations:
            let r = (try? await client.getMovieRecommendations(credential: credential, authHeader: header, categoryLimit: 4, itemLimit: 12)) ?? []
            if current() { recommendations = r.filter { $0.items.count >= 3 } }
        case .serverPicks:
            if let r = try? await client.getTaggedCollections(credential: credential, authHeader: header, tag: "arcfin-promoted"), current() {
                promotedCollections = r
            }
        case .continueWatching, .nextUp, .nowAvailable, .streamingServices,
             .seerrWatchlist, .seerrTrending, .seerrPopularMovies, .seerrPopularSeries,
             .liveFavoriteChannels, .liveOnNow, .liveRecentChannels:
            break
        }
    }

    /// After the main load, so Home doesn't wait on it; a library whose count fails keeps
    /// its last one.
    private func loadLibraryCounts(_ libraries: [JellyfinLibrary], credential: ServerCredential, header: String) async {
        let client = client
        await withTaskGroup(of: (String, Int?).self) { group in
            for library in libraries {
                group.addTask {
                    (library.id, try? await client.getLibraryItemCount(credential: credential, authHeader: header, library: library))
                }
            }
            for await (id, count) in group {
                if let count { libraryCounts[id] = count }
            }
        }
    }

    /// Shelves that follow watched state and favourites, after a change on another device.
    func refreshWatchState(credential: ServerCredential, authClient: JellyfinAuthClient) async {
        guard loaded, !isLoading else { return }
        let header = authClient.authHeader(token: credential.accessToken)
        async let cw = client.getContinueWatching(credential: credential, authHeader: header)
        async let nUp = client.getNextUpIncludingRecent(credential: credential, authHeader: header)
        async let wAgain = client.getWatchAgain(credential: credential, authHeader: header)
        async let favs = client.getFavorites(credential: credential, authHeader: header)
        let cwValue = try? await cw, nUpValue = try? await nUp, wAgainValue = try? await wAgain, favsValue = try? await favs
        // A profile switch while this was out: these are the old profile's, not the shelves'.
        guard credential.userID == lastLoadedUserID, !isLoading else { return }
        // Only what changed: this runs every few seconds while anything plays, and each
        // assignment re-renders Home behind the player.
        if let cwValue, cwValue != continueWatching { continueWatching = cwValue }
        if let nUpValue, nUpValue != nextUp { nextUp = nUpValue }
        if let wAgainValue, wAgainValue != watchAgain { watchAgain = wAgainValue }
        if let favsValue, favsValue != favorites { favorites = favsValue }
    }

    /// Puts a title's changed watched or favourite state on every shelf card showing it.
    func applyUserData(of item: MediaItem) {
        func apply(_ items: inout [MediaItem]) {
            for index in items.indices where items[index].id == item.id {
                items[index].userData = item.userData
            }
        }
        apply(&continueWatching)
        apply(&recentlyAdded)
        apply(&nextUp)
        apply(&recentlyAddedMovies)
        apply(&recentlyAddedShows)
        apply(&recentlyReleasedMovies)
        apply(&recentlyAiredEpisodes)
        apply(&watchAgain)
        apply(&featuredItems)
        apply(&favorites)
        apply(&topRatedUnwatched)
        apply(&suggestions)
    }

    /// Shelves that follow what's in the library, after titles are added or removed.
    func refreshRecentlyAdded(credential: ServerCredential, authClient: JellyfinAuthClient) async {
        guard loaded, !isLoading else { return }
        let header = authClient.authHeader(token: credential.accessToken)
        async let la = client.getLatestMedia(credential: credential, authHeader: header)
        async let raMov = client.getLatestMedia(credential: credential, authHeader: header, itemTypes: "Movie")
        async let raShow = client.getLatestMedia(credential: credential, authHeader: header, itemTypes: "Series")
        async let tmdbKeys = client.getLibraryTMDBKeys(credential: credential, authHeader: header)
        let laValue = try? await la, raMovValue = try? await raMov, raShowValue = try? await raShow, keysValue = try? await tmdbKeys
        guard credential.userID == lastLoadedUserID, !isLoading else { return }
        if let laValue { recentlyAdded = laValue }
        if let raMovValue { recentlyAddedMovies = raMovValue }
        if let raShowValue { recentlyAddedShows = raShowValue }
        if let keysValue {
            libraryTMDBKeys = keysValue
            libraryTMDBKeysUserID = credential.userID
        }
    }

    /// Whether the server already has a Seerr title: Seerr says so, or the library holds its
    /// TMDB id (Seerr's own status lags until it next scans the library).
    func hasInLibrary(_ item: SeerrItem) -> Bool {
        item.availabilityStatus == .available
            || libraryTMDBKeys.contains(JellyfinMediaClient.libraryKey(tmdbId: item.id, isSeries: item.mediaType == .tv))
    }

    /// nil when the server couldn't be asked, as opposed to no matches.
    func search(query: String, credential: ServerCredential, authClient: JellyfinAuthClient) async -> [MediaItem]? {
        guard !query.isEmpty else { return [] }
        let header = authClient.authHeader(token: credential.accessToken)
        return try? await client.search(credential: credential, authHeader: header, query: query)
    }

    func searchIfAuthenticated(query: String, authState: AuthState, authClient: JellyfinAuthClient) async -> [MediaItem]? {
        guard case .authenticated(let cred) = authState else { return [] }
        return await search(query: query, credential: cred, authClient: authClient)
    }

    func imageURL(for item: MediaItem, type: JellyfinImageType = .primary, fillWidth: Int = 300) -> URL? {
        guard let base = baseURL, let token = accessToken else { return nil }
        let tag: String?
        switch type {
        case .backdrop: tag = item.backdropImageTags.first
        case .thumb:    tag = item.thumbImageTag ?? item.backdropImageTags.first
        default:        tag = item.primaryImageTag
        }
        // An episode's own Primary image IS its screenshot — a much better backdrop
        // substitute than falling straight to the series' generic backdrop, since it's
        // specific to the episode actually being shown.
        if tag == nil, type == .backdrop, item.type == .episode, let episodeTag = item.primaryImageTag {
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: episodeTag,
                                                type: .primary, fillWidth: fillWidth, token: token)
        }
        // Otherwise, only truly parentless episodes (no own image at all) fall back to
        // the series/season backdrop.
        if tag == nil, type == .backdrop,
           let parentId = item.parentBackdropItemId ?? item.seriesId,
           let parentTag = item.parentBackdropImageTags.first {
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: parentId, tag: parentTag,
                                                type: .backdrop, fillWidth: fillWidth, token: token)
        }
        // BoxSets only have Primary; fall back to it when thumb/backdrop are absent.
        if tag == nil, item.type == .boxSet, let primary = item.primaryImageTag {
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: primary,
                                                type: .primary, fillWidth: fillWidth, token: token)
        }
        guard let tag else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: tag, type: type == .thumb && item.thumbImageTag == nil ? .backdrop : type, fillWidth: fillWidth, token: token)
    }

    // On tvOS: landscape thumb for movies/shows, episode primary for episodes (landscape screenshot).
    // BoxSets only carry a Primary poster — skip the thumb/backdrop path entirely.
    func tvImageURL(for item: MediaItem, fillWidth: Int = 500) -> URL? {
        guard let base = baseURL, let token = accessToken else { return nil }
        if item.type == .episode {
            guard let tag = item.primaryImageTag else { return nil }
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: tag, type: .primary, fillWidth: fillWidth, token: token)
        }
        if item.type == .boxSet, let tag = item.primaryImageTag {
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: tag, type: .primary, fillWidth: fillWidth, token: token)
        }
        return imageURL(for: item, type: .thumb, fillWidth: fillWidth)
    }

    /// An episode's show artwork in landscape: the series backdrop the episode carries.
    func seriesBackdropURL(for item: MediaItem, fillWidth: Int) -> URL? {
        guard let base = baseURL, let token = accessToken,
              let parentId = item.parentBackdropItemId ?? item.seriesId,
              let tag = item.parentBackdropImageTags.first else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: parentId, tag: tag,
                                            type: .backdrop, fillWidth: fillWidth, token: token)
    }

    // Episode screenshot — uses the episode's own Primary (screenshot) or Thumb image,
    // bypassing the episode→series poster redirect in imageURL(for:type:).
    func episodeThumbnailURL(for item: MediaItem, fillWidth: Int = 240) -> URL? {
        guard let base = baseURL, let token = accessToken else { return nil }
        if let tag = item.thumbImageTag {
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: tag,
                                                type: .thumb, fillWidth: fillWidth, token: token)
        }
        if let tag = item.primaryImageTag {
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: tag,
                                                type: .primary, fillWidth: fillWidth, token: token)
        }
        return nil
    }

    func libraryBackdropURL(for library: JellyfinLibrary, fillWidth: Int = 700) -> URL? {
        guard let base = baseURL, let token = accessToken, let tag = library.backdropImageTag else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: library.id, tag: tag,
                                            type: .backdrop, fillWidth: fillWidth, token: token)
    }

    /// A Live TV channel logo, programme still or series-timer poster.
    func primaryImageURL(itemID: String, tag: String?, fillWidth: Int = 200) -> URL? {
        guard let base = baseURL, let token = accessToken, let tag else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: itemID, tag: tag,
                                            type: .primary, fillWidth: fillWidth, token: token)
    }

    func personImageURL(personId: String, tag: String, fillWidth: Int = 120) -> URL? {
        guard let base = baseURL, let token = accessToken else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: personId, tag: tag,
                                            type: .primary, fillWidth: fillWidth, token: token)
    }

    func logoURL(for item: MediaItem) -> URL? {
        logoURL(itemID: item.id)
    }

    func logoURL(itemID: String, fillWidth: Int = 300) -> URL? {
        guard let base = baseURL, let token = accessToken else { return nil }
        var comps = URLComponents(url: base.appendingPathComponent("Items/\(itemID)/Images/Logo"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "fillWidth", value: "\(fillWidth)"),
            .init(name: "quality", value: "90"),
            .init(name: "api_key", value: token),
        ]
        return comps.url
    }

    func prefetchQuickLookAssets(for items: [MediaItem], limit: Int = 24) {
        let urls = Array(items.prefix(limit)).flatMap { item -> [URL] in
            var itemURLs: [URL] = []
            if let backdropURL = imageURL(for: item, type: .backdrop, fillWidth: 600) {
                itemURLs.append(backdropURL)
            }
            if let logoURL = logoURL(for: item) {
                itemURLs.append(logoURL)
            }
            return itemURLs
        }
        prefetch(urls: urls)
    }

    /// Into the image pipeline's own disk cache: URLSession's cache, used before, was never
    /// read by the image views, so every prefetched image downloaded twice.
    func prefetch(urls: [URL]) {
        ImageCache.prefetch(urls: urls)
    }
}
