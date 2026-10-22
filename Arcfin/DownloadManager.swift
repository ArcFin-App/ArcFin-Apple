// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network
import Observation
import SwiftData
import AuthCore
import JellyfinAPI
import LiveActivityKit
import Persistence
import SyncEngine
#if canImport(UIKit) && !os(tvOS)
import UIKit
#endif
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

enum DownloadError: LocalizedError {
    case permissionDenied
    case noVideoStream

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "This account doesn't have permission to download media. Ask your Jellyfin admin to enable \"Allow media downloading\" for your user."
        case .noVideoStream:
            return "Couldn't find a video stream for this item."
        }
    }
}

struct DownloadStats: Sendable {
    var bytesWritten: Int64
    var totalBytes: Int64
    var bytesPerSecond: Double
}

@MainActor
@Observable
final class DownloadManager: NSObject {

    private(set) var progress: [String: Double] = [:]
    private(set) var stats: [String: DownloadStats] = [:]
    private(set) var activeItemIds: Set<String> = []
    private(set) var activeItemTitles: [String: String] = [:]
    /// Keyed by itemId — a shared single error string would show the wrong download's
    /// failure on an unrelated DownloadButton if more than one item is downloading at once.
    var errors: [String: String] = [:]

    @ObservationIgnored private var modelContext: ModelContext?
    /// Weak, and only ever used for orphan recovery (see recoverOrphanedDownload) — every
    /// normal download call site already passes its own credential/authHeader explicitly.
    @ObservationIgnored private weak var authManager: AuthManager?
    @ObservationIgnored private let client = JellyfinMediaClient()
    @ObservationIgnored private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    /// A title downloading as several byte ranges at once (see downloadInParts).
    @ObservationIgnored private var partTasks: [String: [URLSessionDownloadTask]] = [:]
    @ObservationIgnored private var partBytes: [Int: Int64] = [:]
    @ObservationIgnored private var partTotals: [String: Int64] = [:]
    @ObservationIgnored private var taskItemIds: [Int: String] = [:]
    /// Queued titles whose video transfer was handed to the background session ahead of its
    /// turn, and how each ended if it did before its turn came.
    @ObservationIgnored private var handedOffItemIds: Set<String> = []
    @ObservationIgnored private var handedOffResults: [String: Result<Void, Error>] = [:]
    /// Where a handed-off transfer lands; renamed once the title's container is known.
    private nonisolated static let stagedVideoFileName = "video.download"
    @ObservationIgnored private var speedSamples: [String: (time: Date, bytes: Int64)] = [:]
    #if canImport(UIKit) && !os(tvOS)
    @ObservationIgnored private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    #endif
    #if canImport(ActivityKit) && os(iOS)
    @ObservationIgnored private var liveActivity: Activity<DownloadActivityAttributes>?
    /// Poster thumbnail + season/episode per active item, fetched once per item start
    /// (network call, so filled in asynchronously — the activity starts without it and
    /// picks it up on the next refresh once the fetch completes).
    @ObservationIgnored private var liveActivityItemMeta: [String: (posterData: Data?, season: Int?, episode: Int?)] = [:]
    #endif
    /// Counts across the whole current queue run (reset when a fresh run starts after the
    /// previous one fully drained) — drives the Live Activity's "N of M" display.
    @ObservationIgnored private var queueCompletedCount = 0
    @ObservationIgnored private var queueTotalCount = 0
    /// Own path monitor rather than reusing AuthManager's (which only re-resolves the
    /// server URL and doesn't expose its current path) — kept running for the app's
    /// lifetime, same pattern as AuthManager's own monitor.
    @ObservationIgnored private var wifiPathMonitor: NWPathMonitor?
    @ObservationIgnored private var isOnMobileData = false
    @ObservationIgnored private var isOnLowDataMode = false
    @ObservationIgnored private var isRunningSmartDownloads = false
    @ObservationIgnored private var smartDownloadsRerunRequested = false

    /// Why the queue is waiting instead of starting the next title.
    enum QueueHold: Equatable {
        case mobileData, lowDataMode, lowPowerMode

        var title: String {
            switch self {
            case .mobileData: "Waiting for Wi-Fi"
            case .lowDataMode: "Low Data Mode Is On"
            case .lowPowerMode: "Low Power Mode Is On"
            }
        }
        var detail: String {
            switch self {
            case .mobileData: "Downloads start when you're on Wi-Fi."
            case .lowDataMode: "Downloads start when Low Data Mode is off."
            case .lowPowerMode: "Downloads start when Low Power Mode is off."
            }
        }
    }

    private(set) var queueHold: QueueHold?
    /// Given from Downloads with Start; lasts until the queue drains.
    @ObservationIgnored private var holdOverridden = false

    private var isWiFiOnly: Bool { UserDefaults.standard.object(forKey: "wifiOnly") as? Bool ?? true }
    private var smartDownloadsAllowMobileData: Bool { UserDefaults.standard.bool(forKey: "smartDownloadsAllowMobileData") }

    /// Smart Downloads has its own mobile data setting, separate from downloads people start.
    private func hold(viaSmart: Bool) -> QueueHold? {
        guard !holdOverridden else { return nil }
        let defaults = UserDefaults.standard
        if isOnMobileData, viaSmart ? !smartDownloadsAllowMobileData : isWiFiOnly { return .mobileData }
        if isOnLowDataMode, defaults.bool(forKey: "pauseDownloadsInLowDataMode") { return .lowDataMode }
        if ProcessInfo.processInfo.isLowPowerModeEnabled, defaults.bool(forKey: "pauseDownloadsInLowPowerMode") { return .lowPowerMode }
        return nil
    }

