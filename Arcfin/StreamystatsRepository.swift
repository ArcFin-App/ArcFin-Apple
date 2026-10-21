// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import StreamystatsAPI
import AuthCore
import Telemetry
import os

@Observable
@MainActor
final class StreamystatsRepository {
    var recommendations: [StreamystatsRecommendation] = []
    var promotedWatchlists: [StreamystatsWatchlist] = []
    var isLoading = false
    var loadError: String?

    // Not @ObservationIgnored — isConfigured reads this, and every view gating on it
    // (HomeView, LibraryView, TVLibraryView, TVMediaDetailView, StatsView) needs to react
    // the moment configure() sets a fresh client, same reactivity gap found and fixed in
    // SeerrRepository.
    private var client: StreamystatsHTTPClient?

    var isConfigured: Bool { client != nil }

    // Configure with server URL + the active Jellyfin credential.
    // No separate credentials needed — Streamystats uses the Jellyfin token.
    func configure(urlString: String, credential: ServerCredential, serverId: String) {
        let trimURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimURL.isEmpty, let url = URL(string: trimURL) else {
            client = nil; return
        }
        client = StreamystatsHTTPClient(
            baseURL: url,
            jellyfinToken: credential.accessToken,
            jellyfinServerId: serverId
        )
        recommendations = []; promotedWatchlists = []
    }

    func load() async {
        guard let client, !isLoading else { return }
        isLoading = true
        loadError = nil
        async let recs  = client.getRecommendations()
        async let lists = client.getPromotedWatchlists()
        recommendations    = (try? await recs)  ?? []
        promotedWatchlists = (try? await lists) ?? []
        isLoading = false
    }

    func addToWatchlist(itemId: String) async throws {
        guard let client else { throw StreamystatsError.requestFailed }
        do {
            // The user's own list first: a promoted list may belong to someone else, and
            // adding to it is refused.
            let watchlistId: String
            if let own = try await client.getWatchlists().first?.id {
                watchlistId = own
            } else if let promoted = promotedWatchlists.first?.id {
                watchlistId = promoted
            } else {
                throw StreamystatsError.requestFailed
            }
            try await client.addToWatchlist(watchlistId: watchlistId, jellyfinItemId: itemId)
        } catch {
            Telemetry.logger(category: "StreamystatsRepository").error(
                "addToWatchlist failed for \(itemId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
