// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Which stats the page shows: everything, or just watching or listening.
enum StatsKind: String, CaseIterable, Identifiable {
    case all, video, music

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .video: String(localized: "Movies & Shows")
        case .music: String(localized: "Music")
        }
    }
}

/// What this profile has watched and listened to, the library's counts and the stats worked
/// out for the chosen period, shared by every platform's `StatsView`.
@MainActor @Observable
final class StatsModel {
    enum Phase { case loading, loaded, failed }

    /// How many periods back from the current one: 0 is this week, month or year.
    var offset = 0
    private(set) var watched: [WatchedTitle] = []
    private(set) var details: [String: StatsTitleDetails] = [:]
    private(set) var counts = StatsLibraryCounts()
    private(set) var stats: WatchStats?
    private(set) var phase = Phase.loading
    private var profileID: UUID?

    private(set) var tracks: [ListenedTrack] = []
    private(set) var music: MusicStats?
    /// Nil until the music tab first needs it.
    private(set) var musicPhase: Phase?
    /// The profile's ListenBrainz name once its token checks out; "" when it has none.
    private var listenBrainzUser: String?
    private var listenBrainzStats: [ListenBrainzClient.StatsRange: ListenBrainzYear] = [:]

    struct Input: Equatable {
        let period: StatsPeriod
        let offset: Int
        let loaded: Bool
        let count: Int
        let details: Int
    }

    /// Changes whenever the stats need working out again.
    func input(period: StatsPeriod) -> Input {
        Input(period: period, offset: offset, loaded: phase == .loaded, count: watched.count, details: details.count)
    }

    /// Changes whenever the music stats need working out again.
    func musicInput(period: StatsPeriod) -> Input {
        Input(period: period, offset: offset, loaded: musicPhase == .loaded, count: tracks.count, details: 0)
    }

    /// Whether going back a period can find more, for the tab shown.
    func hasEarlier(_ kind: StatsKind) -> Bool {
        switch kind {
        case .video: stats?.hasEarlier ?? false
        case .music: music?.hasEarlier ?? false
        case .all: (stats?.hasEarlier ?? false) || (music?.hasEarlier ?? false)
        }
    }

    func load(authManager: AuthManager) async {
        guard case .authenticated(let credential) = authManager.state else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let client = JellyfinMediaClient()
        if profileID != credential.id {
            profileID = credential.id
            offset = 0
            watched = []
            details = [:]
            counts = StatsLibraryCounts()
            stats = nil
            tracks = []
            music = nil
            musicPhase = nil
            listenBrainzUser = nil
            listenBrainzStats = [:]
        }
        if musicPhase != nil { Task { await loadMusic(authManager: authManager, force: true) } }
        phase = .loading
        async let countsTask = client.getStatsLibraryCounts(credential: credential, authHeader: header)
        guard let titles = try? await client.getWatchedTitles(credential: credential, authHeader: header) else {
            guard isCurrent(credential, authManager) else { return }
            phase = .failed
            return
        }
        // Each show's own details for every show watched; cast and crew only for the shows
        // and movies most likely to matter, as People makes each item many times bigger.
        var seriesIds: [String] = []
        var seenSeries = Set<String>()
        for title in titles {
            if let id = title.item.seriesId, seenSeries.insert(id).inserted { seriesIds.append(id) }
        }
        let movieIds = titles.filter { $0.item.type == .movie }.prefix(150).map(\.id)
        let creditIds = Array(seriesIds.prefix(60)) + movieIds
        let showIds = Array(seriesIds.prefix(500))
        async let showDetails = client.getStatsDetails(credential: credential, authHeader: header,
                                                       ids: showIds, includePeople: false)
        async let creditDetails = client.getStatsDetails(credential: credential, authHeader: header,
                                                         ids: creditIds, includePeople: true)
        var merged = (try? await showDetails) ?? [:]
        merged.merge((try? await creditDetails) ?? [:]) { _, withPeople in withPeople }
        let libraryCounts = await countsTask
        guard isCurrent(credential, authManager) else { return }
        watched = titles
        details = merged
        counts = libraryCounts
        phase = .loaded
    }

    private func isCurrent(_ credential: ServerCredential, _ authManager: AuthManager) -> Bool {
        !Task.isCancelled && authManager.state.credential?.id == credential.id
    }

    func compute(period: StatsPeriod, reduceMotion: Bool) async {
        guard phase == .loaded else { return }
        let all = watched, details = details, offset = offset
        let result = await Task.detached(priority: .userInitiated) {
            WatchStats(all: all, details: details, period: period, offset: offset)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : DT.Animation.standard) { stats = result }
    }

    // MARK: - Music

    /// The songs this profile has played, fetched the first time a tab with music needs them.
    func loadMusic(authManager: AuthManager, force: Bool = false) async {
        guard force || musicPhase == nil, case .authenticated(let credential) = authManager.state else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        musicPhase = .loading
        let played = try? await JellyfinMediaClient().getListenedTracks(credential: credential, authHeader: header)
        guard isCurrent(credential, authManager) else { return }
        if force { listenBrainzStats = [:] }
        if let played {
            tracks = played
            musicPhase = .loaded
        } else {
            musicPhase = tracks.isEmpty ? .failed : .loaded
        }
    }

    func computeMusic(period: StatsPeriod, reduceMotion: Bool) async {
        guard musicPhase == .loaded else { return }
        let all = tracks, offset = offset
        var result: MusicStats?
        if let range = MusicStats.listenBrainzRange(period: period, offset: offset),
           let year = await listenBrainz(range, period: period, offset: offset), !year.songs.isEmpty {
            result = await Task.detached(priority: .userInitiated) {
                MusicStats(listenBrainz: year, jellyfin: all, period: period, offset: offset)
            }.value
        }
        if result == nil {
            result = await Task.detached(priority: .userInitiated) {
                MusicStats(all: all, period: period, offset: offset)
            }.value
        }
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : DT.Animation.standard) { music = result }
    }

    /// One range from ListenBrainz, kept for the visit; nil without a token or a reply.
    private func listenBrainz(_ range: ListenBrainzClient.StatsRange, period: StatsPeriod, offset: Int) async -> ListenBrainzYear? {
        if let cached = listenBrainzStats[range] { return cached }
        guard let profile = profileID, let token = ListenBrainzCredential.load(profile: profile) else { return nil }
        let client = ListenBrainzClient(token: token, clientVersion: "")
        if listenBrainzUser == nil { listenBrainzUser = (try? await client.validate()) ?? "" }
        guard let user = listenBrainzUser, !user.isEmpty else { return nil }
        let calendar = Calendar.current
        let reference = calendar.date(byAdding: period.component, value: offset, to: .now) ?? .now
        let interval = period.interval(now: reference, calendar: calendar)
        guard let year = try? await client.stats(userName: user, range: range, since: interval?.start ?? .distantPast,
                                                 until: interval?.end ?? .distantFuture) else { return nil }
        listenBrainzStats[range] = year
        return year
    }
}