    /// Settings › Downloads › Downloads at Once.
    private var concurrentDownloadLimit: Int {
        max(1, min(3, UserDefaults.standard.object(forKey: "concurrentDownloads") as? Int ?? 1))
    }
    /// True background session on iOS — transfer keeps going, managed by nsurlsessiond,
    /// even if the app is suspended or killed; iOS relaunches the app to redeliver the
    /// delegate callback via AppDelegate's handleEventsForBackgroundURLSession. tvOS/macOS
    /// don't get the same relaunch guarantee (no AppDelegate wired for it here), so they
    /// stay on a plain session — .default is fine since those aren't killed as aggressively.
    static let backgroundSessionIdentifier = "com.psmattas.arcfin.downloads"
    nonisolated(unsafe) static var pendingBackgroundCompletionHandler: (() -> Void)?
    @ObservationIgnored private lazy var session: URLSession = {
        #if canImport(UIKit) && !os(tvOS)
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        // Room for a title's parallel ranges (downloadInParts) next to another title's; titles
        // handed over ahead of their turn (handOffQueue) still wait here past that.
        config.httpMaximumConnectionsPerHost = 8
        #else
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        #endif
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func configure(modelContext: ModelContext, authManager: AuthManager) {
        self.modelContext = modelContext
        self.authManager = authManager
        // `session` was only ever touched lazily, on the first actual download action —
        // meaning after a relaunch (e.g. the app was killed while a background download
        // was in flight), nothing registered this session's delegate until the user
        // happened to start/cancel some other download, so a task that had already
        // finished or failed while the app wasn't running sat undelivered, possibly past
        // the point the OS still had its temp file around. Touching it here forces that
        // registration immediately at launch instead.
        _ = session
        // Smart Downloads used to follow Wi-Fi Only; carry that over the first time.
        if UserDefaults.standard.object(forKey: "smartDownloadsAllowMobileData") == nil {
            UserDefaults.standard.set(!isWiFiOnly, forKey: "smartDownloadsAllowMobileData")
        }
        startWiFiMonitoringIfNeeded()
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.recheckQueueHold() }
        }
        #if canImport(ActivityKit) && os(iOS)
        reconcileStaleActivitiesOnLaunch()
        #endif
        runSmartDownloadsOnLaunch()
        removeExpiredDownloads()
        purgeWatchedDownloads()
    }

    /// Settings › Downloads › Remove Downloads After, and removing watched ones when the
    /// device is low on space. Queued, not deleted here, for the same reason as watched ones.
    func removeExpiredDownloads() {
        guard let modelContext else { return }
        let items = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>())) ?? []
        let days = UserDefaults.standard.integer(forKey: "removeDownloadsAfterDays")
        if days > 0 {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            for item in items where item.downloadedAt < cutoff { markForDeletionAfterWatching(itemId: item.itemId) }
        }
        guard UserDefaults.standard.bool(forKey: "removeWatchedWhenLowOnSpace"),
              let free = try? DownloadStore.rootDirectory().deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        else { return }
        var shortfall = Int64(Self.lowSpaceThreshold) - Int64(free)
        for item in items.filter(\.played).sorted(by: { $0.downloadedAt < $1.downloadedAt }) where shortfall > 0 {
            markForDeletionAfterWatching(itemId: item.itemId)
            shortfall -= item.fileSizeBytes
        }
    }

    private static let lowSpaceThreshold = 2_000_000_000

    private static let pendingWatchedDeleteKey = "pendingWatchedDeleteIDs"

    /// Queues a finished download for removal instead of deleting it on the spot: the player
    /// is usually still on screen above a detail view bound to that SwiftData row, and
    /// reading a deleted model from there is unsafe. See purgeWatchedDownloads.
    func markForDeletionAfterWatching(itemId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: Self.pendingWatchedDeleteKey) ?? []
        guard !ids.contains(itemId) else { return }
        ids.append(itemId)
        UserDefaults.standard.set(ids, forKey: Self.pendingWatchedDeleteKey)
    }

    /// Run at launch and whenever the Downloads list appears — points where no detail view
    /// can be holding one of the queued rows.
    func purgeWatchedDownloads() {
        let ids = UserDefaults.standard.stringArray(forKey: Self.pendingWatchedDeleteKey) ?? []
        guard !ids.isEmpty, let modelContext else { return }
        // A download whose watching here hasn't reached the server yet stays until it has:
        // deleting it would lose that for good.
        let unsynced = Set(((try? modelContext.fetch(FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.needsSync }))) ?? []).map(\.itemId))
        UserDefaults.standard.set(ids.filter(unsynced.contains), forKey: Self.pendingWatchedDeleteKey)
        for id in ids where !unsynced.contains(id) { deleteDownload(itemId: id) }
    }

    /// Brings each download's watched state and position in line with the server, after first
    /// sending what was watched here. Watching on another device or on the web otherwise never
    /// reaches a downloaded copy, so Smart Downloads and Delete After Watching couldn't act on it.
    func reconcileWatchedState() async {
        guard let modelContext, let authManager else { return }
        let profiles = authManager.profiles
        let authClient = authManager.authClient
        await OfflineProgressSync.syncPending(modelContext: modelContext, profiles: profiles,
                                              authHeader: { authClient.authHeader(token: $0.accessToken) })
        let settled = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>(predicate: #Predicate { !$0.needsSync }))) ?? []
        let deletesWatched = UserDefaults.standard.bool(forKey: "deleteDownloadsAfterWatching")
        for items in Dictionary(grouping: settled, by: { "\($0.serverId)|\($0.userId)" }).values {
            guard let first = items.first,
                  let credential = profiles.first(where: { $0.id.uuidString == first.serverId && $0.userID == first.userId }),
                  let server = try? await client.getUserData(credential: credential, authHeader: authClient.authHeader(token: credential.accessToken),
                                                             itemIds: items.map(\.itemId))
            else { continue }
            for item in items {
                guard let remote = server[item.itemId] else { continue }
                let newlyWatched = remote.played && !item.played
                item.played = remote.played
                item.playbackPositionTicks = remote.played ? 0 : remote.playbackPositionTicks
                // Delete After Watching counts finishing it anywhere, not only here.
                if newlyWatched && deletesWatched { markForDeletionAfterWatching(itemId: item.itemId) }
            }
        }
        try? modelContext.save()
    }

    private func startWiFiMonitoringIfNeeded() {
        guard wifiPathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // isExpensive covers a personal hotspot too, which bills the same mobile data.
            let onMobileData = path.status == .satisfied && path.isExpensive
            let lowDataMode = path.status == .satisfied && path.isConstrained
            guard let self else { return }
            Task { @MainActor in self.networkChanged(onMobileData: onMobileData, lowDataMode: lowDataMode) }
        }
        monitor.start(queue: DispatchQueue(label: "arcfin.downloads.pathMonitor"))
        wifiPathMonitor = monitor
    }

    /// For the player's Quality on Mobile Data, read as it opens.
    static private(set) var isOnMobileDataNow = false

    private func networkChanged(onMobileData: Bool, lowDataMode: Bool) {
        isOnMobileData = onMobileData
        isOnLowDataMode = lowDataMode
        Self.isOnMobileDataNow = onMobileData
        recheckQueueHold()
    }

    /// Starts a held queue once the network, power state or settings allow it.
    func recheckQueueHold() {
        guard queueHold != nil, let first = pendingQueue.first, hold(viaSmart: first.viaSmart) == nil else { return }
        queueHold = nil
        Task { await processQueue() }
    }

    /// Starts a held queue anyway, once the person has accepted the cost.
    func startHeldDownloads() {
        holdOverridden = true
        guard queueHold != nil else { return }
        queueHold = nil
        Task { await processQueue() }
    }

    /// Mirrors reconcileStaleActivitiesOnLaunch's own delay — authManager.checkStoredAuth()
    /// runs concurrently from ContentView's own `.task`, so `authManager.state` isn't
    /// reliably `.authenticated` yet at the moment `configure` itself is called.
    private func runSmartDownloadsOnLaunch() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard let authManager, let credential = authManager.state.credential else { return }
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            await reconcileWatchedState()
            await runSmartDownloadsIfNeeded(credential: credential, authHeader: authHeader)
            purgeWatchedDownloads()
        }
    }

    #if canImport(ActivityKit) && os(iOS)
    /// A Live Activity survives independently of this (fresh, per-launch) DownloadManager
    /// instance — if the app was killed mid-download and relaunched, the activity from
    /// before is still sitting there even though activeItemIds/pendingQueue start empty
    /// again, looking exactly like "the queue is empty but the Live Activity is still up".
    /// Gives any redelivered background-session events a moment to repopulate real state
    /// first; only ends activities that are still unaccounted for after that.
    private func reconcileStaleActivitiesOnLaunch() {
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard activeItemIds.isEmpty, pendingQueue.isEmpty else { return }
            for activity in Activity<DownloadActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    #endif

    // MARK: - Live Activity

    #if canImport(ActivityKit) && os(iOS)
    private func beginLiveActivity(currentItemTitle: String) {
        guard liveActivity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = DownloadActivityAttributes.ContentState(
            currentItemTitle: currentItemTitle, bytesWritten: 0, totalBytes: 0, bytesPerSecond: 0,
            completedCount: 0, totalCount: queueTotalCount
        )
        liveActivity = try? Activity.request(
            attributes: DownloadActivityAttributes(),
            content: ActivityContent(state: state, staleDate: nil)
        )
    }

    private func refreshLiveActivity(
        isFinished: Bool = false,
        finishedTitle: String? = nil,
        finishedMeta: (posterData: Data?, season: Int?, episode: Int?)? = nil
    ) {
        guard let liveActivity else { return }
        let itemId = activeItemIds.first
        let stat = itemId.flatMap { stats[$0] }
        let meta = isFinished ? finishedMeta : itemId.flatMap { liveActivityItemMeta[$0] }
        // Held for Wi-Fi, nothing has started yet: show the first title waiting.
        let waiting = itemId == nil ? pendingQueue.first?.item : nil
        let title = isFinished ? (finishedTitle ?? "") : (itemId.flatMap { activeItemTitles[$0] } ?? waiting?.name ?? "")
        // Spread the current title over time at the present speed: starting where it would
        // have to have begun to be this far along, ending when the rest arrives.
        var estimate: (start: Date, finish: Date)?
        if let stat, stat.bytesPerSecond > 0, stat.totalBytes > stat.bytesWritten {
            let remaining = Double(stat.totalBytes - stat.bytesWritten) / stat.bytesPerSecond
            let fraction = Double(stat.bytesWritten) / Double(stat.totalBytes)
            let now = Date()
            estimate = (now.addingTimeInterval(-remaining / (1 - fraction) * fraction), now.addingTimeInterval(remaining))
        }
        let state = DownloadActivityAttributes.ContentState(
            currentItemTitle: title,
            bytesWritten: stat?.bytesWritten ?? 0, totalBytes: stat?.totalBytes ?? 0,
            bytesPerSecond: stat?.bytesPerSecond ?? 0,
            completedCount: queueCompletedCount, totalCount: queueTotalCount, isFinished: isFinished,
            posterImageData: meta?.posterData, seasonNumber: meta?.season, episodeNumber: meta?.episode,
            isPaused: !isFinished && (isQueuePaused || itemId.map(pausedItemIds.contains) == true
                || (queueHold != nil && queueHold != .mobileData)),
            nextItemTitle: isFinished ? nil : pendingQueue.first { $0.item.id != waiting?.id }?.item.name,
            estimateStart: estimate?.start, estimatedFinish: estimate?.finish,
            isWaitingForWiFi: !isFinished && queueHold == .mobileData
        )
        Task { await liveActivity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Small thumbnail for the Live Activity — no App Group exists to share a file path with
    /// the widget extension, so a downsized JPEG rides along in the content state itself.
    /// For an episode this prefers the series' own poster over the episode's screenshot —
    /// a landscape episode screenshot crops badly into the activity's portrait thumbnail,
    /// and "which show is this" is more useful at a glance than "which frame of it".
    private func fetchLiveActivityPoster(item: MediaItem, credential: ServerCredential) async {
        let imageType: JellyfinImageType
        let imageID: String
        let tag: String
        if item.type == .episode, let seriesID = item.seriesId, let seriesTag = item.seriesPrimaryImageTag {
            imageID = seriesID
            imageType = .primary
            tag = seriesTag
        } else if let primaryTag = item.primaryImageTag {
            imageID = item.id
            imageType = .primary
            tag = primaryTag
        } else if let thumbTag = item.thumbImageTag {
            imageID = item.id
            imageType = .thumb
            tag = thumbTag
        } else if let seriesID = item.seriesId, let seriesTag = item.seriesPrimaryImageTag {
            imageID = seriesID
            imageType = .primary
            tag = seriesTag
        } else {
            return
        }
          let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: imageID, tag: tag, type: imageType, fillWidth: 120, token: credential.accessToken)
          guard let (data, response) = try? await URLSession.arcfin.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        guard var existing = liveActivityItemMeta[item.id] else { return }
        existing.posterData = Self.liveActivityThumbnail(from: data)
        liveActivityItemMeta[item.id] = existing
        refreshLiveActivity()
    }

    private static func liveActivityThumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 56
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.jpegData(withCompressionQuality: 0.1) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumbnail.count <= 1_800 ? thumbnail : nil
    }

    /// Shows a brief "Download Complete" state before dismissing — matching every other
    /// list's stats/progress reset at this same point, so there's nothing stale left over
    /// for the next queue run to accidentally inherit. Takes the last item's title/poster
    /// explicitly since by the time this runs, performDownload has already cleared
    /// activeItemIds/activeItemTitles/liveActivityItemMeta for it — reading those here
    /// (like the in-progress path does) produced an empty "Download Complete" card with
    /// no title or thumbnail.
    private func endLiveActivity(lastTitle: String, lastMeta: (posterData: Data?, season: Int?, episode: Int?)?) {
        guard let liveActivity else { return }
        refreshLiveActivity(isFinished: true, finishedTitle: lastTitle, finishedMeta: lastMeta)
        self.liveActivity = nil
        Task {
            try? await Task.sleep(for: .seconds(2))
            await liveActivity.end(nil, dismissalPolicy: .after(.now + 60 * 20))
        }
    }

    /// Cancelling isn't completing — no "Download Complete" flourish, no lingering card.
    private func endLiveActivityImmediately() {
        guard let liveActivity else { return }
        self.liveActivity = nil
        Task { await liveActivity.end(nil, dismissalPolicy: .immediate) }
    }
    #endif

    /// Hands every waiting title's video transfer to the background session as the app
    /// leaves the foreground. iOS treats a transfer the app starts once it's already in the
    /// background as discretionary and can hold it off until the app is next opened, which
    /// stalled a queue the moment its current title finished out of sight. Started here,
    /// they carry on without the app; the queue picks up each finished file in turn.
    /// Lower-quality downloads need the server's playback info first, so they keep their turn.
    func handOffQueue() {
        #if canImport(UIKit) && !os(tvOS)
        guard !isQueuePaused else { return }
        for entry in pendingQueue where entry.bitrateCap == nil {
            if hold(viaSmart: entry.viaSmart) != nil { break }
            let itemId = entry.item.id
            guard !handedOffItemIds.contains(itemId), !isDownloaded(itemId),
                  let dir = try? DownloadStore.ensureDirectory(for: itemId) else { continue }
            var req = URLRequest(url: JellyfinMediaClient.originalFileDownloadURL(
                baseURL: entry.credential.baseURL, itemID: itemId, token: entry.credential.accessToken))
            for (name, value) in CustomHTTPHeaders.current { req.setValue(value, forHTTPHeaderField: name) }
            req.setValue(entry.authHeader, forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 60 * 60
            let task = session.downloadTask(with: req)
            task.taskDescription = dir.appendingPathComponent(Self.stagedVideoFileName).path
            taskItemIds[task.taskIdentifier] = itemId
            downloadTasks[itemId] = task
            handedOffItemIds.insert(itemId)
            // Lets a relaunch after the app was ended finish the title from the file alone.
            savePendingDescriptor(itemId: itemId, credentialId: entry.credential.id.uuidString, bitrateCap: nil)
            task.resume()
        }
        #endif
        #if canImport(ActivityKit) && os(iOS)
        // The last update before the app is suspended; the estimate carries it from here.
        refreshLiveActivity()
        #endif
    }

    /// Waits for a handed-off transfer, or takes its result if it already ended.
    private func awaitHandedOff(itemId: String) async throws {
        defer {
            handedOffItemIds.remove(itemId)
            handedOffResults[itemId] = nil
        }
        if let result = handedOffResults[itemId] { return try result.get() }
        guard let task = downloadTasks[itemId] else { throw URLError(.cancelled) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            continuations[task.taskIdentifier] = continuation
        }
    }

    func isDownloaded(_ itemId: String) -> Bool {
        guard let modelContext else { return false }
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    // MARK: - Preview (shown before the user confirms a download)

    struct DownloadPreview: Identifiable {
        let id = UUID()
        var subtitleLanguages: [String]
        var audioLanguages: [String]
        var estimatedSizeBytes: Int64?
        /// True only when the size above is computed from bitrate × runtime rather than a
        /// real Content-Length — the confirm sheet should hedge the number as approximate.
        var estimatedSizeIsApproximate: Bool
        var willRemux: Bool
        /// Source's own bitrate (bits/sec), when the server reports it — the ceiling for
        /// any bitrate the confirm sheet lets the user pick (no point offering to "upscale").
        var sourceBitrate: Int?
        var runtimeTicks: Int64?
        var container: String?
        var videoCodec: String?
        var videoWidth: Int?
        var videoHeight: Int?
        var videoRange: String?
    }

    /// What the confirmation sheet shows before actually starting — same PlaybackInfo call
    /// the real download makes, plus a HEAD request against the resolved video URL for its
    /// size (Content-Length), without downloading anything yet.
    func preview(for item: MediaItem, credential: ServerCredential, authHeader: String) async -> DownloadPreview? {
        guard let info = try? await client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: item.id) else {
            return nil
        }
        // Playback is always VLC for downloads (OfflinePlayerView), which plays the original
        // file natively regardless of container/codec — no remux needed by default anymore.
        // Only an explicit lower-quality pick (handled in performDownload via bitrateCap)
        // still forces one, since that's the only way to actually shrink a download.
        let videoURL = JellyfinMediaClient.originalFileDownloadURL(baseURL: credential.baseURL, itemID: item.id, token: credential.accessToken)

        var headReq = URLRequest(url: videoURL)
        headReq.httpMethod = "HEAD"
        headReq.setValue(authHeader, forHTTPHeaderField: "Authorization")
        headReq.timeoutInterval = 10
        var estimatedSize: Int64?
        if let (_, response) = try? await URLSession.arcfin.data(for: headReq),
           let http = response as? HTTPURLResponse, http.expectedContentLength > 0 {
            estimatedSize = http.expectedContentLength
        }
        // Some servers/proxies don't return Content-Length on a HEAD to this endpoint — fall
        // back to bitrate × runtime rather than showing "Unknown" when we have both figures.
        var isApproximate = false
        if estimatedSize == nil, let bitrate = info.bitrate, let ticks = info.runTimeTicks, ticks > 0 {
            let seconds = Double(ticks) / 10_000_000
            estimatedSize = Int64(Double(bitrate) / 8 * seconds)
            isApproximate = true
        }

        let subtitleLanguages = info.subtitleStreams.compactMap { $0.deliveryUrl != nil ? ($0.language ?? $0.displayTitle ?? "Unknown") : nil }
        let audioLanguages = info.audioStreams.map { $0.language ?? $0.displayTitle ?? "Unknown" }
        return DownloadPreview(
            subtitleLanguages: subtitleLanguages, audioLanguages: audioLanguages,
            estimatedSizeBytes: estimatedSize, estimatedSizeIsApproximate: isApproximate, willRemux: false,
            sourceBitrate: info.bitrate, runtimeTicks: info.runTimeTicks,
            container: info.container, videoCodec: info.videoStream?.codec,
            videoWidth: info.videoStream?.width, videoHeight: info.videoStream?.height,
            videoRange: info.videoStream?.videoRange
        )
    }

    // MARK: - Start download

    private typealias PendingEntry = (item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int?, viaSmart: Bool)

    @ObservationIgnored private var pendingQueue: [PendingEntry] = [] {
        // pendingQueue itself isn't observed (a tuple array), so the UI reads this mirror.
        didSet { queuedItemIds = pendingQueue.map(\.item.id) }
    }
    @ObservationIgnored private var isProcessingQueue = false

    /// Items waiting for their turn, in the order they'll run.
    private(set) var queuedItemIds: [String] = []
    /// When set, the item currently transferring finishes normally but nothing new starts —
    /// a true mid-transfer pause isn't possible with the background session's task model.
    private(set) var isQueuePaused = false

    /// Active transfer first, then the waiting items in queue order.
    var orderedInProgressIds: [String] {
        let queued = Set(queuedItemIds)
        let active = activeItemTitles.keys.filter { !queued.contains($0) }.sorted()
        return active + queuedItemIds
    }

    /// Items whose transfer is suspended mid-download: the bytes already received are kept and
    /// the transfer carries on from there when resumed.
    private(set) var pausedItemIds: Set<String> = []

    /// Every transfer carrying a title: one, or one per range.
    private func transfers(for itemId: String) -> [URLSessionDownloadTask] {
        (partTasks[itemId] ?? []) + (downloadTasks[itemId].map { [$0] } ?? [])
    }

    func pauseDownload(itemId: String) {
        let running = transfers(for: itemId).filter { $0.state == .running }
        guard !running.isEmpty else { return }
        running.forEach { $0.suspend() }
        pausedItemIds.insert(itemId)
        stats[itemId]?.bytesPerSecond = 0
        speedSamples[itemId] = nil
        #if canImport(ActivityKit) && os(iOS)
        refreshLiveActivity()
        #endif
    }

    func resumeDownload(itemId: String) {
        guard pausedItemIds.remove(itemId) != nil else { return }
        transfers(for: itemId).forEach { $0.resume() }
        #if canImport(ActivityKit) && os(iOS)
        refreshLiveActivity()
        #endif
    }

    /// Stops new items starting and suspends the transfer already in flight.
    func pauseQueue() {
        isQueuePaused = true
        for id in Set(downloadTasks.keys).union(partTasks.keys) { pauseDownload(itemId: id) }
    }

    func resumeQueue() {
        isQueuePaused = false
        for id in pausedItemIds { transfers(for: id).forEach { $0.resume() } }
        pausedItemIds = []
        #if canImport(ActivityKit) && os(iOS)
        refreshLiveActivity()
        #endif
        Task { await processQueue() }
    }

    func moveToFront(itemId: String) {
        guard let index = pendingQueue.firstIndex(where: { $0.item.id == itemId }), index > 0 else { return }
        let entry = pendingQueue.remove(at: index)
        pendingQueue.insert(entry, at: 0)
    }

    func cancelAllDownloads() {
        for id in Array(activeItemTitles.keys) { cancelDownload(itemId: id) }
        isQueuePaused = false
    }

    /// Queues the download — a season's worth of episodes all calling this at once
    /// shouldn't fire a dozen simultaneous video downloads, so only one actually runs at a
    /// time; the rest wait their turn here. `bitrateCap` (bits/sec), when set, forces a
    /// remux even for an otherwise direct-downloadable source — that's the only way to
    /// actually reduce a download's bitrate below the source's own.
    func startDownload(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int? = nil, viaSmart: Bool = false) async {
        guard addToQueue(item: item, credential: credential, authHeader: authHeader, bitrateCap: bitrateCap, viaSmart: viaSmart) else { return }
        await processQueue()
    }

    /// Queues without waiting for the queue to run. False when it's already downloaded or queued.
    @discardableResult
    private func addToQueue(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int?, viaSmart: Bool) -> Bool {
        guard modelContext != nil, !isDownloaded(item.id), !activeItemIds.contains(item.id),
              !pendingQueue.contains(where: { $0.item.id == item.id })
        else { return false }
        let isFreshQueue = activeItemIds.isEmpty && pendingQueue.isEmpty
        activeItemTitles[item.id] = item.name
        pendingQueue.append((item, credential, authHeader, bitrateCap, viaSmart))
        #if canImport(ActivityKit) && os(iOS)
        if isFreshQueue {
            queueCompletedCount = 0
            queueTotalCount = 1
            beginLiveActivity(currentItemTitle: item.name)
        } else {
            queueTotalCount += 1
            refreshLiveActivity()
        }
        #endif
        return true
    }

    private enum QueueEvent: Sendable {
        case finished(isEpisode: Bool)
        case woken
    }

    @ObservationIgnored private var queueWake: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var isQueueClosing = false

    /// Lets a running queue start a title added after it began, when a slot is free.
    private func wakeQueue() {
        queueWake?.resume()
        queueWake = nil
    }

    private func nextToStart() -> PendingEntry? {
        while !pendingQueue.isEmpty, !isQueuePaused {
            // A title already handed to the background session is transferring regardless.
            if let first = pendingQueue.first, !handedOffItemIds.contains(first.item.id),
               let reason = hold(viaSmart: first.viaSmart) {
                queueHold = reason
                #if canImport(ActivityKit) && os(iOS)
                refreshLiveActivity()
                #endif
                return nil
            }
            let next = pendingQueue.removeFirst()
            if !isDownloaded(next.item.id) { return next }
        }
        return nil
    }

    /// Runs up to Downloads at Once titles side by side until the queue drains, pauses or
    /// is held. Returns only then, which Smart Downloads relies on for its storage budget.
    private func processQueue() async {
        guard !isProcessingQueue else {
            wakeQueue()
            return
        }
        isProcessingQueue = true
        isQueueClosing = false
        var downloadedEpisode = false
        await withTaskGroup(of: QueueEvent.self) { group in
            var running = 0
            var listening = false
            loop: while true {
                while running < concurrentDownloadLimit, let next = nextToStart() {
                    running += 1
                    group.addTask { @MainActor in
                        await self.performDownload(item: next.item, credential: next.credential, authHeader: next.authHeader, bitrateCap: next.bitrateCap)
                        return .finished(isEpisode: next.item.type == .episode)
                    }
                }
                guard running > 0 else { break }
                if !listening {
                    listening = true
                    group.addTask { @MainActor in
                        await withCheckedContinuation { continuation in
                            if self.isQueueClosing { continuation.resume() } else { self.queueWake = continuation }
                        }
                        return .woken
                    }
                }
                switch await group.next() {
                case .finished(let isEpisode)?:
                    running -= 1
                    if isEpisode { downloadedEpisode = true }
                case .woken?:
                    listening = false
                case nil:
                    break loop
                }
            }
            isQueueClosing = true
            wakeQueue()
        }
        isProcessingQueue = false
        if pendingQueue.isEmpty { holdOverridden = false }
        // A show just got a downloaded episode, so Smart Downloads can line up the ones after
        // it. Only once the queue has drained: running it mid-queue would reenter this loop
        // (see runSmartDownloadsIfNeeded), and a run already in progress ignores this.
        if downloadedEpisode, !isQueuePaused { refreshSmartDownloads() }
    }

    /// `skipVideoDownload` is set only by orphan recovery (see recoverOrphanedDownload) —
    /// the video file is already correctly at its destination by that point (the OS-level
    /// delegate callback moved it there independent of whether this app process was alive),
    /// so only the metadata/subtitles/trickplay/poster/SwiftData tail needs to run.
    private func performDownload(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int?, skipVideoDownload: Bool = false) async {
        guard let modelContext else { return }
        activeItemIds.insert(item.id)
        progress[item.id] = skipVideoDownload ? 1 : 0
        beginBackgroundTaskIfNeeded()
        savePendingDescriptor(itemId: item.id, credentialId: credential.id.uuidString, bitrateCap: bitrateCap)
        #if canImport(ActivityKit) && os(iOS)
        liveActivityItemMeta[item.id] = (nil, item.parentIndexNumber, item.indexNumber)
        refreshLiveActivity()
        #endif

        do {
            async let detailTask = client.getItemDetailData(credential: credential, authHeader: authHeader, itemId: item.id)
            async let playbackTask = client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: item.id)
            let detailData = try await detailTask
            let detail = try JellyfinMediaClient.decodeItemDetail(detailData)
            let info = try await playbackTask

            #if canImport(ActivityKit) && os(iOS)
            var posterItem = item
            posterItem.primaryImageTag = detail.item.primaryImageTag
            posterItem.thumbImageTag = detail.item.thumbImageTag
            posterItem.seriesId = detail.item.seriesId
            posterItem.seriesPrimaryImageTag = detail.item.seriesPrimaryImageTag
            await fetchLiveActivityPoster(item: posterItem, credential: credential)
            #endif

            let dir = try DownloadStore.ensureDirectory(for: item.id)
            try? detailData.write(to: dir.appendingPathComponent(Self.savedDetailFileName))

            let savesPreviews = UserDefaults.standard.object(forKey: "downloadTrickplay") as? Bool ?? true
            let trickplay = detail.trickplay[info.mediaSourceId] ?? detail.trickplay.values.first
            let savedTrickplay = savesPreviews ? trickplay : nil
            // Everything besides the video, fetched side by side while the video comes down
            // rather than one request at a time after it.
            async let extras = fetchExtras(itemId: item.id, detail: detail, info: info, trickplay: savedTrickplay,
                                           credential: credential, authHeader: authHeader, dir: dir)

            // Playback is always VLC for downloads, which plays the original file's container/
            // codec natively — no remux needed for compatibility. Only an explicit bitrateCap
            // (the user picking a lower quality tier) still forces one, since that's the only
            // way to actually shrink a download below the source's own size.
            let sourceContainer = (info.container ?? "").lowercased()
            let needsRemux = bitrateCap != nil
            let videoFileName = needsRemux ? "video.mp4" : "video.\(sourceContainer.nilIfEmpty ?? "mp4")"
            let videoURL = needsRemux
                ? JellyfinMediaClient.remuxDownloadURL(baseURL: credential.baseURL, itemID: item.id, mediaSourceId: info.mediaSourceId, videoBitRate: min(bitrateCap!, info.bitrate ?? bitrateCap!), token: credential.accessToken)
                : JellyfinMediaClient.originalFileDownloadURL(baseURL: credential.baseURL, itemID: item.id, token: credential.accessToken)
            if handedOffItemIds.contains(item.id) {
                try await awaitHandedOff(itemId: item.id)
            } else if !skipVideoDownload {
                try await downloadFile(from: videoURL, authHeader: authHeader, to: dir.appendingPathComponent(videoFileName),
                                       itemId: item.id, allowsParts: !needsRemux)
            }
            let staged = dir.appendingPathComponent(Self.stagedVideoFileName)
            if FileManager.default.fileExists(atPath: staged.path) {
                let final = dir.appendingPathComponent(videoFileName)
                try? FileManager.default.removeItem(at: final)
                try FileManager.default.moveItem(at: staged, to: final)
            }

            let fetched = await extras

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(videoFileName).path)[.size] as? Int64) ?? 0

            let downloaded = DownloadedItem(
                itemId: item.id, name: detail.item.name, typeRaw: detail.item.type.rawValue,
                overview: detail.item.overview, runtimeTicks: detail.runTimeTicks ?? 0,
                productionYear: detail.item.productionYear, communityRating: detail.item.communityRating,
                officialRating: detail.officialRating, genres: detail.genres,
                seriesId: detail.item.seriesId, seriesName: detail.item.seriesName,
                seasonNumber: detail.item.parentIndexNumber, episodeNumber: detail.item.indexNumber,
                serverId: credential.id.uuidString, serverBaseURL: credential.baseURL.absoluteString, userId: credential.userID,
                videoFileName: videoFileName, posterFileName: fetched.posterFileName, backdropFileName: fetched.backdropFileName,
                subtitleFileNames: fetched.subtitleFileNames, subtitleLanguages: fetched.subtitleLanguages,
                trickplayFileNames: fetched.trickplayFileNames,
                trickplayWidth: savedTrickplay?.width, trickplayHeight: savedTrickplay?.height,
                trickplayTileWidth: savedTrickplay?.tileWidth, trickplayTileHeight: savedTrickplay?.tileHeight,
                trickplayIntervalMs: savedTrickplay?.intervalMs, trickplayThumbnailCount: savedTrickplay?.thumbnailCount,
                introEndSeconds: fetched.introEnd, creditsStartSeconds: fetched.creditsStart,
                fileSizeBytes: fileSize
            )
            downloaded.tagline = detail.taglines.first
            downloaded.studios = detail.studios
            downloaded.directors = detail.directors.map(\.name)
            downloaded.videoSummary = detail.videoStream?.displayTitle
            downloaded.audioSummary = detail.audioStreams.first(where: \.isDefault)?.displayTitle ?? detail.audioStreams.first?.displayTitle
            let cast = Array(detail.cast.prefix(10))
            downloaded.castNames = cast.map(\.name)
            downloaded.castRoles = cast.map { $0.role ?? "" }
            downloaded.castPhotoFileNames = fetched.castPhotoFileNames
            modelContext.insert(downloaded)
            try? modelContext.save()
            Task { await NotificationManager.notifyDownloadComplete(title: detail.item.name) }

            if let seriesId = detail.item.seriesId {
                await ensureSeriesMetadata(seriesId: seriesId, credential: credential, authHeader: authHeader)
            }
        } catch {
            errors[item.id] = (error as? DownloadError)?.errorDescription ?? "Download failed: \(error.localizedDescription)"
            DownloadStore.deleteDirectory(for: item.id)
        }
        removePendingDescriptor(itemId: item.id)

        #if canImport(ActivityKit) && os(iOS)
        let finishedTitle = activeItemTitles[item.id] ?? item.name
        let finishedMeta = liveActivityItemMeta[item.id]
        #endif
        activeItemIds.remove(item.id)
        activeItemTitles[item.id] = nil
        progress[item.id] = nil
        stats[item.id] = nil
        speedSamples[item.id] = nil
        endBackgroundTaskIfIdle()
        #if canImport(ActivityKit) && os(iOS)
        liveActivityItemMeta[item.id] = nil
        queueCompletedCount += 1
        // Another title can still be transferring alongside (Downloads at Once).
        if pendingQueue.isEmpty && activeItemIds.isEmpty {
            endLiveActivity(lastTitle: finishedTitle, lastMeta: finishedMeta)
        } else {
            refreshLiveActivity()
        }
        #endif
    }

    private struct DownloadExtras: Sendable {
        var subtitleFileNames: [String] = []
        var subtitleLanguages: [String] = []
        var trickplayFileNames: [String] = []
        var posterFileName: String?
        var backdropFileName: String?
        var introEnd: Double?
        var creditsStart: Double?
        var castPhotoFileNames: [String] = []
    }

    /// Subtitles, preview tiles, artwork, cast photos and skip markers, all at once.
    private func fetchExtras(itemId: String, detail: MediaItemDetail, info: JellyfinPlaybackInfo, trickplay: JellyfinTrickplayInfo?,
                             credential: ServerCredential, authHeader: String, dir: URL) async -> DownloadExtras {
        let client = client
        async let subtitles = Self.saveSubtitles(info: info, credential: credential, to: dir)
        async let tiles = Self.saveTrickplayTiles(itemId: itemId, trickplay: trickplay, client: client,
                                                  credential: credential, authHeader: authHeader, to: dir)
        async let poster = Self.saveImage(itemId: itemId, tag: detail.item.primaryImageTag, type: .primary, width: 400,
                                          credential: credential, as: "poster.jpg", in: dir)
        async let backdrop = Self.saveImage(itemId: itemId, tag: detail.item.backdropImageTags.first, type: .backdrop, width: 800,
                                            credential: credential, as: "backdrop.jpg", in: dir)
        async let segments = client.getSkipSegments(credential: credential, authHeader: authHeader, itemId: itemId)
        async let castPhotos = Self.saveCastPhotos(Array(detail.cast.prefix(10)), credential: credential, to: dir)
        let (subs, tileNames, posterName, backdropName, skips, cast) = await (subtitles, tiles, poster, backdrop, segments, castPhotos)
        return DownloadExtras(
            subtitleFileNames: subs.map(\.fileName), subtitleLanguages: subs.map(\.language),
            trickplayFileNames: tileNames, posterFileName: posterName, backdropFileName: backdropName,
            introEnd: skips.intro?.upperBound, creditsStart: skips.credits?.lowerBound,
            castPhotoFileNames: cast)
    }

    /// External tracks only (embedded ones travel with the video file itself), per Settings ›
    /// Downloads › Subtitles: all, only the preferred language, or none.
    private static func saveSubtitles(info: JellyfinPlaybackInfo, credential: ServerCredential, to dir: URL) async -> [(fileName: String, language: String)] {
        let choice = UserDefaults.standard.string(forKey: "downloadSubtitles") ?? "all"
        let preferred = UserDefaults.standard.string(forKey: "preferredSubtitleLanguage") ?? ""
        let wanted = info.subtitleStreams.filter { stream in
            guard stream.deliveryUrl != nil else { return false }
            switch choice {
            case "none": return false
            case "preferred" where !preferred.isEmpty: return stream.language == preferred
            default: return true
            }
        }
        return await withTaskGroup(of: (Int, String, String)?.self) { group in
            for (order, stream) in wanted.enumerated() {
                guard let deliveryUrl = stream.deliveryUrl else { continue }
                let fileName = "sub-\(stream.index).vtt", language = stream.language ?? stream.displayTitle ?? "Unknown"
                group.addTask {
                    guard let data = await SubtitleLoader.fetchRawVTTData(deliveryUrl: deliveryUrl, credential: credential),
                          (try? data.write(to: dir.appendingPathComponent(fileName))) != nil
                    else { return nil }
                    return (order, fileName, language)
                }
            }
            var saved: [(Int, String, String)] = []
            for await result in group { if let result { saved.append(result) } }
            return saved.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }
    }

    /// Every tile for the preferred (smallest) width. Array position must equal tileIndex
    /// (that's how playback looks tiles up), so a failed tile keeps an empty placeholder.
    private static func saveTrickplayTiles(itemId: String, trickplay: JellyfinTrickplayInfo?, client: JellyfinMediaClient,
                                           credential: ServerCredential, authHeader: String, to dir: URL) async -> [String] {
        guard let trickplay, trickplay.tileWidth > 0, trickplay.tileHeight > 0, trickplay.thumbnailCount > 0 else { return [] }
        let tileCount = max(Int(ceil(Double(trickplay.thumbnailCount) / Double(trickplay.tileWidth * trickplay.tileHeight))), 1)
        var names = Array(repeating: "", count: tileCount)
        await withTaskGroup(of: (Int, String).self) { group in
            for tileIndex in 0..<tileCount {
                let tileURL = client.trickplayTileURL(credential: credential, itemId: itemId, width: trickplay.width, tileIndex: tileIndex)
                group.addTask {
                    var req = URLRequest(url: tileURL)
                    req.setValue(authHeader, forHTTPHeaderField: "Authorization")
                    let fileName = "tile-\(tileIndex).jpg"
                    guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
                          (resp as? HTTPURLResponse)?.statusCode == 200,
                          (try? data.write(to: dir.appendingPathComponent(fileName))) != nil
                    else { return (tileIndex, "") }
                    return (tileIndex, fileName)
                }
            }
            for await (index, name) in group { names[index] = name }
        }
        return names
    }

    private static func saveImage(itemId: String, tag: String?, type: JellyfinImageType, width: Int,
                                  credential: ServerCredential, as fileName: String, in dir: URL) async -> String? {
        guard let tag else { return nil }
        let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: itemId, tag: tag, type: type, fillWidth: width, token: credential.accessToken)
        guard let (data, _) = try? await URLSession.arcfin.data(from: url),
              (try? data.write(to: dir.appendingPathComponent(fileName))) != nil
        else { return nil }
        return fileName
    }

    /// Small photos of the billed cast, so the downloaded page can show faces offline. An
    /// empty name keeps the arrays aligned for someone without a photo.
    private static func saveCastPhotos(_ cast: [MediaPerson], credential: ServerCredential, to dir: URL) async -> [String] {
        var names = Array(repeating: "", count: cast.count)
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, person) in cast.enumerated() {
                guard let tag = person.primaryImageTag else { continue }
                var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Items/\(person.id)/Images/Primary"), resolvingAgainstBaseURL: false)!
                comps.queryItems = [
                    .init(name: "tag", value: tag), .init(name: "fillWidth", value: "160"),
                    .init(name: "quality", value: "85"), .init(name: "api_key", value: credential.accessToken),
                ]
                let fileName = "cast-\(person.id).jpg"
                guard let url = comps.url else { continue }
                group.addTask {
                    guard let (data, _) = try? await URLSession.arcfin.data(from: url), !data.isEmpty,
                          (try? data.write(to: dir.appendingPathComponent(fileName))) != nil
                    else { return (index, "") }
                    return (index, fileName)
                }
            }
            for await (index, name) in group { names[index] = name }
        }
        return names
    }

    /// Fetches and saves series-level metadata (poster, backdrop, overview) the first time
    /// any of a series' episodes is downloaded — skipped on every later episode of the same
    /// series since the row already exists. Best-effort: a failure here doesn't fail the
    /// episode download itself, it just leaves the series container without a poster/overview
    /// until a later episode download succeeds in fetching it.
    private func ensureSeriesMetadata(seriesId: String, credential: ServerCredential, authHeader: String) async {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<DownloadedSeries>(predicate: #Predicate { $0.seriesId == seriesId })
        guard ((try? modelContext.fetchCount(descriptor)) ?? 0) == 0 else { return }
        guard let detailData = try? await client.getItemDetailData(credential: credential, authHeader: authHeader, itemId: seriesId),
              let detail = try? JellyfinMediaClient.decodeItemDetail(detailData),
              let dir = try? DownloadStore.ensureDirectory(for: seriesId)
        else { return }
        try? detailData.write(to: dir.appendingPathComponent(Self.savedDetailFileName))

        var posterFileName: String?
        if let tag = detail.item.primaryImageTag {
            let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: seriesId, tag: tag, type: .primary, fillWidth: 400, token: credential.accessToken)
            if let (data, _) = try? await URLSession.arcfin.data(from: url) {
                posterFileName = "poster.jpg"
                try? data.write(to: dir.appendingPathComponent("poster.jpg"))
            }
        }
        var backdropFileName: String?
        if let tag = detail.item.backdropImageTags.first {
            let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: seriesId, tag: tag, type: .backdrop, fillWidth: 800, token: credential.accessToken)
            if let (data, _) = try? await URLSession.arcfin.data(from: url) {
                backdropFileName = "backdrop.jpg"
                try? data.write(to: dir.appendingPathComponent("backdrop.jpg"))
            }
        }

        let series = DownloadedSeries(
            seriesId: seriesId, name: detail.item.name, overview: detail.item.overview, genres: detail.genres,
            communityRating: detail.item.communityRating, officialRating: detail.officialRating,
            productionYear: detail.item.productionYear, posterFileName: posterFileName, backdropFileName: backdropFileName
        )
        modelContext.insert(series)
        try? modelContext.save()
    }

    // MARK: - Saved title pages

    private static let savedDetailFileName = "detail.json"

    /// The title's full page as the server sent it when it was downloaded.
    func savedDetail(itemId: String) -> MediaItemDetail? {
        let url = DownloadStore.directory(for: itemId).appendingPathComponent(Self.savedDetailFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JellyfinMediaClient.decodeItemDetail(data)
    }

    /// Downloads made before the full page was kept with them get it the next time
    /// Downloads is open with a connection.
    func saveMissingDetails() async {
        guard let modelContext, let authManager, let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        let items = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>())) ?? []
        let ids = Set(items.map(\.itemId) + items.compactMap(\.seriesId))
        for id in ids {
            let url = DownloadStore.directory(for: id).appendingPathComponent(Self.savedDetailFileName)
            guard !FileManager.default.fileExists(atPath: url.path),
                  let data = try? await client.getItemDetailData(credential: credential, authHeader: authHeader, itemId: id),
                  (try? JellyfinMediaClient.decodeItemDetail(data)) != nil,
                  (try? DownloadStore.ensureDirectory(for: id)) != nil
            else { continue }
            try? data.write(to: url)
        }
    }

    func cancelDownload(itemId: String) {
        let wasQueued = pendingQueue.contains(where: { $0.item.id == itemId }) || activeItemIds.contains(itemId)
        pendingQueue.removeAll { $0.item.id == itemId }
        if pendingQueue.isEmpty { queueHold = nil }
        transfers(for: itemId).forEach { $0.cancel() }
        downloadTasks[itemId] = nil
        clearParts(itemId: itemId)
        handedOffItemIds.remove(itemId)
        handedOffResults[itemId] = nil
        pausedItemIds.remove(itemId)
        activeItemIds.remove(itemId)
        activeItemTitles[itemId] = nil
        progress[itemId] = nil
        stats[itemId] = nil
        speedSamples[itemId] = nil
        DownloadStore.deleteDirectory(for: itemId)
        endBackgroundTaskIfIdle()
        removePendingDescriptor(itemId: itemId)
        #if canImport(ActivityKit) && os(iOS)
        if wasQueued {
            queueTotalCount = max(queueTotalCount - 1, queueCompletedCount)
            if pendingQueue.isEmpty && activeItemIds.isEmpty {
                endLiveActivityImmediately()
            } else {
                refreshLiveActivity()
            }
        }
        #endif
    }

    // MARK: - Orphan recovery (app killed mid-download, relaunched)

    /// Just enough to finish a download's metadata pipeline after a relaunch — deliberately
    /// not the access token itself (that stays in Keychain via AuthManager; this only
    /// records which saved profile to look it up from).
    private struct PendingDownloadDescriptor: Codable {
        let itemId: String
        let credentialId: String
        let bitrateCap: Int?
    }

    private static let pendingDownloadsKey = "arcfin.pendingDownloads"

    private func savePendingDescriptor(itemId: String, credentialId: String, bitrateCap: Int?) {
        var all = loadPendingDescriptors().filter { $0.itemId != itemId }
        all.append(PendingDownloadDescriptor(itemId: itemId, credentialId: credentialId, bitrateCap: bitrateCap))
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.pendingDownloadsKey)
        }
    }

    private func removePendingDescriptor(itemId: String) {
        let remaining = loadPendingDescriptors().filter { $0.itemId != itemId }
        if let data = try? JSONEncoder().encode(remaining) {
            UserDefaults.standard.set(data, forKey: Self.pendingDownloadsKey)
        }
    }

    private func loadPendingDescriptors() -> [PendingDownloadDescriptor] {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingDownloadsKey),
              let decoded = try? JSONDecoder().decode([PendingDownloadDescriptor].self, from: data)
        else { return [] }
        return decoded
    }

    /// Called when a background download task's completion is redelivered with no matching
    /// continuation — meaning this app instance didn't start it, so nothing is waiting on
    /// it. The video file is already safely moved to its destination by the delegate
    /// callback above (that part doesn't depend on any of performDownload's in-memory
    /// state), but the rest of the pipeline — metadata, subtitles, trickplay, poster, the
    /// SwiftData record — never ran, since that WAS tied to the original call's state,
    /// which died with the old process. Without this, the file would just sit orphaned on
    /// disk forever with no record of it and no way to play it from the Downloads screen.
    private func recoverOrphanedDownload(destinationPath: String) async {
        let itemId = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().lastPathComponent
        guard !isDownloaded(itemId),
              let descriptor = loadPendingDescriptors().first(where: { $0.itemId == itemId }),
              let authManager,
              let credential = authManager.profiles.first(where: { $0.id.uuidString == descriptor.credentialId })
        else {
            removePendingDescriptor(itemId: itemId)
            return
        }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        // Placeholder — performDownload re-fetches the real item detail itself and uses
        // that (detail.item.name/type/etc) to build the actual DownloadedItem record; this
        // is only ever read for the Downloads list's in-progress row title and Live
        // Activity meta, neither of which meaningfully applies to a recovery that's already
        // finished downloading its video by the time this runs.
        let placeholder = MediaItem(id: itemId, name: "Resuming…", type: .movie)
        await performDownload(item: placeholder, credential: credential, authHeader: authHeader, bitrateCap: descriptor.bitrateCap, skipVideoDownload: true)
    }

    // MARK: - Background continuation

    /// Not a true background URLSession (that needs app-delegate wiring to reconnect a
    /// completion handler after relaunch) — this just asks iOS for extra runtime so a
    /// download in flight has a real chance to finish if the user backgrounds the app
    /// mid-download, rather than being killed within seconds.
    private func beginBackgroundTaskIfNeeded() {
        #if canImport(UIKit) && !os(tvOS)
        guard backgroundTaskId == .invalid else { return }
        // Per Apple's docs, the expiration handler is called synchronously on the main
        // thread right as the app's background time runs out — dispatching a fresh Task
        // to hop back to MainActor here raced that deadline and regularly lost, producing
        // "Background task still not ended after expiration handlers were called". Calling
        // straight through with assumeIsolated (safe: we're already guaranteed main thread)
        // ends it within the handler itself instead of after it returns.
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "ArcfinDownload") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTaskIfIdle(force: true) }
        }
        #endif
    }

    private func endBackgroundTaskIfIdle(force: Bool = false) {
        #if canImport(UIKit) && !os(tvOS)
        guard force || activeItemIds.isEmpty, backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
        #endif
    }

    func deleteDownload(_ item: DownloadedItem) {
        guard let modelContext else { return }
        let seriesId = item.seriesId
        DownloadStore.deleteDirectory(for: item.itemId)
        modelContext.delete(item)
        try? modelContext.save()
        if let seriesId {
            deleteSeriesMetadataIfNoEpisodesRemain(seriesId: seriesId)
        }
    }

    func deleteDownload(itemId: String) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        deleteDownload(item)
    }

    /// Deletes many at once — used by the downloads screen's multi-select. Runs each through
    /// the same path as a single delete (series cleanup included) rather than batching the
    /// SwiftData writes, since this isn't a hot path and correctness (no orphaned series rows
    /// or files) matters more than a handful of extra save() calls.
    func deleteDownloads(_ items: [DownloadedItem]) {
        for item in items { deleteDownload(item) }
    }

    private func deleteSeriesMetadataIfNoEpisodesRemain(seriesId: String) {
        guard let modelContext else { return }
        let episodeDescriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.seriesId == seriesId })
        guard ((try? modelContext.fetchCount(episodeDescriptor)) ?? 0) == 0 else { return }
        let seriesDescriptor = FetchDescriptor<DownloadedSeries>(predicate: #Predicate { $0.seriesId == seriesId })
        guard let series = try? modelContext.fetch(seriesDescriptor).first else { return }
        DownloadStore.deleteDirectory(for: seriesId)
        modelContext.delete(series)
        try? modelContext.save()
    }

    // MARK: - Smart Downloads

    private static let smartDownloadsEnabledKey = "smartDownloadsEnabled"
    private static let smartDownloadsEpisodeCountKey = "smartDownloadsEpisodeCount"
    private static let smartDownloadsStorageBudgetGBKey = "smartDownloadsStorageBudgetGB"

    /// Shows the user asked to keep topped up from the show's own page, with how many
    /// upcoming episodes to keep. Works with or without the global Smart Downloads toggle.
    struct KeptShow: Codable, Equatable {
        var name: String
        var episodeCount: Int
    }

    private static let keptShowsKey = "smartDownloadsKeptShows"

    static var keptShows: [String: KeptShow] {
        guard let data = UserDefaults.standard.data(forKey: keptShowsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: KeptShow].self, from: data)) ?? [:]
    }

    /// nil `episodeCount` stops keeping that show; its downloads stay until watched or removed.
    func setKeptShow(seriesId: String, name: String, episodeCount: Int?) {
        var shows = Self.keptShows
        shows[seriesId] = episodeCount.map { KeptShow(name: name, episodeCount: $0) }
        UserDefaults.standard.set(try? JSONEncoder().encode(shows), forKey: Self.keptShowsKey)
        if episodeCount != nil { refreshSmartDownloads() }
    }

    /// Catches downloads up with the server's watched state, then re-checks kept shows, from
    /// places other than launch: the app coming to the foreground, the connection coming back,
    /// the player closing, or a show being switched on.
    func refreshSmartDownloads() {
        guard let authManager, let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        Task {
            await reconcileWatchedState()
            await runSmartDownloadsIfNeeded(credential: credential, authHeader: authHeader)
        }
    }

    /// Keeps the next few unwatched episodes downloaded, for every show with downloads when
    /// Smart Downloads is on and for each show kept from its own page, and clears out watched
    /// ones to make room, all capped by a hard storage budget. Deliberately NOT called from
    /// performDownload's own completion path: that would reenter this same queue
    /// (pendingQueue/isProcessingQueue) while its own while-loop is still mid-iteration, so
    /// startDownload would just append and return immediately instead of actually awaiting the
    /// download, which would make the budget check below (totalDownloadedBytes) race against
    /// downloads that haven't happened yet. isRunningSmartDownloads guards reentrancy.
    func runSmartDownloadsIfNeeded(credential: ServerCredential, authHeader: String) async {
        guard let modelContext, ProfileRules.shared.canDownload else { return }
        let globalOn = UserDefaults.standard.object(forKey: Self.smartDownloadsEnabledKey) as? Bool ?? false
        let kept = Self.keptShows
        guard globalOn || !kept.isEmpty else { return }
        guard !isOnMobileData || smartDownloadsAllowMobileData else { return }
        // A check already running read the kept shows before this one was asked for (a show
        // just switched on, say), so it runs once more when it's done instead of dropping it.
        guard !isRunningSmartDownloads else {
            smartDownloadsRerunRequested = true
            return
        }
        isRunningSmartDownloads = true
        defer {
            isRunningSmartDownloads = false
            if smartDownloadsRerunRequested {
                smartDownloadsRerunRequested = false
                Task { await runSmartDownloadsIfNeeded(credential: credential, authHeader: authHeader) }
            }
        }

        let episodeCount = max(1, min(5, UserDefaults.standard.object(forKey: Self.smartDownloadsEpisodeCountKey) as? Int ?? 2))
        let budgetGB = UserDefaults.standard.object(forKey: Self.smartDownloadsStorageBudgetGBKey) as? Int ?? 10
        let budgetBytes = Int64(budgetGB) * 1_000_000_000

        let allDownloaded = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>())) ?? []
        var targets: [String: Int] = [:]
        if globalOn {
            for seriesId in Set(allDownloaded.compactMap(\.seriesId)) { targets[seriesId] = episodeCount }
        }
        for (seriesId, show) in kept { targets[seriesId] = show.episodeCount }
        guard !targets.isEmpty else { return }

        // Watched episodes are queued for removal rather than deleted here: this also runs
        // while a downloads screen may be showing those rows (see markForDeletionAfterWatching).
        for item in allDownloaded where item.played {
            guard let seriesId = item.seriesId, targets[seriesId] != nil else { continue }
            markForDeletionAfterWatching(itemId: item.itemId)
        }

        func totalDownloadedBytes() -> Int64 {
            let current = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>())) ?? []
            return current.reduce(0) { $0 + $1.fileSizeBytes }
        }

        for (seriesId, count) in targets {
            // The episode up next plus the `count` after it: the one you're on doesn't use
            // up the allowance.
            guard let nextUp = try? await client.getUpcomingEpisodes(credential: credential, authHeader: authHeader, seriesId: seriesId, count: count + 1) else { continue }
            // Episodes before the next one up were watched, possibly streamed on another
            // device, which the downloaded copy's own played flag never hears about.
            if kept[seriesId] != nil, let first = nextUp.first,
               let season = first.parentIndexNumber, let episode = first.indexNumber {
                for item in allDownloaded where item.seriesId == seriesId {
                    let s = item.seasonNumber ?? 0, e = item.episodeNumber ?? 0
                    if s < season || (s == season && e < episode) {
                        markForDeletionAfterWatching(itemId: item.itemId)
                    }
                }
            }
            if kept[seriesId] != nil {
                // Asked for by name on the show's page, so Smart Downloads' budget (a setting
                // only shown with Smart Downloads on) doesn't hold it back; the device's own
                // free space still does. Queued together, so they show in Downloads at once.
                for episode in nextUp where Self.freeSpace().map({ $0 > Int64(Self.lowSpaceThreshold) }) ?? true {
                    addToQueue(item: episode, credential: credential, authHeader: authHeader, bitrateCap: nil, viaSmart: true)
                }
                Task { await processQueue() }
                continue
            }
            for episode in nextUp {
                guard !isDownloaded(episode.id), !activeItemIds.contains(episode.id) else { continue }
                guard totalDownloadedBytes() < budgetBytes else { return }
                await startDownload(item: episode, credential: credential, authHeader: authHeader, viaSmart: true)
            }
        }
    }

    private static func freeSpace() -> Int64? {
        (try? DownloadStore.rootDirectory().deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map(Int64.init)
    }

    // MARK: - Video download with progress

    /// On iOS this session is already a true background session, and per Apple's own docs
    /// ("Pausing and resuming downloads"): "downloads that use a background configuration
    /// will handle resumption automatically, so manual resuming is only needed for
    /// non-background downloads." Manually reconstructing a task from resumeData on top of
    /// that turned out actively harmful here — it was producing NSURLErrorCannotDecodeRawData
    /// (-1017) failures and prolonging the beginBackgroundTaskIfNeeded() window past its
    /// grace period. tvOS/macOS use a plain .default session (see `session`'s config above),
    /// which does need this manual retry since it has no automatic resumption of its own.
    private func downloadFile(from url: URL, authHeader: String, to destination: URL, itemId: String, allowsParts: Bool) async throws {
        if allowsParts, try await downloadInParts(from: url, authHeader: authHeader, to: destination, itemId: itemId) { return }
        #if canImport(UIKit) && !os(tvOS)
        try await attemptDownload(url: url, authHeader: authHeader, destination: destination, itemId: itemId, resumeData: nil)
        #else
        var resumeData: Data?
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try await attemptDownload(url: url, authHeader: authHeader, destination: destination, itemId: itemId, resumeData: resumeData)
                return
            } catch {
                lastError = error
                guard let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data else {
                    throw error
                }
                resumeData = data
                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(Double(attempt + 1) * 2))
                }
            }
        }
        throw lastError ?? URLError(.unknown)
        #endif
    }

    private func attemptDownload(url: URL, authHeader: String, destination: URL, itemId: String, resumeData: Data?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task: URLSessionDownloadTask
            if let resumeData {
                // The original request (including the Authorization header) is already
                // encoded in resumeData — nothing to re-attach here.
                task = session.downloadTask(withResumeData: resumeData)
            } else {
                var req = URLRequest(url: url)
                for (name, value) in CustomHTTPHeaders.current { req.setValue(value, forHTTPHeaderField: name) }
                req.setValue(authHeader, forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 60 * 60
                task = session.downloadTask(with: req)
            }
            // Read synchronously (no actor hop) from the delegate callback, which must move
            // the temp file before returning — the OS deletes it right after, so this can't
            // wait on a MainActor round-trip first.
            task.taskDescription = destination.path
            taskItemIds[task.taskIdentifier] = itemId
            downloadTasks[itemId] = task
            continuations[task.taskIdentifier] = continuation
            task.resume()
        }
    }

    @ObservationIgnored private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]

    // MARK: - Parallel ranges

    private static let partCount = 4
    /// Under this, a single connection finishes about as fast as setting up four would.
    private static let minimumSizeForParts: Int64 = 128 * 1_000_000

    private nonisolated static func partFileName(_ index: Int, of count: Int) -> String { "video.part-\(index)-of-\(count)" }

    /// Brings a large original file down as several byte ranges at once and joins them. One
    /// connection is often held well under the line's speed (a reverse proxy, TLS, distance);
    /// a few side by side fill it. Returns false, having downloaded nothing, when the server
    /// doesn't serve ranges or the file is small, so the caller uses a single transfer.
    private func downloadInParts(from url: URL, authHeader: String, to destination: URL, itemId: String) async throws -> Bool {
        guard let total = await Self.rangeSupportedSize(of: url, authHeader: authHeader),
              total >= Self.minimumSizeForParts
        else { return false }
        let count = Self.partCount
        let chunk = total / Int64(count)
        let ranges = (0..<count).map { index -> ClosedRange<Int64> in
            let start = Int64(index) * chunk
            return start...(index == count - 1 ? total - 1 : start + chunk - 1)
        }
        let dir = destination.deletingLastPathComponent()
        let partURLs = (0..<count).map { dir.appendingPathComponent(Self.partFileName($0 + 1, of: count)) }
        partTotals[itemId] = total
        defer { clearParts(itemId: itemId) }
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, range) in ranges.enumerated() {
                    group.addTask { @MainActor in
                        try await self.downloadPart(url: url, authHeader: authHeader, range: range, to: partURLs[index], itemId: itemId)
                    }
                }
                try await group.waitForAll()
            }
        } catch {
            transfers(for: itemId).forEach { $0.cancel() }
            partURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
        // A server that answered a range with the whole file: start over as one transfer.
        for (index, range) in ranges.enumerated() {
            let size = (try? FileManager.default.attributesOfItem(atPath: partURLs[index].path)[.size] as? Int64) ?? -1
            if size != Int64(range.count) {
                partURLs.forEach { try? FileManager.default.removeItem(at: $0) }
                return false
            }
        }
        try await Task.detached(priority: .utility) { try Self.join(partURLs, into: destination) }.value
        return true
    }

    private func downloadPart(url: URL, authHeader: String, range: ClosedRange<Int64>, to partURL: URL, itemId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var req = URLRequest(url: url)
            for (name, value) in CustomHTTPHeaders.current { req.setValue(value, forHTTPHeaderField: name) }
            req.setValue(authHeader, forHTTPHeaderField: "Authorization")
            req.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
            req.timeoutInterval = 60 * 60
            let task = session.downloadTask(with: req)
            task.taskDescription = partURL.path
            taskItemIds[task.taskIdentifier] = itemId
            partTasks[itemId, default: []].append(task)
            continuations[task.taskIdentifier] = continuation
            task.resume()
        }
    }

    private func clearParts(itemId: String) {
        for task in partTasks[itemId] ?? [] { partBytes[task.taskIdentifier] = nil }
        partTasks[itemId] = nil
        partTotals[itemId] = nil
    }

    /// The file's size, when the server answers a one-byte range request with 206.
    private nonisolated static func rangeSupportedSize(of url: URL, authHeader: String) async -> Int64? {
        var req = URLRequest(url: url)
        for (name, value) in CustomHTTPHeaders.current { req.setValue(value, forHTTPHeaderField: name) }
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        req.timeoutInterval = 15
        guard let (_, response) = try? await URLSession.arcfin.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 206,
              let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
              let total = contentRange.split(separator: "/").last.flatMap({ Int64($0) })
        else { return nil }
        return total
    }

    /// Appends the later parts onto the first, 8 MB at a time, and removes them.
    private nonisolated static func join(_ parts: [URL], into destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: parts[0], to: destination)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        try output.seekToEnd()
        for part in parts.dropFirst() {
            let input = try FileHandle(forReadingFrom: part)
            while let data = try input.read(upToCount: 8 * 1_048_576), !data.isEmpty {
                try output.write(contentsOf: data)
            }
            try input.close()
            try FileManager.default.removeItem(at: part)
        }
    }

    /// After a relaunch, each range arrives on its own; once all of a title's are on disk they're
    /// joined into the staged file the rest of the download picks up. Nil until then.
    private nonisolated static func joinOrphanedParts(at partPath: String) throws -> String? {
        let partURL = URL(fileURLWithPath: partPath)
        let name = partURL.lastPathComponent
        guard name.hasPrefix("video.part-"),
              let count = name.split(separator: "-").last.flatMap({ Int($0) })
        else { return partPath }
        let dir = partURL.deletingLastPathComponent()
        let parts = (1...count).map { dir.appendingPathComponent(partFileName($0, of: count)) }
        guard parts.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        let staged = dir.appendingPathComponent(stagedVideoFileName)
        try join(parts, into: staged)
        return staged.path
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let taskId = downloadTask.taskIdentifier
        let now = Date()
        Task { @MainActor in
            guard let itemId = self.taskItemIds[taskId] else { return }
            var totalBytesWritten = totalBytesWritten
            var totalBytesExpectedToWrite = totalBytesExpectedToWrite
            if let total = self.partTotals[itemId] {
                self.partBytes[taskId] = totalBytesWritten
                totalBytesWritten = (self.partTasks[itemId] ?? []).reduce(0) { $0 + (self.partBytes[$1.taskIdentifier] ?? 0) }
                totalBytesExpectedToWrite = total
            }
            if totalBytesExpectedToWrite > 0 {
                self.progress[itemId] = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            }
            // Sampled rather than computed from this single delta — didWriteData can fire
            // many times a second, which would make the displayed speed jump around.
            let bytesPerSecond: Double
            var tookNewSample = false
            if let last = self.speedSamples[itemId], now.timeIntervalSince(last.time) >= 0.5 {
                let elapsed = now.timeIntervalSince(last.time)
                bytesPerSecond = elapsed > 0 ? Double(totalBytesWritten - last.bytes) / elapsed : 0
                self.speedSamples[itemId] = (now, totalBytesWritten)
                tookNewSample = true
            } else if self.speedSamples[itemId] == nil {
                self.speedSamples[itemId] = (now, totalBytesWritten)
                bytesPerSecond = self.stats[itemId]?.bytesPerSecond ?? 0
                tookNewSample = true
            } else {
                bytesPerSecond = self.stats[itemId]?.bytesPerSecond ?? 0
            }
            self.stats[itemId] = DownloadStats(bytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite, bytesPerSecond: bytesPerSecond)
            #if canImport(ActivityKit) && os(iOS)
            // Throttled to the same ~0.5s cadence as the speed sample above — updating on
            // every didWriteData tick would hammer ActivityKit with far more writes than a
            // glanceable progress bar needs.
            if tookNewSample {
                self.refreshLiveActivity()
            }
            #endif
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Must move the temp file before this method returns — the OS deletes it right
        // after, so this happens synchronously here rather than after a MainActor hop.
        let taskId = downloadTask.taskIdentifier
        var moveError: Error?
        if let path = downloadTask.taskDescription {
            let destination = URL(fileURLWithPath: path)
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                moveError = error
            }
        }
        let capturedMoveError = moveError
        let capturedPath = downloadTask.taskDescription
        Task { @MainActor in
            if let continuation = self.continuations[taskId] {
                self.continuations[taskId] = nil
                if let capturedMoveError { continuation.resume(throwing: capturedMoveError) } else { continuation.resume() }
                return
            }
            // Handed off ahead of its turn and done before it came: the queue picks it up.
            if let itemId = self.taskItemIds[taskId], self.handedOffItemIds.contains(itemId) {
                self.handedOffResults[itemId] = capturedMoveError.map { .failure($0) } ?? .success(())
                return
            }
            // No continuation means this app instance didn't originate the transfer — most
            // likely relaunched specifically to receive this exact redelivered event. The
            // file's already safely moved above; finish the rest of the pipeline for it.
            if capturedMoveError == nil, let capturedPath,
               let videoPath = try? await Task.detached(priority: .utility, operation: { try Self.joinOrphanedParts(at: capturedPath) }).value {
                await self.recoverOrphanedDownload(destinationPath: videoPath)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        let capturedPath = task.taskDescription
        Task { @MainActor in
            if let continuation = self.continuations[taskId] {
                self.continuations[taskId] = nil
                continuation.resume(throwing: error)
                return
            }
            if let itemId = self.taskItemIds[taskId], self.handedOffItemIds.contains(itemId) {
                self.handedOffResults[itemId] = .failure(error)
                return
            }
            // Orphaned and it failed outright — there'll never be a video file to trigger
            // recovery via didFinishDownloadingTo, so the pending descriptor would otherwise
            // sit around forever. Best-effort cleanup only; nothing else was watching this.
            if let capturedPath {
                let itemId = URL(fileURLWithPath: capturedPath).deletingLastPathComponent().lastPathComponent
                self.removePendingDescriptor(itemId: itemId)
            }
        }
    }

    /// iOS calls this once all queued delegate callbacks for the background session have
    /// been replayed after a relaunch — the completion handler AppDelegate stashed must be
    /// called here, or iOS won't snapshot the app / give background time again.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            #if canImport(UIKit) && !os(tvOS)
            Self.pendingBackgroundCompletionHandler?()
            Self.pendingBackgroundCompletionHandler = nil
            #endif
        }
    }
}
