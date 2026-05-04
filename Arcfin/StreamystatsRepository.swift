import Foundation
import Observation
import StreamystatsAPI
import AuthCore

@Observable
@MainActor
final class StreamystatsRepository {
    var recommendations: [StreamystatsRecommendation] = []
    var promotedWatchlists: [StreamystatsWatchlist] = []
    var isLoading = false
    var loadError: String?

    @ObservationIgnored private var client: StreamystatsHTTPClient?

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
        let watchlistId: String
        if let first = promotedWatchlists.first?.id {
            watchlistId = first
        } else {
            watchlistId = try await client.getWatchlists().first?.id ?? ""
        }
        guard !watchlistId.isEmpty else { throw StreamystatsError.requestFailed }
        try await client.addToWatchlist(watchlistId: watchlistId, jellyfinItemId: itemId)
    }
}
