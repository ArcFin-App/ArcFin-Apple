// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import AuthCore
import JellyfinAPI
import SeerrAPI
import Telemetry
import Network
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
    /// TMDB keys (`JellyfinMediaClient.libraryKey`) of every movie and show the server has.
    var libraryTMDBKeys: Set<String> = []
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
    private var loaded = false
    private var lastLoadedAt: Date?
    private var lastLoadedUserID: String?

    /// Runs in its own task, so a caller being cancelled (pull to refresh ending, a view
    /// going away) can't cancel the requests halfway and leave a half-finished load.
    func load(credential: ServerCredential, authClient: JellyfinAuthClient, force: Bool = false) async {
        await Task { await performLoad(credential: credential, authClient: authClient, force: force) }.value
    }

    private func performLoad(credential: ServerCredential, authClient: JellyfinAuthClient, force: Bool) async {
        // Skip if already loaded within the last 60 s for the SAME profile — prevents
        // repeated API bursts when the view re-appears (tab switch, background/foreground).
        // A profile switch always reloads regardless of the cooldown. An explicit
        // user-initiated refresh (force: true) always bypasses it too.
        if !force, loaded, credential.userID == lastLoadedUserID,
           let t = lastLoadedAt, Date().timeIntervalSince(t) < 60 { return }
        guard !isLoading else { return }
        isLoading = true

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
        connectionFailed = !succeeded
        // Only cache-guard a successful load — a failed attempt shouldn't block Retry
        // behind the cooldown window.
        if succeeded {
            loaded = true
            lastLoadedAt = Date()
            lastLoadedUserID = credential.userID
        }
    }

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

        async let cw      = client.getContinueWatching(credential: credential, authHeader: header)
        async let la      = client.getLatestMedia(credential: credential, authHeader: header)
        async let libs    = client.getLibraries(credential: credential, authHeader: header)
        async let srvID   = client.getServerID(credential: credential)
        async let nUp     = client.getNextUp(credential: credential, authHeader: header)
        async let raMov   = client.getLatestMedia(credential: credential, authHeader: header, itemTypes: "Movie")
        async let raShow  = client.getLatestMedia(credential: credential, authHeader: header, itemTypes: "Series")
        async let rrMov   = client.getRecentlyPremiered(credential: credential, authHeader: header, itemType: "Movie")
        async let raEp    = client.getRecentlyPremiered(credential: credential, authHeader: header, itemType: "Episode")
        async let wAgain  = client.getWatchAgain(credential: credential, authHeader: header)
        async let genres  = client.getGenreShelves(credential: credential, authHeader: header)
        async let favs    = client.getFavorites(credential: credential, authHeader: header)
        async let topUnw  = client.getTopRatedUnwatched(credential: credential, authHeader: header)
        async let sugg    = client.getSuggestions(credential: credential, authHeader: header)
        async let recs    = client.getMovieRecommendations(credential: credential, authHeader: header, categoryLimit: 4, itemLimit: 12)
        async let tmdbKeys = client.getLibraryTMDBKeys(credential: credential, authHeader: header)

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
        let laResult = (try? await la) ?? []
        let libsResult = (try? await libs) ?? []
        let nUpResult = (try? await nUp) ?? []
        let raMovResult = (try? await raMov) ?? []
        let raShowResult = (try? await raShow) ?? []
        let rrMovResult = (try? await rrMov) ?? []
        let raEpResult = (try? await raEp) ?? []
        let wAgainResult = (try? await wAgain) ?? []
        let genresResult = (try? await genres) ?? []
        let favsResult = (try? await favs) ?? []
        let topUnwResult = (try? await topUnw) ?? []
        let suggResult = (try? await sugg) ?? []
        let recsResult = (try? await recs) ?? []
        let tmdbKeysResult = try? await tmdbKeys
        guard succeeded else { return false }

        continueWatching       = cwResult
        recentlyAdded          = laResult
        libraries              = libsResult
        nextUp                 = nUpResult
        recentlyAddedMovies    = raMovResult
        recentlyAddedShows     = raShowResult
        recentlyReleasedMovies = rrMovResult
        recentlyAiredEpisodes  = raEpResult
        watchAgain             = wAgainResult
        genreShelves           = genresResult
        becauseYouWatched      = await loadBecauseYouWatched(credential: credential, header: header)
        favorites              = favsResult
        topRatedUnwatched      = topUnwResult
        suggestions            = suggResult
        recommendations        = recsResult.filter { $0.items.count >= 3 }
        if let tmdbKeysResult { libraryTMDBKeys = tmdbKeysResult }

        return succeeded
    }

    /// Whether the server already has a Seerr title: Seerr says so, or the library holds its
    /// TMDB id (Seerr's own status lags until it next scans the library).
    func hasInLibrary(_ item: SeerrItem) -> Bool {
        item.availabilityStatus == .available
            || libraryTMDBKeys.contains(JellyfinMediaClient.libraryKey(tmdbId: item.id, isSeries: item.mediaType == .tv))
    }

    func search(query: String, credential: ServerCredential, authClient: JellyfinAuthClient) async -> [MediaItem] {
        guard !query.isEmpty else { return [] }
        let header = authClient.authHeader(token: credential.accessToken)
        return (try? await client.search(credential: credential, authHeader: header, query: query)) ?? []
    }

    func searchIfAuthenticated(query: String, authState: AuthState, authClient: JellyfinAuthClient) async -> [MediaItem] {
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

    func personImageURL(personId: String, tag: String, fillWidth: Int = 120) -> URL? {
        guard let base = baseURL, let token = accessToken else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: personId, tag: tag,
                                            type: .primary, fillWidth: fillWidth, token: token)
    }

    func logoURL(for item: MediaItem) -> URL? {
        guard let base = baseURL, let token = accessToken else { return nil }
        var comps = URLComponents(url: base.appendingPathComponent("Items/\(item.id)/Images/Logo"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "fillWidth", value: "300"),
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

    func prefetch(urls: [URL]) {
        let uniqueURLs = Array(Set(urls))
        guard !uniqueURLs.isEmpty else { return }

        Task.detached(priority: .utility) {
            for url in uniqueURLs {
                let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 12)
                _ = try? await URLSession.arcfin.data(for: req)
            }
        }
    }
}
