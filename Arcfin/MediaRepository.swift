import Foundation
import Observation
import AuthCore
import JellyfinAPI

@Observable
@MainActor
final class MediaRepository {

    var continueWatching: [MediaItem] = []
    var recentlyAdded: [MediaItem] = []
    var libraries: [JellyfinLibrary] = []
    var topMovies: [MediaItem] = []
    var topShows: [MediaItem] = []
    var playedMovieCount: Int = 0
    var playedEpisodeCount: Int = 0
    var serverID: String = ""
    var isLoading: Bool = false

    private(set) var baseURL: URL?
    private(set) var accessToken: String?

    private let client = JellyfinMediaClient()
    private var loaded = false

    func load(credential: ServerCredential, authClient: JellyfinAuthClient) async {
        guard !isLoading else { return }
        baseURL = credential.baseURL
        accessToken = credential.accessToken
        isLoading = true
        let header = authClient.authHeader(token: credential.accessToken)

        async let cw    = client.getContinueWatching(credential: credential, authHeader: header)
        async let la    = client.getLatestMedia(credential: credential, authHeader: header)
        async let libs  = client.getLibraries(credential: credential, authHeader: header)
        async let tMov  = client.getTopPlayed(credential: credential, authHeader: header, itemType: "Movie")
        async let tShow = client.getTopPlayed(credential: credential, authHeader: header, itemType: "Series")
        async let cMov  = client.getPlayedCount(credential: credential, authHeader: header, itemType: "Movie")
        async let cEp   = client.getPlayedCount(credential: credential, authHeader: header, itemType: "Episode")
        async let srvID = client.getServerID(credential: credential)

        continueWatching   = (try? await cw)    ?? []
        recentlyAdded      = (try? await la)    ?? []
        libraries          = (try? await libs)  ?? []
        topMovies          = (try? await tMov)  ?? []
        topShows           = (try? await tShow) ?? []
        playedMovieCount   = (try? await cMov)  ?? 0
        playedEpisodeCount = (try? await cEp)   ?? 0
        serverID           = (try? await srvID) ?? ""

        isLoading = false
        loaded = true
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
        // For episodes requesting primary on iOS, use the series poster instead of a screenshot
        if item.type == .episode, type == .primary,
           let seriesId = item.seriesId, let seriesTag = item.seriesPrimaryImageTag {
            return JellyfinMediaClient.imageURL(
                baseURL: base, itemID: seriesId, tag: seriesTag,
                type: .primary, fillWidth: fillWidth, token: token
            )
        }
        let tag: String?
        switch type {
        case .backdrop: tag = item.backdropImageTags.first
        case .thumb:    tag = item.thumbImageTag ?? item.backdropImageTags.first
        default:        tag = item.primaryImageTag
        }
        guard let tag else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: tag, type: type == .thumb && item.thumbImageTag == nil ? .backdrop : type, fillWidth: fillWidth, token: token)
    }

    // On tvOS: landscape thumb for movies/shows, episode primary for episodes (landscape screenshot).
    func tvImageURL(for item: MediaItem, fillWidth: Int = 500) -> URL? {
        guard let base = baseURL, let token = accessToken else { return nil }
        if item.type == .episode {
            guard let tag = item.primaryImageTag else { return nil }
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: tag, type: .primary, fillWidth: fillWidth, token: token)
        }
        return imageURL(for: item, type: .thumb, fillWidth: fillWidth)
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
                _ = try? await URLSession.shared.data(for: req)
            }
        }
    }
}
