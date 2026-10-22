// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
#if os(macOS)
import AppKit
#endif

/// "Play this" from outside the app's screens: Siri and SharePlay. Buffered like the other
/// deep links, because Home isn't listening yet on a cold launch.
enum WatchRoute {
    static let pendingKey = "arcfin.pendingWatchID"
    static let notification = Notification.Name("arcfinWatchItem")

    static func open(id: String) {
        UserDefaults.standard.set(id, forKey: pendingKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// The pending title, if any, taken off the buffer.
    static func takePending() -> String? {
        guard let id = UserDefaults.standard.string(forKey: pendingKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return id
    }

    /// A movie or episode plays from where it was left; a series from its next episode.
    static func resolve(id: String, credential: ServerCredential, authHeader: String) async -> PlaybackRequest? {
        let client = JellyfinMediaClient()
        guard var item = try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: id).item
        else { return nil }
        if item.type == .series {
            if let next = try? await client.getNextEpisode(credential: credential, authHeader: authHeader, seriesId: item.id) {
                item = next
            } else if let first = try? await client.getEpisodes(credential: credential, authHeader: authHeader, seriesId: item.id, seasonId: nil).first {
                item = first
            } else {
                return nil
            }
        }
        guard item.type == .movie || item.type == .episode else { return nil }
        let resume = item.userData.flatMap { $0.played ? nil : $0.playbackPositionTicks } ?? 0
        return PlaybackRequest(item: item, startTicks: resume)
    }
}

#if !os(tvOS)
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
        .environment(AppServices.statsRepo)
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
#endif

/// "Download the next episode" from Siri. Run by ContentView, which owns the DownloadManager.
enum DownloadRoute {
    static let pendingKey = "arcfin.pendingDownloadID"
    static let notification = Notification.Name("arcfinDownloadItem")

    static func open(id: String) {
        UserDefaults.standard.set(id, forKey: pendingKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

/// Shared, app-wide "what's currently playing" state — only actually used on macOS, where
/// PlayerView is rendered as a full-window ZStack overlay in ContentView (the same pattern
/// AppLockView already uses to cover the whole window) instead of each screen presenting it
/// locally via .sheet/.fullScreenCover. A .sheet on macOS is an inherently small, modal,
/// parent-attached panel that can't properly fill or fullscreen a window — which is exactly
/// why the player looked stuck small with a non-functional fullscreen button. iOS/tvOS keep
/// using their existing per-screen .fullScreenCover, which already behaves correctly there.
@MainActor
@Observable
final class PlaybackPresenter {
    struct Request: Identifiable {
        let id = UUID()
        let item: MediaItem
        let startTicks: Int64
        let onPlayNext: (MediaItem) -> Void
    }

    var request: Request?

    func present(_ item: MediaItem, startTicks: Int64 = 0, onPlayNext: @escaping (MediaItem) -> Void = { _ in }) {
        request = Request(item: item, startTicks: startTicks, onPlayNext: onPlayNext)
    }

    func dismiss() {
        request = nil
        #if os(macOS)
        // PlayerView grabs first responder via .focusable()/@FocusState for its keyboard
        // shortcuts (space, arrows, f, Escape). Because it's a manually-toggled ZStack
        // overlay rather than a real sheet/window AppKit tears down itself, removing it
        // doesn't hand first responder back to the main window on its own — left as-is,
        // every click after closing the player silently hits a torn-down responder and
        // nothing behind it (Home's tiles, the sidebar, everything) reacts. Clearing it
        // lets the window re-establish first responder from the next actual click.
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }
}
