// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Another player app a title can be handed to, by its URL scheme (iPhone, iPad, Apple TV)
/// or its bundle (Mac). Progress isn't reported back from it.
struct ExternalPlayer: Identifiable, Hashable {
    let id: String
    let name: String
    /// The link that opens a stream in the app, where it takes one by URL scheme.
    let schemeLink: (@Sendable (URL) -> URL?)?
    /// The Mac app, opened with the stream URL.
    let macBundleID: String?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private nonisolated static func encoded(_ url: URL) -> String {
        url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url.absoluteString
    }

    static let all: [ExternalPlayer] = [
        ExternalPlayer(id: "infuse", name: "Infuse",
                       schemeLink: { URL(string: "infuse://x-callback-url/play?url=\(encoded($0))") },
                       macBundleID: "com.firecore.infuse"),
        ExternalPlayer(id: "vlc", name: "VLC",
                       schemeLink: { URL(string: "vlc-x-callback://x-callback-url/stream?url=\(encoded($0))") },
                       macBundleID: "org.videolan.vlc"),
        ExternalPlayer(id: "iina", name: "IINA", schemeLink: nil, macBundleID: "com.colliderli.iina"),
        ExternalPlayer(id: "outplayer", name: "Outplayer",
                       schemeLink: { URL(string: "outplayer://\($0.absoluteString)") }, macBundleID: nil),
        ExternalPlayer(id: "nplayer", name: "nPlayer",
                       schemeLink: { URL(string: "nplayer-\($0.absoluteString)") }, macBundleID: nil),
    ]

    /// The players installed here that can take a stream.
    static var installed: [ExternalPlayer] { all.filter { ExternalApps.canOpen($0) } }

    /// The file itself, played as is, signed with the profile's token so the other app can
    /// fetch it without signing in.
    static func streamURL(for item: MediaItem, credential: ServerCredential) -> URL? {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Videos/\(item.id)/stream"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            .init(name: "static", value: "true"),
            .init(name: "MediaSourceId", value: item.id),
            .init(name: "api_key", value: credential.accessToken),
        ]
        return comps?.url
    }
}

/// "Open In" and "Copy Stream Link" for a movie or episode's menu.
struct OpenInPlayerMenu: View {
    let item: MediaItem
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if item.type == .movie || item.type == .episode,
           let credential = authManager.state.credential,
           let stream = ExternalPlayer.streamURL(for: item, credential: credential) {
            let players = ExternalPlayer.installed
            if !players.isEmpty {
                Menu {
                    ForEach(players) { player in
                        Button(player.name) { ExternalApps.open(player, stream: stream) }
                    }
                } label: {
                    Label("Open In", systemImage: "arrow.up.forward.app")
                }
            }
            if ExternalApps.canCopy {
                Button { ExternalApps.copy(stream.absoluteString) } label: {
                    Label("Copy Stream Link", systemImage: "link")
                }
            }
        }
    }
}
