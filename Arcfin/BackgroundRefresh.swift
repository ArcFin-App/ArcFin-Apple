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
    private static let seenFilmsKey = "arcfin.notify.seenFilmIDs"
    private static let seenEpisodesKey = "arcfin.notify.seenEpisodeIDs"
    private static let lastActivityKey = "arcfin.notify.lastActivityID"
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
        for key in [seenFilmsKey, seenEpisodesKey, lastActivityKey, seerrStatusKey, announcedWatchlistKey,
                    NotificationManager.sentRequestNoticesKey] {
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
            await check()
            box.task.setTaskCompleted(success: !Task.isCancelled)
        }
        box.task.expirationHandler = { work.cancel() }
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
                                     authorizeQuickConnect: authorizer,
                                     onSavedPasswordRejected: { try? KeychainStore().deleteSeerrPassword() })

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
