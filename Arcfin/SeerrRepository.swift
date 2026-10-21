// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import SeerrAPI
import Telemetry
// Needed for the privacy-annotated string interpolation in the error logs below — Telemetry
// wraps os.Logger, but that doesn't re-export the OSLogMessage interpolation machinery to
// callers (see MediaRepository.swift/JellyfinAuthClient.swift, which hit the identical
// "missing import of defining module 'os'" error for the same reason).
import os

@Observable
@MainActor
final class SeerrRepository {
    var trending: [SeerrItem] = []
    var popularMovies: [SeerrItem] = []
    var popularTV: [SeerrItem] = []
    var upcomingMovies: [SeerrItem] = []
    var upcomingTV: [SeerrItem] = []
    var movieGenres: [SeerrGenre] = []
    var tvGenres: [SeerrGenre] = []
    var requests: [SeerrRequestItem] = []
    var watchlist: [SeerrItem] = []
    var isLoadingDiscover = false
    var isLoadingRequests = false
    var authFailed = false
    /// The signed-in Seerr user's id/permission bitmask and the server's request settings —
    /// both fetched once per session and cached, same lifetime as `movieGenres`/`tvGenres`
    /// above. Used by the season picker (quota, auto-approve banner, whether specials/partial
    /// requests are even offered).
    @ObservationIgnored private(set) var currentUser: SeerrCurrentUser?
    @ObservationIgnored private(set) var publicSettings: SeerrPublicSettings?

    // Not @ObservationIgnored, unlike the bookkeeping vars below — isConfigured reads this,
    // and every tab-visibility check (HomeView's Discover/Watchlist tabs) reads isConfigured.
    // Ignoring it meant configure() setting a fresh client never invalidated those views, so
    // connecting Seerr (e.g. via the Quick Connect setup prompt) silently needed a full app
    // relaunch before Discover/Watchlist actually appeared.
    private var client: SeerrHTTPClient?
    @ObservationIgnored private var isFetchingDiscover = false
    @ObservationIgnored private var isFetchingRequests = false
    @ObservationIgnored private var configuredURL: String = ""
    @ObservationIgnored private var configuredUsername: String = ""
    @ObservationIgnored private var configuredPassword: String = ""
    @ObservationIgnored private var configuredMethod: SeerrAuthMethod = .jellyfin

    var isConfigured: Bool { client != nil }

    func configure(urlString: String, username: String, password: String,
                   authMethod: SeerrAuthMethod = .jellyfin) {
        let trimURL  = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimPass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimURL.isEmpty, !trimUser.isEmpty, !trimPass.isEmpty,
              let url = URL(string: trimURL) else {
            client = nil
            configuredURL = ""; configuredUsername = ""; configuredPassword = ""
            return
        }
        // Skip recreation when nothing changed — preserves isAuthenticated state
        // and prevents a fresh login() attempt (which hits Jellyfin) on every app launch.
        if client != nil,
           trimURL == configuredURL, trimUser == configuredUsername,
           trimPass == configuredPassword, authMethod == configuredMethod {
            return
        }
        // Clear any persisted auth-failure cooldown when credentials change.
        if let old = client { Task { await old.clearAuthFailure() } }
        configuredURL = trimURL; configuredUsername = trimUser
        configuredPassword = trimPass; configuredMethod = authMethod
        client = SeerrHTTPClient(baseURL: url, username: trimUser, password: trimPass,
                                      authMethod: authMethod)
        authFailed = false
        cachedRegion = nil
        trending = []; popularMovies = []; popularTV = []; requests = []
        upcomingMovies = []; upcomingTV = []; movieGenres = []; tvGenres = []
    }

    func loadDiscover() async {
        guard let client, !isFetchingDiscover else { return }
        isFetchingDiscover = true
        let firstLoad = trending.isEmpty
        if firstLoad { isLoadingDiscover = true }
        do {
            async let t  = client.trending()
            async let m  = client.discoverMovies()
            async let tv = client.discoverTV()
            let (rawT, rawM, rawTV) = try await (t, m, tv)
            let newT = await visible(rawT), newM = await visible(rawM), newTV = await visible(rawTV)
            if !newT.isEmpty  || firstLoad { trending = newT }
            if !newM.isEmpty  || firstLoad { popularMovies = newM }
            if !newTV.isEmpty || firstLoad { popularTV = newTV }
            authFailed = false
        } catch SeerrError.authFailed {
            authFailed = true
        } catch {
            // isConfigured only means a client exists (valid URL/credentials entered) — it
            // says nothing about whether the fetch itself actually succeeds. This used to
            // swallow any other failure (network, timeout, decode) completely silently,
            // leaving trending/popularMovies/popularTV empty with zero trace — "Seerr is
            // configured but the discover shelves don't show" was undiagnosable from this
            // alone, the same silently-swallowed-error shape already found and fixed for
            // MediaRepository/LibraryView/JellyfinAuthClient elsewhere this session.
            let nsError = error as NSError
            Telemetry.logger(category: "SeerrRepository").error(
                "loadDiscover failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
            )
        }
        if firstLoad { isLoadingDiscover = false }
        isFetchingDiscover = false
    }

