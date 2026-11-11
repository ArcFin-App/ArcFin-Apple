// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import AuthCore
import BackgroundKit
#if os(iOS)
import BackgroundTasks
#endif
import Foundation
import JellyfinAPI
import SeerrAPI
import Telemetry
import os

/// Periodic background check that turns server-side changes into local notifications: new
/// titles in the Jellyfin library, Seerr request updates, and watchlist items that became
/// available. iOS decides when a refresh actually runs (typically a few times a day, and
/// less if the app is rarely opened), so these are best-effort rather than instant. The Mac
/// runs the same check every half hour or so while Arcfin is open.
///
/// Each check remembers what it has already seen in UserDefaults. The first run only records
/// the current state, so turning notifications on never announces everything that already
/// existed.
nonisolated enum BackgroundRefresh {
    private static let log = Telemetry.logger(category: "BackgroundRefresh")
    private static let seenLibraryKey = "arcfin.notify.seenLibraryIDs"
    private static let seerrStatusKey = "arcfin.notify.seerrRequestStatus"
    private static let announcedWatchlistKey = "arcfin.notify.announcedWatchlistIDs"

    #if os(iOS)
    /// BGTask isn't Sendable, but it is only touched from the launch handler and the one
    /// task that finishes it.
    private struct TaskBox: @unchecked Sendable { let task: BGAppRefreshTask }
    #endif

    /// Forgets what earlier checks saw, so the next account's first run only records state
    /// instead of announcing its whole library.
    static func resetState() {
        let defaults = UserDefaults.standard
        for key in [seenLibraryKey, seerrStatusKey, announcedWatchlistKey] {
            defaults.removeObject(forKey: key)
        }
    }

    #if os(macOS)
    nonisolated(unsafe) private static let activity: NSBackgroundActivityScheduler = {
        let activity = NSBackgroundActivityScheduler(identifier: BackgroundTaskIdentifier.refresh)
        activity.repeats = true
        activity.interval = 30 * 60
        activity.tolerance = 10 * 60
        activity.qualityOfService = .utility
        return activity
    }()

    static func register() {
        activity.schedule { completion in
            Task {
                await check()
                completion(.finished)
            }
        }
    }
    #else
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTaskIdentifier.refresh, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(TaskBox(task: refresh))
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifier.refresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("Failed to schedule refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ box: TaskBox) {
        schedule()
        let work = Task {
            await check()
            box.task.setTaskCompleted(success: !Task.isCancelled)
        }
        box.task.expirationHandler = { work.cancel() }
    }
    #endif

    static func check() async {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "notifyNewContent") as? Bool ?? true {
            await checkLibrary()
        }
        guard !Task.isCancelled else { return }
        await checkSeerr(
            requestUpdates: defaults.object(forKey: "notifyRequestUpdates") as? Bool ?? true,
            watchlist: defaults.object(forKey: "notifyWatchlistAvailable") as? Bool ?? true)
    }

    // MARK: - Jellyfin

    private static func checkLibrary() async {
        // Nil for a profile with an app-lock PIN, so titles never surface past that lock.
        guard let credential = IntentSession.credential() else { return }
        let header = IntentSession.authHeader(for: credential)
        guard let latest = try? await JellyfinMediaClient().getLatestMedia(
            credential: credential, authHeader: header, limit: 20)
        else { return }

        let defaults = UserDefaults.standard
        let seen = defaults.stringArray(forKey: seenLibraryKey)
        let ids = latest.map(\.id)
        defer { defaults.set(Array((ids + (seen ?? [])).prefix(100)), forKey: seenLibraryKey) }
        guard let seen else { return }

        let fresh = latest.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        await NotificationManager.notifyNewContent(titles: fresh.map(\.name), firstItemID: fresh.first?.id)
    }

    // MARK: - Seerr

    private static func checkSeerr(requestUpdates: Bool, watchlist: Bool) async {
        guard requestUpdates || watchlist else { return }
        let defaults = UserDefaults.standard
        // Nobody signed in: the Seerr sign-in left behind isn't anyone's to check.
        guard defaults.string(forKey: "arcfin.activeProfileID") != nil,
              let urlString = defaults.string(forKey: "seerrURL"), let url = URL(string: urlString),
              let username = defaults.string(forKey: "seerrUsername"), !username.isEmpty
        else { return }
        let password = ((try? KeychainStore().loadSeerrPassword()) ?? nil) ?? ""
        let method = defaults.string(forKey: "seerrAuthMethod").flatMap(SeerrAuthMethod.init(rawValue:)) ?? .jellyfin
        // No saved password: a Jellyfin account connected through Quick Connect.
        let authorizer = IntentSession.credential().map(SeerrSignIn.quickConnectAuthorizer(credential:))
        guard !password.isEmpty || (method == .jellyfin && authorizer != nil) else { return }
        let client = SeerrHTTPClient(baseURL: url, username: username, password: password, authMethod: method,
                                     authorizeQuickConnect: authorizer)

        if requestUpdates, let requests = try? await client.getRequests() {
            await announceRequestChanges(requests)
        }
        guard !Task.isCancelled else { return }
        if watchlist, let items = try? await client.watchlist() {
            await announceWatchlist(items)
        }
    }

    private static func announceRequestChanges(_ requests: [SeerrRequestItem]) async {
        let defaults = UserDefaults.standard
        let previous = defaults.dictionary(forKey: seerrStatusKey) as? [String: String]
        var current: [String: String] = [:]
        for item in requests {
            current[String(item.id)] = "\(item.status.rawValue)-\(item.mediaStatus?.rawValue ?? 0)"
        }
        defaults.set(current, forKey: seerrStatusKey)
        guard let previous else { return }

        for item in requests {
            guard let old = previous[String(item.id)] else { continue }
            let oldStatus = Int(old.split(separator: "-").first ?? "") ?? 0
            let oldMedia = Int(old.split(separator: "-").last ?? "") ?? 0
            if item.mediaStatus == .available, oldMedia != SeerrAvailabilityStatus.available.rawValue {
                await NotificationManager.notifyRequestAvailable(title: item.mediaTitle)
            } else if item.status == .approved, oldStatus != RequestStatus.approved.rawValue {
                await NotificationManager.notifyRequestApproved(title: item.mediaTitle)
            } else if item.status == .declined, oldStatus != RequestStatus.declined.rawValue {
                await NotificationManager.notifyRequestDeclined(title: item.mediaTitle)
            }
        }
    }

    private static func announceWatchlist(_ items: [SeerrItem]) async {
        let defaults = UserDefaults.standard
        let announced = defaults.array(forKey: announcedWatchlistKey) as? [Int]
        let available = items.filter { $0.availabilityStatus == .available }
        defaults.set(Array(Set((announced ?? []) + available.map(\.id))), forKey: announcedWatchlistKey)
        guard let announced else { return }

        for item in available where !announced.contains(item.id) {
            await NotificationManager.notifyWatchlistAvailable(title: item.title)
        }
    }
}
#endif
