import Foundation
import Observation
import JellyseerrAPI

@Observable
@MainActor
final class JellyseerrRepository {
    var trending: [SeerrItem] = []
    var popularMovies: [SeerrItem] = []
    var popularTV: [SeerrItem] = []
    var requests: [SeerrRequestItem] = []
    var isLoadingDiscover = false
    var isLoadingRequests = false

    @ObservationIgnored private var client: JellyseerrHTTPClient?

    var isConfigured: Bool { client != nil }

    func configure(urlString: String, username: String, password: String,
                   authMethod: JellyseerrAuthMethod = .jellyfin) {
        let trimURL  = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimPass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimURL.isEmpty, !trimUser.isEmpty, !trimPass.isEmpty,
              let url = URL(string: trimURL) else {
            client = nil; return
        }
        client = JellyseerrHTTPClient(baseURL: url, username: trimUser, password: trimPass,
                                      authMethod: authMethod)
        trending = []; popularMovies = []; popularTV = []; requests = []
    }

    func loadDiscover() async {
        guard let client, !isLoadingDiscover else { return }
        isLoadingDiscover = true
        async let t  = (try? await client.trending())       ?? []
        async let m  = (try? await client.discoverMovies()) ?? []
        async let tv = (try? await client.discoverTV())     ?? []
        trending      = await t
        popularMovies = await m
        popularTV     = await tv
        isLoadingDiscover = false
    }

    func loadRequests() async {
        guard let client, !isLoadingRequests else { return }
        isLoadingRequests = true
        requests = (try? await client.getRequests()) ?? []
        isLoadingRequests = false
    }

    func search(query: String) async -> [SeerrItem] {
        guard let client, !query.isEmpty else { return [] }
        return (try? await client.search(query: query)) ?? []
    }

    func createRequest(mediaType: RequestMediaType, mediaId: Int) async throws {
        guard let client else { throw URLError(.badURL) }
        try await client.createRequest(mediaType: mediaType, mediaId: mediaId)
        await loadRequests()
    }
}
