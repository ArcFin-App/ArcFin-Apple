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

    /// Where tapping a notification should land.
    enum Route {
        case item(String)
        case downloads
        case discover

        fileprivate var userInfo: [String: String] {
            switch self {
            case .item(let id): ["route": "item", "itemID": id]
            case .downloads: ["route": "downloads"]
            case .discover: ["route": "discover"]
            }
        }
    }

    private static func send(title: String, body: String, identifier: String, route: Route? = nil) async {
        // tvOS notifications carry only a badge, no text.
        #if !os(tvOS)
        guard await ensureAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let route { content.userInfo = route.userInfo }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }

    /// For the permission prompt when someone switches a notification toggle on — the lazy
    /// request in `send` can't prompt from a background refresh, where nobody is looking.
    static func requestAuthorizationIfNeeded() async {
        _ = await ensureAuthorized()
    }

    /// `firstItemID` is the title a tap opens when several arrived at once.
    static func notifyNewContent(titles: [String], firstItemID: String?) async {
        guard let first = titles.first else { return }
        let body = titles.count == 1 ? first : "\(first) and \(titles.count - 1) more"
        await send(
            title: "New in Your Library", body: body, identifier: "library-new.\(UUID().uuidString)",
            route: firstItemID.map(Route.item))
    }

    static func notifyRequestDeclined(title: String) async {
        await send(title: "Request Declined", body: title, identifier: "seerr-declined.\(UUID().uuidString)", route: .discover)
    }

    static func notifyWatchlistAvailable(title: String) async {
        await send(title: "On Your Watchlist: Now Available", body: title, identifier: "watchlist-available.\(UUID().uuidString)", route: .discover)
    }

    static func notifyDownloadComplete(title: String) async {
        await send(title: "Download Complete", body: title, identifier: "download.\(UUID().uuidString)", route: .downloads)
    }

    static func notifyRequestApproved(title: String) async {
        await send(title: "Request Approved", body: title, identifier: "seerr-approved.\(UUID().uuidString)", route: .discover)
    }

    static func notifyRequestAvailable(title: String) async {
        await send(title: "Now Available", body: title, identifier: "seerr-available.\(UUID().uuidString)", route: .discover)
    }
}

#if os(iOS)
/// Receives notification taps and shows banners while the app is open.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let route = info["route"] as? String
        let itemID = info["itemID"] as? String
        await MainActor.run {
            switch route {
            case "item":
                if let itemID { ArcfinRouting.openItem(id: itemID) }
            case "downloads":
                ArcfinRouting.showDownloads()
            case "discover":
                ArcfinRouting.showDiscover()
            default:
                break
            }
        }
    }
}
#endif