    func loadWatchlist() async {
        guard let client else { return }
        watchlist = await visible((try? await client.watchlist()) ?? [])
        indexForSpotlight()
    }

    /// Keeps Spotlight's copy of the personal Seerr slice (watchlist + requests) current.
    private func indexForSpotlight() {
        #if os(iOS)
        let watchlist = watchlist, requests = requests
        Task { await SeerrSpotlightIndexer.index(watchlist: watchlist, requests: requests) }
        #endif
    }

    func loadRequests() async {
        guard let client, !isFetchingRequests else { return }
        isFetchingRequests = true
        let firstLoad = requests.isEmpty
        if firstLoad { isLoadingRequests = true }
        do {
            let fetched = try await client.getRequests()
            // A per-item TMDB detail fetch can fail transiently, leaving that row titled
            // "Unknown" — keep the title/artwork we already had for it rather than letting a
            // flaky refetch blank out a row that was fine a moment ago. Status is still taken
            // from the fresh response.
            let known = Dictionary(requests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            requests = fetched.map { item in
                guard item.mediaTitle == "Unknown", let previous = known[item.id], previous.mediaTitle != "Unknown" else {
                    return item
                }
                var merged = item
                merged.mediaTitle = previous.mediaTitle
                merged.posterPath = previous.posterPath
                merged.backdropPath = previous.backdropPath
                return merged
            }
            // Only on a refresh, never the first load — otherwise every request already
            // sitting at approved/available on first launch would fire a notification.
            if !firstLoad {
                for item in requests {
                    guard let previous = known[item.id] else { continue }
                    if previous.status != .approved, item.status == .approved {
                        Task { await NotificationManager.notifyRequestApproved(title: item.mediaTitle) }
                    } else if previous.mediaStatus != .available, item.mediaStatus == .available {
                        Task { await NotificationManager.notifyRequestAvailable(title: item.mediaTitle) }
                    }
                }
            }
            authFailed = false
            indexForSpotlight()
        } catch SeerrError.authFailed {
            authFailed = true
        } catch {
            let nsError = error as NSError
            Telemetry.logger(category: "SeerrRepository").error(
                "loadRequests failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
            )
        }
        if firstLoad { isLoadingRequests = false }
        isFetchingRequests = false
    }

    func search(query: String) async -> [SeerrItem] {
        guard let client, !query.isEmpty else { return [] }
        return await visible((try? await client.search(query: query)) ?? [])
    }

    /// Genre picker data for browse-by-genre — fetched once per session, cheap and rarely
    /// changes, no reason to refetch every time the Discover screen appears.
    func loadGenres() async {
        guard let client, movieGenres.isEmpty, tvGenres.isEmpty else { return }
        async let m = (try? await client.genreSlider(mediaType: .movie)) ?? []
        async let t = (try? await client.genreSlider(mediaType: .tv)) ?? []
        let (movie, tv) = await (m, t)
        movieGenres = movie
        tvGenres = tv
    }

    func loadUpcoming() async {
        guard let client else { return }
        async let m = (try? await client.upcomingMovies()) ?? []
        async let t = (try? await client.upcomingTV()) ?? []
        let (movies, tv) = await (m, t)
        upcomingMovies = await visible(movies)
        upcomingTV = await visible(tv)
    }

    func discoverByGenre(_ genreId: Int, mediaType: RequestMediaType) async -> [SeerrItem] {
        guard let client else { return [] }
        if mediaType == .tv {
            return await visible((try? await client.discoverTV(genreId: genreId)) ?? [])
        }
        return await visible((try? await client.discoverMovies(genreId: genreId)) ?? [])
    }

    func createRequest(mediaType: RequestMediaType, mediaId: Int, seasons: [Int] = []) async throws {
        guard let client else { throw URLError(.badURL) }
        try await client.createRequest(mediaType: mediaType, mediaId: mediaId, seasons: seasons)
        await loadRequests()
    }

    func cancelRequest(id: Int) async throws {
        guard let client else { throw URLError(.badURL) }
        try await client.cancelRequest(requestID: id)
        requests.removeAll { $0.id == id }
    }

    func isInWatchlist(_ item: SeerrItem) -> Bool {
        watchlist.contains { $0.id == item.id && $0.mediaType == item.mediaType }
    }

    /// Matched by tmdbId, not title — a title match silently fails whenever the request's own
    /// detail fetch failed (title falls back to "Unknown", see getRequests) or just formats
    /// the title differently than this item's own source does. tmdbId comes straight off the
    /// request's media object and doesn't depend on that detail fetch succeeding at all.
    func matchingRequest(for item: SeerrItem) -> SeerrRequestItem? {
        requests.first { $0.mediaType == item.mediaType && ($0.tmdbId.map { $0 == item.id } ?? ($0.mediaTitle == item.title)) }
    }

    func addToWatchlist(_ item: SeerrItem) async throws {
        guard let client else { throw URLError(.badURL) }
        do {
            try await client.addToWatchlist(tmdbId: item.id, mediaType: item.mediaType, title: item.title)
        } catch {
            Telemetry.logger(category: "SeerrRepository").error(
                "addToWatchlist failed for \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        if !isInWatchlist(item) { watchlist.append(item) }
    }

    func removeFromWatchlist(_ item: SeerrItem) async throws {
        guard let client else { throw URLError(.badURL) }
        do {
            try await client.removeFromWatchlist(tmdbId: item.id, mediaType: item.mediaType)
        } catch {
            Telemetry.logger(category: "SeerrRepository").error(
                "removeFromWatchlist failed for \(item.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        watchlist.removeAll { $0.id == item.id && $0.mediaType == item.mediaType }
    }

    func clearAuthFailure() {
        authFailed = false
        if let c = client { Task { await c.clearAuthFailure() } }
    }

    /// Call whenever the active Jellyfin profile changes — mirrors configureStats()'s own
    /// profile-switch hook in ContentView (a profile switch keeps the same Seerr URL/username/
    /// password today, so configure() short-circuits as "nothing changed" and never gets a
    /// chance to retry). An auth failure here sets a 1-hour cooldown (see SeerrHTTPClient) that
    /// previously only ever cleared by the user blanking out and retyping the Seerr fields in
    /// Settings — if the failure was actually transient (e.g. the Jellyfin server was briefly
    /// unreachable during the switch, same shape as the cold-launch network race elsewhere in
    /// this app), a profile switch is a reasonable moment to give it a fresh try instead of
    /// staying latched out for the rest of the cooldown.
    func retryAfterProfileSwitch() async {
        guard let client else { return }
        await client.clearAuthFailure()
        authFailed = false
        await loadDiscover()
        await loadRequests()
    }

    func mediaDetail(mediaType: RequestMediaType, tmdbId: Int) async -> SeerrMediaDetail? {
        guard let client else { return nil }
        let settings = await ensurePublicSettings()
        return try? await client.fullDetail(mediaType: mediaType, tmdbId: tmdbId,
                                             includeSpecials: settings?.enableSpecialEpisodes ?? false)
    }

    /// Fetched once per session and cached — same lazy pattern as `loadGenres()` above.
    func ensurePublicSettings() async -> SeerrPublicSettings? {
        if let publicSettings { return publicSettings }
        guard let client else { return nil }
        let fetched = try? await client.publicSettings()
        publicSettings = fetched
        return fetched
    }

    /// Fetched once per session and cached. nil if the client can't reach `/auth/me` (not
    /// signed in yet, or the server's down) — callers treat that as "quota/auto-approve
    /// unknown" rather than failing the whole request sheet over it.
    func ensureCurrentUser() async -> SeerrCurrentUser? {
        if let currentUser { return currentUser }
        guard let client else { return nil }
        let fetched = try? await client.currentUser()
        currentUser = fetched
        return fetched
    }

    /// Always fetched fresh (not cached like the two above) — a quota is spent by other
    /// requests during the session, so a stale value would wrongly let a request through or
    /// wrongly block one.
    func seasonQuota() async -> SeerrSeasonQuota? {
        guard let client, let user = await ensureCurrentUser() else { return nil }
        return try? await client.seasonQuota(userId: user.id)
    }

    /// Whether a request for `item` would be approved automatically, going by the signed-in
    /// user's own permissions — Seerr auto-approves for MANAGE_REQUESTS/AUTO_APPROVE/
    /// AUTO_APPROVE_TV (movies substitute AUTO_APPROVE_MOVIE, not read here since this app
    /// doesn't yet request movies through this picker).
    func autoApprovesTVRequests() -> Bool {
        guard let currentUser else { return false }
        return SeerrPermission.hasAny(of: [.manageRequests, .autoApprove, .autoApproveTV], in: currentUser.permissions)
    }

    /// A person's filmography via Seerr/TMDB — used by PersonDetailView to offer titles that
    /// aren't in the Jellyfin library yet. nil (not empty) when Seerr isn't configured, so a
    /// caller can tell "no Seerr" from "fetched, nothing found."
    func personCredits(tmdbId: Int) async -> [SeerrPersonCredit]? {
        guard let client else { return nil }
        guard let credits = try? await client.personCredits(tmdbPersonId: tmdbId) else { return nil }
        let allowed = Set(await visible(credits.map(\.asSeerrItem)).map { "\($0.mediaType):\($0.id)" })
        return credits.filter { allowed.contains("\($0.mediaType):\($0.id)") }
    }

    func relatedMedia(mediaType: RequestMediaType, mediaId: Int) async -> [SeerrItem] {
        guard let client else { return [] }
        async let recommendations = (try? await client.recommendations(mediaType: mediaType, mediaId: mediaId)) ?? []
        async let similar = (try? await client.similar(mediaType: mediaType, mediaId: mediaId)) ?? []
        let merged = await recommendations + similar
        var seen = Set<Int>()
        return await visible(merged.filter { item in
            seen.insert(item.id).inserted
        })
    }

    // MARK: - More discovery

    /// Popular titles first made in a language (ISO 639-1).
    func discoverByLanguage(_ language: String, mediaType: RequestMediaType) async -> [SeerrItem] {
        guard let client else { return [] }
        return await visible((try? await client.discoverByLanguage(language, mediaType: mediaType)) ?? [])
    }

    /// Movies from a studio, or shows from a network.
    func discoverByCompany(_ id: Int, mediaType: RequestMediaType) async -> [SeerrItem] {
        guard let client else { return [] }
        return await visible((try? await client.discoverByCompany(id, mediaType: mediaType)) ?? [])
    }

    func discoverByKeyword(_ id: Int) async -> [SeerrItem] {
        guard let client else { return [] }
        return await visible((try? await client.discoverByKeyword(id)) ?? [])
    }

    func relatedInfo(mediaType: RequestMediaType, tmdbId: Int) async -> SeerrRelatedInfo? {
        guard let client else { return nil }
        return try? await client.related(mediaType: mediaType, tmdbId: tmdbId, region: await region())
    }

    func ratings(mediaType: RequestMediaType, tmdbId: Int) async -> SeerrRatings? {
        guard let client else { return nil }
        return try? await client.ratings(mediaType: mediaType, tmdbId: tmdbId)
    }

    /// The country used for streaming availability and age ratings: the one set in Seerr
    /// (the signed-in user's, else the server's), as Seerr's own pages use; the device's
    /// region only when Seerr has none. Fetched once per Seerr connection.
    @ObservationIgnored private var cachedRegion: String?

    func region() async -> String {
        if let cachedRegion { return cachedRegion }
        let resolved = await client?.preferredRegion() ?? Locale.current.region?.identifier ?? "US"
        cachedRegion = resolved
        return resolved
    }

    /// Streaming services available in Seerr's country, for picking which get a Home row.
    /// Throws with the reason when Seerr can't be reached or signed in to.
    func streamingServices() async throws -> [SeerrWatchProvider] {
        guard let client else { return [] }
        let region = await region()
        async let movies = client.watchProviders(mediaType: .movie, region: region)
        async let shows = client.watchProviders(mediaType: .tv, region: region)
        let (m, t) = try await (movies, shows)
        var seen = Set<Int>()
        return (m + t).filter { seen.insert($0.id).inserted }
    }

    /// Popular movies and shows on a streaming service here, alternating.
    func popularOn(_ providerId: Int) async -> [SeerrItem] {
        guard let client else { return [] }
        let region = await region()
        async let movies = (try? await client.discoverByWatchProvider(providerId, mediaType: .movie, region: region)) ?? []
        async let shows = (try? await client.discoverByWatchProvider(providerId, mediaType: .tv, region: region)) ?? []
        let (m, t) = await (movies, shows)
        var mixed: [SeerrItem] = []
        for index in 0..<max(m.count, t.count) {
            if index < m.count { mixed.append(m[index]) }
            if index < t.count { mixed.append(t[index]) }
        }
        return await visible(mixed)
    }

    /// A Seerr title's age rating, for showing on its page.
    func certification(for item: SeerrItem) async -> String? {
        if let known = ProfileRules.shared.certification(for: item) { return known }
        guard let client else { return nil }
        return try? await client.certification(mediaType: item.mediaType, tmdbId: item.id, region: await region())
    }

    // MARK: - Parental controls

    /// What the signed-in profile may see of a Seerr list, by its parental controls.
    private func visible(_ items: [SeerrItem]) async -> [SeerrItem] {
        guard let client else { return items }
        return await ProfileRules.shared.visible(items, region: await region()) { item, region in
            let rating = try? await client.certification(mediaType: item.mediaType, tmdbId: item.id, region: region)
            return rating ?? nil
        }
    }
}
