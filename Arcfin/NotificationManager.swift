// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
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
        /// Discover's Requests list, for a request to approve or one that failed.
        case seerrRequests
        case seerrIssue(Int)
        /// An arcfin:// link, opened the way the system would open it.
        case link(URL)

        fileprivate var userInfo: [String: String] {
            switch self {
            case .item(let id): ["route": "item", "itemID": id]
            case .downloads: ["route": "downloads"]
            case .discover: ["route": "discover"]
            case .seerrRequests: ["route": "seerrRequests"]
            case .seerrIssue(let id): ["route": "seerrIssue", "issueID": String(id)]
            case .link(let url): ["route": "link", "url": url.absoluteString]
            }
        }
    }

    private static func send(title: String, body: String, identifier: String, route: Route? = nil,
                             threadIdentifier: String? = nil) async {
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
        if let threadIdentifier { content.threadIdentifier = threadIdentifier }
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

    /// From the server's admin, through Arcfin Sync.
    static func notifyAnnouncement(id: String, title: String, message: String) async {
        await send(title: title.isEmpty ? String(localized: "Announcement") : title, body: message, identifier: id)
    }

    /// A day or less before maintenance the server's admin planned.
    static func notifyMaintenance(id: String, summary: String) async {
        await send(title: String(localized: "Maintenance Coming Up"), body: summary, identifier: id)
    }

    /// Sent from the Arcfin Sync dashboard to check that notifications reach this person.
    static func notifyServerTest(id: String) async {
        await send(title: String(localized: "Test Notification"),
                   body: String(localized: "Your server's notifications reach this device."), identifier: id)
    }

    /// A friend sent a scene in Arcs: opens it there. A PIN profile's shows no name or title.
    static func notifyArcsSent(_ event: ServerEvent, hidingDetails: Bool) async {
        let sender = event.title
        let heading = hidingDetails || sender.isEmpty ? String(localized: "Someone sent you a scene") : String(localized: "\(sender) sent you a scene")
        let route = event.clipId.flatMap { URL(string: "arcfin://arcs/\($0)") }.map(Route.link)
        await send(title: heading, body: hidingDetails ? "" : (event.body ?? ""), identifier: event.id, route: route, threadIdentifier: "arcs-sent")
    }

    /// For people who can approve requests in Seerr: one waiting, approved by itself, or failed.
    static func notifyRequestToManage(_ event: ServerEvent, title: String, hidingDetails: Bool) async {
        let heading = switch event.kind {
        case "seerr-pending": String(localized: "Request to Approve")
        case "seerr-auto-approved": String(localized: "Request Approved Automatically")
        default: String(localized: "Request Failed")
        }
        let body = !hidingDetails && event.kind != "seerr-failed" ? event.actor.map { String(localized: "\($0) asked for \(title)") } ?? title : title
        await send(title: heading, body: body, identifier: event.id, route: .seerrRequests)
    }

    /// A Seerr issue reported, commented on, resolved or reopened.
    static func notifyIssue(_ event: ServerEvent, hidingDetails: Bool) async {
        let subject = hidingDetails || event.title.isEmpty ? String(localized: "An issue") : event.title
        let heading = switch event.kind {
        case "issue-reported": String(localized: "New Issue: \(subject)")
        case "issue-comment": String(localized: "New Comment: \(subject)")
        case "issue-resolved": String(localized: "Issue Resolved: \(subject)")
        default: String(localized: "Issue Reopened: \(subject)")
        }
        let kind = switch event.issueType {
        case 1: String(localized: "Video")
        case 2: String(localized: "Audio")
        case 3: String(localized: "Subtitles")
        default: String(localized: "Other")
        }
        let body: String
        if hidingDetails {
            body = ""
        } else if let text = event.body, !text.isEmpty {
            body = event.actor.map { "\($0): \(text)" } ?? text
        } else {
            body = event.actor.map { String(localized: "\(kind) · \($0)") } ?? kind
        }
        await send(title: heading, body: body, identifier: event.id, route: event.issueId.map(Route.seerrIssue) ?? .discover)
    }

    /// The app icon's badge; 0 clears it. Not on Apple TV.
    static func setBadge(_ count: Int) async {
        #if !os(tvOS)
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
        #endif
    }

    static func notifyRequestDeclined(title: String, requestID: Int? = nil) async {
        guard let identifier = requestIdentifier("seerr-declined", requestID: requestID) else { return }
        await send(title: String(localized: "Request Declined"), body: title, identifier: identifier, route: .discover)
    }

    static func notifyWatchlistAvailable(title: String) async {
        await send(title: String(localized: "On Your Watchlist: Now Available"), body: title, identifier: "watchlist-available.\(UUID().uuidString)", route: .discover)
    }

    static func notifyDownloadComplete(title: String) async {
        await send(title: String(localized: "Download Complete"), body: title, identifier: "download.\(UUID().uuidString)",
                   route: .downloads, threadIdentifier: "downloads")
    }

    /// A run of music downloads has finished.
    static func notifyMusicDownloaded(songs: Int) async {
        await send(title: String(localized: "Music Downloaded"), body: String(localized: "\(songs) songs"),
                   identifier: "music-download.\(UUID().uuidString)")
    }

    static func notifyRequestApproved(title: String, requestID: Int? = nil) async {
        guard let identifier = requestIdentifier("seerr-approved", requestID: requestID) else { return }
        await send(title: String(localized: "Request Approved"), body: title, identifier: identifier, route: .discover)
    }

    static func notifyRequestAvailable(title: String, requestID: Int? = nil) async {
        guard let identifier = requestIdentifier("seerr-available", requestID: requestID) else { return }
        await send(title: String(localized: "Now Available"), body: title, identifier: identifier, route: .discover)
    }

    nonisolated static let sentRequestNoticesKey = "arcfin.notify.sentRequestNotices"

    /// Nil when Request Updates is off, or this change of this request was already announced:
    /// the in-app Seerr refresh and the background check can both find the same one.
    private static func requestIdentifier(_ kind: String, requestID: Int?) -> String? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "notifyRequestUpdates") as? Bool ?? true else { return nil }
        guard let requestID else { return "\(kind).\(UUID().uuidString)" }
        let identifier = "\(kind).\(requestID)"
        var sent = defaults.stringArray(forKey: sentRequestNoticesKey) ?? []
        guard !sent.contains(identifier) else { return nil }
        sent.append(identifier)
        defaults.set(Array(sent.suffix(300)), forKey: sentRequestNoticesKey)
        return identifier
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

    // MARK: - Watch parties

    private static let partyPrefix = "watch-party."

    /// A notification when a scheduled watch party's lobby opens; tapping it opens the party.
    /// One per code, so a new time replaces the old one. Skipped when notifications aren't allowed.
    static func remindParty(code: String, title: String, lobbyOpens: Date, link: URL) async {
        #if !os(tvOS)
        guard lobbyOpens > .now, await ensureAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Watch Party")
        content.body = String(localized: "\(title) starts in 15 minutes. Tap to join.")
        content.sound = QuietHours.isNow ? nil : .default
        content.userInfo = Route.link(link).userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(lobbyOpens.timeIntervalSinceNow, 1), repeats: false)
        let request = UNNotificationRequest(identifier: partyPrefix + code, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
        #endif
    }

    static func cancelPartyReminder(code: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [partyPrefix + code])
    }

    /// The parties with a notification still to come.
    static func partyReminderCodes() async -> Set<String> {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(pending.map(\.identifier).filter { $0.hasPrefix(partyPrefix) }.map { String($0.dropFirst(partyPrefix.count)) })
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
        let link = info["url"] as? String
        await MainActor.run {
            switch route {
            case "link":
                // Through the app's own link handling, buffered for a cold launch and the app lock.
                if let link { ControlRoute.open(link) }
            case "item":
                if let itemID { ArcfinRouting.openItem(id: itemID) }
            case "downloads":
                ArcfinRouting.showDownloads()
            case "discover":
                ArcfinRouting.showDiscover()
            case "seerrRequests":
                ArcfinRouting.showSeerrRequests()
            case "seerrIssue":
                if let id = (info["issueID"] as? String).flatMap(Int.init) { ArcfinRouting.openSeerrIssue(id: id) }
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
