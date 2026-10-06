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
            let (newT, newM, newTV) = try await (t, m, tv)
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
        watchlist = (try? await client.watchlist()) ?? []
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
            authFailed = false
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
        return (try? await client.search(query: query)) ?? []
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
        upcomingMovies = movies
        upcomingTV = tv
    }

    func discoverByGenre(_ genreId: Int, mediaType: RequestMediaType) async -> [SeerrItem] {
        guard let client else { return [] }
        if mediaType == .tv {
            return (try? await client.discoverTV(genreId: genreId)) ?? []
        }
        return (try? await client.discoverMovies(genreId: genreId)) ?? []
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

    func addToWatchlist(_ item: SeerrItem) async throws {
        guard let client else { throw URLError(.badURL) }
        try await client.addToWatchlist(tmdbId: item.id, mediaType: item.mediaType, title: item.title)
        if !isInWatchlist(item) { watchlist.append(item) }
    }

    func removeFromWatchlist(_ item: SeerrItem) async throws {
        guard let client else { throw URLError(.badURL) }
        try await client.removeFromWatchlist(tmdbId: item.id, mediaType: item.mediaType)
        watchlist.removeAll { $0.id == item.id && $0.mediaType == item.mediaType }
    }

    func clearAuthFailure() {
        authFailed = false
        if let c = client { Task { await c.clearAuthFailure() } }
    }

    func mediaDetail(mediaType: RequestMediaType, tmdbId: Int) async -> SeerrMediaDetail? {
        guard let client else { return nil }
        return try? await client.fullDetail(mediaType: mediaType, tmdbId: tmdbId)
    }

    func relatedMedia(mediaType: RequestMediaType, mediaId: Int) async -> [SeerrItem] {
        guard let client else { return [] }
        async let recommendations = (try? await client.recommendations(mediaType: mediaType, mediaId: mediaId)) ?? []
        async let similar = (try? await client.similar(mediaType: mediaType, mediaId: mediaId)) ?? []
        let merged = await recommendations + similar
        var seen = Set<Int>()
        return merged.filter { item in
            seen.insert(item.id).inserted
        }
    }
}
