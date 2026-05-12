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
    @ObservationIgnored private var isFetchingDiscover = false
    @ObservationIgnored private var isFetchingRequests = false
    @ObservationIgnored private var configuredURL: String = ""
    @ObservationIgnored private var configuredUsername: String = ""
    @ObservationIgnored private var configuredPassword: String = ""
    @ObservationIgnored private var configuredMethod: JellyseerrAuthMethod = .jellyfin

    var isConfigured: Bool { client != nil }

    func configure(urlString: String, username: String, password: String,
                   authMethod: JellyseerrAuthMethod = .jellyfin) {
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
        client = JellyseerrHTTPClient(baseURL: url, username: trimUser, password: trimPass,
                                      authMethod: authMethod)
        trending = []; popularMovies = []; popularTV = []; requests = []
    }

    func loadDiscover() async {
        guard let client, !isFetchingDiscover else { return }
        isFetchingDiscover = true
        let firstLoad = trending.isEmpty
        if firstLoad { isLoadingDiscover = true }
        async let t  = (try? await client.trending())       ?? []
        async let m  = (try? await client.discoverMovies()) ?? []
        async let tv = (try? await client.discoverTV())     ?? []
        let (newT, newM, newTV) = await (t, m, tv)
        if !newT.isEmpty  || firstLoad { trending = newT }
        if !newM.isEmpty  || firstLoad { popularMovies = newM }
        if !newTV.isEmpty || firstLoad { popularTV = newTV }
        if firstLoad { isLoadingDiscover = false }
        isFetchingDiscover = false
    }

    func loadRequests() async {
        guard let client, !isFetchingRequests else { return }
        isFetchingRequests = true
        let firstLoad = requests.isEmpty
        if firstLoad { isLoadingRequests = true }
        let fetched = (try? await client.getRequests()) ?? []
        requests = fetched
        if firstLoad { isLoadingRequests = false }
        isFetchingRequests = false
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
