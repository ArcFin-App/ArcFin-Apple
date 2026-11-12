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
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
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
        // Settings › Notifications › Quiet Hours: still delivered, just without a sound or banner.
        if QuietHours.isNow {
            content.interruptionLevel = .passive
        } else {
            content.sound = .default
        }
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

    /// `episodes` are (show, "S2 · E5 Title") pairs; a tap opens the first.
    static func notifyNewEpisodes(_ episodes: [(show: String, episode: String)], firstItemID: String?) async {
        guard let first = episodes.first else { return }
        let shows = Set(episodes.map(\.show))
        let title = episodes.count == 1 ? String(localized: "New Episode of \(first.show)")
            : shows.count == 1 ? String(localized: "\(episodes.count) New Episodes of \(first.show)")
            : String(localized: "New Episodes")
        let body = episodes.count == 1 || shows.count == 1 ? first.episode
            : String(localized: "\(first.show) and \(shows.count - 1) more of your shows")
        await send(title: title, body: body, identifier: "episodes-new.\(UUID().uuidString)", route: firstItemID.map(Route.item))
    }

    static func notifyNewFilms(titles: [String], firstItemID: String?) async {
        guard let first = titles.first else { return }
        let body = titles.count == 1 ? first : String(localized: "\(first) and \(titles.count - 1) more")
        await send(title: titles.count == 1 ? String(localized: "New Film") : String(localized: "New Films"),
                   body: body, identifier: "films-new.\(UUID().uuidString)", route: firstItemID.map(Route.item))
    }

    /// For admins: a failed task, a failed sign-in, a plugin change.
    static func notifyServerEvent(title: String, detail: String?) async {
        await send(title: String(localized: "Server: \(title)"), body: detail ?? "",
                   identifier: "server-event.\(UUID().uuidString)")
    }

    /// The app icon's badge; 0 clears it. Not on Apple TV.
    static func setBadge(_ count: Int) async {
        #if !os(tvOS)
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
        #endif
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

    // MARK: - Live TV reminders

    /// Apple TV notifications carry only a badge, so a reminder couldn't say anything there.
    static var supportsReminders: Bool {
        #if os(tvOS)
        false
        #else
        true
        #endif
    }

    private static let reminderPrefix = "livetv-reminder."

    /// A notification two minutes before a programme starts; tapping it plays the channel.
    /// False when notifications aren't allowed or the programme has already started.
    static func remind(programID: String, title: String, channelName: String, channelID: String, startsAt start: Date) async -> Bool {
        #if os(tvOS)
        return false
        #else
        guard start > .now, await ensureAuthorized() else { return false }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Starting Soon")
        content.body = String(localized: "\(title) starts on \(channelName) at \(start.formatted(date: .omitted, time: .shortened)).")
        content.sound = QuietHours.isNow ? nil : .default
        content.userInfo = Route.item(channelID).userInfo
        let fire = max(start.addingTimeInterval(-120).timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire, repeats: false)
        let request = UNNotificationRequest(identifier: reminderPrefix + programID, content: content, trigger: trigger)
        return (try? await UNUserNotificationCenter.current().add(request)) != nil
        #endif
    }

    static func cancelReminder(programID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderPrefix + programID])
    }

    /// The programmes with a reminder still to come.
    static func reminderProgramIDs() async -> Set<String> {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) }.map { String($0.dropFirst(reminderPrefix.count)) })
    }
}

#if !os(tvOS)
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

/// Settings › Notifications › Quiet Hours, as minutes after midnight.
enum QuietHours {
    static let enabledKey = "quietHoursEnabled"
    static let startKey = "quietHoursStart"
    static let endKey = "quietHoursEnd"
    static let defaultStart = 22 * 60
    static let defaultEnd = 7 * 60

    static var isNow: Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return false }
        let start = defaults.object(forKey: startKey) as? Int ?? defaultStart
        let end = defaults.object(forKey: endKey) as? Int ?? defaultEnd
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // A span that runs past midnight (22:00 to 07:00) wraps around.
        return start <= end ? (now >= start && now < end) : (now >= start || now < end)
    }
}
