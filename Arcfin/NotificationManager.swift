// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import UserNotifications

/// Local-only notifications — no push entitlement, no server round trip. Authorization is
/// requested lazily on first actual use (a download finishing, a Seerr request changing
/// status), not at app launch, so someone who never uses either feature is never prompted.
enum NotificationManager {
    private static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            // .denied, .ephemeral — the user said no, or this is a transient context where
            // asking again isn't appropriate. Respect it silently rather than re-prompting.
            return false
        }
    }

    private static func send(title: String, body: String, identifier: String) async {
        guard await ensureAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// For the permission prompt when someone switches a notification toggle on — the lazy
    /// request in `send` can't prompt from a background refresh, where nobody is looking.
    static func requestAuthorizationIfNeeded() async {
        _ = await ensureAuthorized()
    }

    static func notifyNewContent(titles: [String]) async {
        guard let first = titles.first else { return }
        let body = titles.count == 1 ? first : "\(first) and \(titles.count - 1) more"
        await send(title: "New in Your Library", body: body, identifier: "library-new.\(UUID().uuidString)")
    }

    static func notifyRequestDeclined(title: String) async {
        await send(title: "Request Declined", body: title, identifier: "seerr-declined.\(UUID().uuidString)")
    }

    static func notifyWatchlistAvailable(title: String) async {
        await send(title: "On Your Watchlist: Now Available", body: title, identifier: "watchlist-available.\(UUID().uuidString)")
    }

    static func notifyDownloadComplete(title: String) async {
        await send(title: "Download Complete", body: title, identifier: "download.\(UUID().uuidString)")
    }

    static func notifyRequestApproved(title: String) async {
        await send(title: "Request Approved", body: title, identifier: "seerr-approved.\(UUID().uuidString)")
    }

    static func notifyRequestAvailable(title: String) async {
        await send(title: "Now Available", body: title, identifier: "seerr-available.\(UUID().uuidString)")
    }
}
