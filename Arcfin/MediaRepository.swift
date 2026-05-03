import Foundation
import Observation
import AuthCore
import JellyfinAPI

@Observable
@MainActor
final class MediaRepository {

    var continueWatching: [MediaItem] = []
    var recentlyAdded: [MediaItem] = []
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
        async let cw = client.getContinueWatching(credential: credential, authHeader: header)
        async let la = client.getLatestMedia(credential: credential, authHeader: header)
        continueWatching = (try? await cw) ?? []
        recentlyAdded = (try? await la) ?? []
        isLoading = false
        loaded = true
    }

    func imageURL(for item: MediaItem, type: JellyfinImageType = .primary, fillWidth: Int = 300) -> URL? {
        let tag: String?
        if type == .backdrop {
            tag = item.backdropImageTags.first
        } else {
            tag = item.primaryImageTag
        }
        guard let tag, let base = baseURL, let token = accessToken else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: item.id, tag: tag, type: type, fillWidth: fillWidth, token: token)
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
}
