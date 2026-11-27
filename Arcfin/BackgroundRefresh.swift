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
import SwiftData
import Telemetry
import os

/// Periodic background check that turns server-side changes into local notifications: new
/// titles in the Jellyfin library, Seerr request updates, watchlist items that became
/// available, and with Arcfin Sync 0.7 the server's own feed of request changes, announcements
/// and planned maintenance. iOS decides when a refresh actually runs (typically a few times a day, and
/// less if the app is rarely opened), so these are best-effort rather than instant. The Mac
/// runs the same check every half hour or so while Arcfin is open.
///
/// Each check remembers what it has already seen in UserDefaults. The first run only records
/// the current state, so turning notifications on never announces everything that already
/// existed.
nonisolated enum BackgroundRefresh {
    private static let log = Telemetry.logger(category: "BackgroundRefresh")
    private static let seenFilmsKey = "arcfin.notify.seenFilmIDs"
    private static let seenEpisodesKey = "arcfin.notify.seenEpisodeIDs"
    private static let lastActivityKey = "arcfin.notify.lastActivityID"
    private static let seerrStatusKey = "arcfin.notify.seerrRequestStatus"
    private static let announcedWatchlistKey = "arcfin.notify.announcedWatchlistIDs"
    private static let feedCursorKey = "arcfin.notify.serverFeedCursor"
    private static let feedSeenKey = "arcfin.notify.serverFeedSeen"
    private static let lastFeedCheckKey = "arcfin.notify.lastFeedCheck"
    static let announcementsKey = "notifyAnnouncements"
    static let requestsToApproveKey = "notifyRequestsToApprove"
    static let issuesKey = "notifyIssues"
    static let arcsSentKey = "notifyArcsSent"

    #if os(iOS)
    /// BGTask isn't Sendable. The work and the expiration handler can both finish it, so the
    /// lock keeps that to once.
    private final class TaskBox: @unchecked Sendable {
        let task: BGAppRefreshTask
        private let lock = NSLock()
        private var completed = false

        init(task: BGAppRefreshTask) { self.task = task }

        func complete(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
        }
    }
    #endif

    /// Forgets what earlier checks saw, so the next account's first run only records state
    /// instead of announcing its whole library.
    static func resetState() {
        let defaults = UserDefaults.standard
        for key in [seenFilmsKey, seenEpisodesKey, lastActivityKey, seerrStatusKey, announcedWatchlistKey,
                    feedCursorKey, feedSeenKey, NotificationManager.sentRequestNoticesKey] {
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

    /// While Arcfin is open: a check as it comes to the front (at most every few minutes), then
    /// every 15 minutes, so news doesn't wait for iOS to schedule a background refresh.
    @MainActor private static var whileOpen: Task<Void, Never>?
    private static let lastOpenCheckKey = "arcfin.notify.lastOpenCheck"

    /// Each window calls this as it becomes active; one already running carries on, so a
    /// check in progress isn't cut short after it has recorded what it saw.
    @MainActor static func startWhileOpen() {
        checkFeedOnOpen()
        guard whileOpen == nil else { return }
        whileOpen = Task {
            let last = UserDefaults.standard.object(forKey: lastOpenCheckKey) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 5 * 60 {
                UserDefaults.standard.set(Date(), forKey: lastOpenCheckKey)
                await check()
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard !Task.isCancelled else { return }
                UserDefaults.standard.set(Date(), forKey: lastOpenCheckKey)
                await check()
            }
        }
    }

    @MainActor static func stopWhileOpen() {
        whileOpen?.cancel()
        whileOpen = nil
    }

    private static func handle(_ box: TaskBox) {
        schedule()
        let work = Task {
            async let downloads: Void = queueDownloads()
            await check()
            await downloads
            box.complete(success: !Task.isCancelled)
        }
        // Signing in can wait on the device being unlocked, which cancelling doesn't cut short.
        box.task.expirationHandler = {
            work.cancel()
            box.complete(success: false)
        }
    }

    /// Progress watched offline goes to the server, and Smart Downloads queues the next
    /// episodes, whose transfers carry on in the background download session.
    @MainActor private static func queueDownloads() async {
        let manager = AppServices.downloadManager
        // A background launch connects no window to set the manager up.
        manager.configure(modelContext: AppServices.modelContainer.mainContext, authManager: AppServices.authManager)
        await manager.refreshInBackground()
    }
    #endif

    /// New Episodes and New Films start from the old single New Content setting.
    private static func isOn(_ key: String) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key) as? Bool ?? defaults.object(forKey: "notifyNewContent") as? Bool ?? true
    }

    static func check() async {
        let defaults = UserDefaults.standard
        if isOn("notifyNewFilms") { await checkFilms() }
        guard !Task.isCancelled else { return }
        if isOn("notifyNewEpisodes") { await checkEpisodes() }
        guard !Task.isCancelled else { return }
        if defaults.bool(forKey: "notifyServerEvents") { await checkServerEvents() }
        guard !Task.isCancelled else { return }
        if defaults.bool(forKey: StreamBadge.key) { await StreamBadge.refresh() }
        guard !Task.isCancelled else { return }
        if let credential = IntentSession.credential() {
            await WidgetSnapshotUpdater.refreshProgress(credential: credential, authHeader: IntentSession.authHeader(for: credential))
        }
        #if os(iOS)
        await ArcsWidgetPublisher.refresh()
        #endif
        guard !Task.isCancelled else { return }
        await checkServerFeed()
        guard !Task.isCancelled else { return }
        await checkSeerr(
            requestUpdates: defaults.object(forKey: "notifyRequestUpdates") as? Bool ?? true,
            watchlist: defaults.object(forKey: "notifyWatchlistAvailable") as? Bool ?? true)
    }

    // MARK: - Jellyfin

    private static func checkFilms() async {
        // Nil for a profile with an app-lock PIN, so titles never surface past that lock.
        guard let credential = IntentSession.credential() else { return }
        let header = IntentSession.authHeader(for: credential)
        guard let latest = try? await JellyfinMediaClient().getLatestMedia(
            credential: credential, authHeader: header, itemTypes: "Movie", limit: 20)
        else { return }
        guard let fresh = remember(latest.map(\.id), key: seenFilmsKey) else { return }
        let films = latest.filter { fresh.contains($0.id) }
        await NotificationManager.notifyNewFilms(titles: films.map(\.name), firstItemID: films.first?.id)
    }

    /// New episodes of the shows in Continue Watching and Next Up, the ones being watched.
    private static func checkEpisodes() async {
        guard let credential = IntentSession.credential() else { return }
        let header = IntentSession.authHeader(for: credential)
        let client = JellyfinMediaClient()
        guard let latest = try? await client.getRecentlyAddedEpisodes(credential: credential, authHeader: header)
        else { return }
        guard let fresh = remember(latest.map(\.id), key: seenEpisodesKey) else { return }
        async let nextUp = client.getNextUpIncludingRecent(credential: credential, authHeader: header)
        async let resume = client.getContinueWatching(credential: credential, authHeader: header)
        let watching = Set(((try? await nextUp) ?? []).compactMap(\.seriesId) + ((try? await resume) ?? []).compactMap(\.seriesId))
        let episodes = latest.filter { fresh.contains($0.id) && $0.seriesId.map(watching.contains) == true && $0.userData?.played != true }
        guard !episodes.isEmpty else { return }
        await NotificationManager.notifyNewEpisodes(episodes.map { episode in
            let code = [episode.parentIndexNumber.map { "S\($0)" }, episode.indexNumber.map { "E\($0)" }]
                .compactMap { $0 }.joined(separator: " · ")
            return (episode.seriesName ?? episode.name, code.isEmpty ? episode.name : "\(code) \(episode.name)")
        }, firstItemID: episodes.first?.id)
    }

    /// Records `ids` as seen and returns the ones that are new, or nil on the first run, which
    /// only records what's there.
    private static func remember(_ ids: [String], key: String) -> Set<String>? {
        let defaults = UserDefaults.standard
        let seen = defaults.stringArray(forKey: key)
        defaults.set(Array((ids + (seen ?? [])).prefix(200)), forKey: key)
        guard let seen else { return nil }
        let fresh = Set(ids).subtracting(seen)
        return fresh.isEmpty ? nil : fresh
    }

    // MARK: - Server events (admins)

    /// Failed tasks and sign-ins, warnings, and plugin changes from the activity log since the
    /// last check. A non-admin profile gets nothing back, so nothing is sent.
    private static func checkServerEvents() async {
        guard let credential = IntentSession.credential() else { return }
        let header = IntentSession.authHeader(for: credential)
        guard let entries = try? await JellyfinAdminClient().activity(limit: 30, credential: credential, authHeader: header)
        else { return }
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: lastActivityKey) as? Int
        if let newest = entries.map(\.id).max() { defaults.set(max(newest, last ?? 0), forKey: lastActivityKey) }
        guard let last else { return }
        let notable = entries.filter { entry in
            entry.id > last && (entry.severity != "Information" || entry.type.hasPrefix("Plugin"))
        }
        for entry in notable.sorted(by: { $0.id < $1.id }).prefix(3) {
            await NotificationManager.notifyServerEvent(title: entry.name, detail: entry.overview)
        }
    }

    // MARK: - Arcfin Sync

    /// The server's feed is one small request, so it's read every time Arcfin comes to the
    /// front (at most every half minute), not only with the full check every few minutes.
    /// When Arcfin Sync says there's news, over the live connection: read it now.
    @MainActor static func listenForServerNews() {
        NotificationCenter.default.addObserver(forName: .arcfinServerFeedChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(Date(), forKey: lastFeedCheckKey)
                Task { await checkServerFeed() }
            }
        }
    }

    @MainActor static func checkFeedOnOpen() {
        let defaults = UserDefaults.standard
        guard Date().timeIntervalSince(defaults.object(forKey: lastFeedCheckKey) as? Date ?? .distantPast) > 30 else { return }
        defaults.set(Date(), forKey: lastFeedCheckKey)
        Task { await checkServerFeed() }
    }

    /// The plugin's feed. It overlaps the device's own Seerr check when both look at the same
    /// Seerr; each request change has one identifier, so it's announced once either way.
    /// A profile with an app-lock PIN still gets it, with request titles left out, as the other
    /// checks give it nothing at all.
    private static func checkServerFeed() async {
        guard let (credential, pinLocked) = IntentSession.profile() else { return }
        let defaults = UserDefaults.standard
        let cursor = (defaults.object(forKey: feedCursorKey) as? NSNumber)?.int64Value
        let feed: ServerEventFeed
        do {
            guard let answer = try await ArcfinCompanionClient().events(
                since: cursor, credential: credential, authHeader: IntentSession.authHeader(for: credential))
            else { return }
            feed = answer
        } catch {
            log.error("Server feed failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        log.notice("Server feed: \(feed.events.count, privacy: .public) events after \(cursor.map(String.init) ?? "none", privacy: .public), now at \(feed.cursor, privacy: .public)")
        defaults.set(NSNumber(value: feed.cursor), forKey: feedCursorKey)
        let seen = defaults.stringArray(forKey: feedSeenKey)
        var kept: [String] = []
        for id in feed.events.filter({ $0.kind == "announcement" || $0.kind == "maintenance" }).map(\.id) + (seen ?? [])
        where !kept.contains(id) { kept.append(id) }
        defaults.set(Array(kept.prefix(200)), forKey: feedSeenKey)
        guard cursor != nil else { return }

        let announcements = defaults.object(forKey: announcementsKey) as? Bool ?? true
        let toApprove = defaults.object(forKey: requestsToApproveKey) as? Bool ?? true
        let issues = defaults.object(forKey: issuesKey) as? Bool ?? true
        let arcsSent = PlatformMetrics.hasArcs && (defaults.object(forKey: arcsSentKey) as? Bool ?? true)
        for event in feed.events {
            let title = event.title.isEmpty || pinLocked ? String(localized: "One of your requests") : event.title
            switch event.kind {
            case "seerr-approved": await NotificationManager.notifyRequestApproved(title: title, requestID: event.requestId)
            case "seerr-declined": await NotificationManager.notifyRequestDeclined(title: title, requestID: event.requestId)
            case "seerr-available": await NotificationManager.notifyRequestAvailable(title: title, requestID: event.requestId)
            case "announcement" where announcements && seen?.contains(event.id) == false:
                await NotificationManager.notifyAnnouncement(id: event.id, title: event.title, message: event.body ?? "")
            case "maintenance" where announcements && seen?.contains(event.id) == false:
                guard let starts = event.starts, let ends = event.ends else { continue }
                let window = MaintenanceWindow(id: event.id, starts: starts, ends: ends, message: event.body ?? "")
                await NotificationManager.notifyMaintenance(id: event.id, summary: await MainActor.run { window.summary })
            case "test": await NotificationManager.notifyServerTest(id: event.id)
            case "seerr-pending" where toApprove, "seerr-auto-approved" where toApprove, "seerr-failed" where toApprove:
                await NotificationManager.notifyRequestToManage(event, title: title, hidingDetails: pinLocked)
            case "issue-reported" where issues, "issue-comment" where issues, "issue-resolved" where issues,
                 "issue-reopened" where issues:
                await NotificationManager.notifyIssue(event, hidingDetails: pinLocked)
            case "arcs-sent" where arcsSent:
                await NotificationManager.notifyArcsSent(event, hidingDetails: pinLocked)
            default: continue
            }
        }
    }

    // MARK: - Seerr

    private static func checkSeerr(requestUpdates: Bool, watchlist: Bool) async {
        // Like the other checks, nothing for a profile with an app-lock PIN.
        guard requestUpdates || watchlist, IntentSession.credential() != nil else { return }
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
        guard !password.isEmpty || (method.isJellyfin && authorizer != nil) else { return }
        let client = SeerrHTTPClient(baseURL: url, username: username, password: password, authMethod: method,
                                     authorizeQuickConnect: authorizer,
                                     onSavedPasswordRejected: { try? KeychainStore().deleteSeerrPassword() })

        if requestUpdates, let requests = try? await client.getRequests(limit: 100) {
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
                await NotificationManager.notifyRequestAvailable(title: item.mediaTitle, requestID: item.id)
            } else if item.status == .approved, oldStatus != RequestStatus.approved.rawValue {
                await NotificationManager.notifyRequestApproved(title: item.mediaTitle, requestID: item.id)
            } else if item.status == .declined, oldStatus != RequestStatus.declined.rawValue {
                await NotificationManager.notifyRequestDeclined(title: item.mediaTitle, requestID: item.id)
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
