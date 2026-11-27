// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import JellyfinAPI
import SwiftUI

extension Notification.Name {
    /// arcfin://arcs/<clipId>, from the Scene of the Day widget. The id is in `ArcsDeepLink.pendingKey`.
    static let arcfinOpenArcs = Notification.Name("arcfinOpenArcs")
}

enum ArcsDeepLink {
    static let pendingKey = "arcfin.pendingArcsClip"

    /// Buffered for a cold launch: Home opens it once Arcfin Sync says whether Arcs is on.
    static func receive(_ url: URL) {
        UserDefaults.standard.set(url.pathComponents.dropFirst().first ?? "", forKey: pendingKey)
        NotificationCenter.default.post(name: .arcfinOpenArcs, object: nil)
    }
}

extension View {
    /// Opens Arcs for a Scene of the Day link: at that scene while it's still today's, otherwise
    /// at the top of For You.
    func arcsDeepLink() -> some View {
        modifier(ArcsDeepLinkModifier())
    }
}

private struct ArcsLaunch: Identifiable {
    let id = UUID()
    let clip: ArcClip?
}

private struct ArcsDeepLinkModifier: ViewModifier {
    @Environment(AuthManager.self) private var authManager
    @State private var pending: String?
    @State private var launch: ArcsLaunch?

    private struct Key: Equatable {
        let pending: String?
        let arcsOn: Bool?
    }

    private var arcsOn: Bool? { authManager.arcfinSyncStatus.map { $0.isOn("arcs") } }

    func body(content: Content) -> some View {
        content
            .onAppear { pending = UserDefaults.standard.string(forKey: ArcsDeepLink.pendingKey) }
            .onReceive(NotificationCenter.default.publisher(for: .arcfinOpenArcs)) { _ in
                pending = UserDefaults.standard.string(forKey: ArcsDeepLink.pendingKey)
            }
            .task(id: Key(pending: pending, arcsOn: arcsOn)) { await open() }
            .fullScreenCover(item: $launch) { launch in
                ArcsCover(feed: .forYou, startingWith: launch.clip.map { [$0] } ?? [])
            }
    }

    private func open() async {
        guard let id = pending, let arcsOn else { return }
        var today: ArcClip?
        if arcsOn, let credential = authManager.state.credential {
            today = try? await ArcsClient().clipOfTheDay(credential: credential,
                                                         authHeader: authManager.authClient.authHeader(token: credential.accessToken))
            guard !Task.isCancelled else { return }
        }
        UserDefaults.standard.removeObject(forKey: ArcsDeepLink.pendingKey)
        pending = nil
        guard arcsOn else { return }
        launch = ArcsLaunch(clip: today?.id == id ? today : nil)
    }
}
