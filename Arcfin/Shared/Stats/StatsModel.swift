// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// What this profile has watched, the library's counts and the stats worked out for the chosen
/// period, shared by every platform's `StatsView`.
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

    func load(authManager: AuthManager) async {
        guard case .authenticated(let credential) = authManager.state else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let client = JellyfinMediaClient()
        phase = .loading
        async let countsTask = client.getStatsLibraryCounts(credential: credential, authHeader: header)
        guard let titles = try? await client.getWatchedTitles(credential: credential, authHeader: header) else {
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
        watched = titles
        details = merged
        counts = await countsTask
        phase = .loaded
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
}
