// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

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
        handBackFirstResponder()
    }
}
