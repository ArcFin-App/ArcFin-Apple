// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

struct PlayerWindowRequest: Codable, Hashable {
    let itemId: String
    let startTicks: Int64
}

extension EnvironmentValues {
    /// Inside a player window, where closing the player closes the window.
    @Entry var isPlayerWindow = false
}

/// A title playing in a window of its own, which iPad and Mac can place beside the app.
struct PlayerWindow: View {
    let request: PlayerWindowRequest

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var playbackPresenter = PlaybackPresenter()
    @State private var item: MediaItem?
    @State private var startTicks: Int64 = 0
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let item {
                PlayerView(item: item, startPositionTicks: startTicks) { next in
                    startTicks = 0
                    self.item = next
                }
                .id(item.id)
            } else if failed {
                ContentUnavailableView("Can't Play This", systemImage: "exclamationmark.triangle",
                                       description: Text("Check your connection, then open it again."))
            } else {
                ProgressView().tint(.white)
            }
        }
        .alwaysDarkPlayer()
        .navigationTitle(item?.name ?? "")
        .environment(\.isPlayerWindow, true)
        .environment(AppServices.authManager)
        .environment(AppServices.mediaRepo)
        .environment(playbackPresenter)
        .environment(AppServices.seerrRepo)
        .environment(AppServices.downloadManager)
        .environment(AppServices.syncPlayManager)
        .environment(AppServices.sharePlayManager)
        .task { await load() }
    }

    private func load() async {
        guard AppServices.hasPassedLock else {
            dismissWindow()
            return
        }
        let authManager = AppServices.authManager
        guard let credential = authManager.state.credential,
              let detail = try? await JellyfinMediaClient().getItemDetail(
                credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken),
                itemId: request.itemId)
        else {
            failed = true
            return
        }
        startTicks = request.startTicks
        item = detail.item
    }
}
