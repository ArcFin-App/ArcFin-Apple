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
import Telemetry
import os
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
    /// The server didn't say how big it is (a conversion streams out as it's made), so
    /// `totalBytes` is the size worked out from the bitrate and runtime.
    var isEstimate = false
}

@MainActor
@Observable
final class DownloadManager: NSObject {

    private(set) var progress: [String: Double] = [:]
    private(set) var stats: [String: DownloadStats] = [:]
    private(set) var activeItemIds: Set<String> = []
    private(set) var activeItemTitles: [String: String] = [:]
    /// The title being downloaded or waiting, for its show, season and episode in Downloads.
    private(set) var activeItems: [String: MediaItem] = [:]
    /// Keyed by itemId — a shared single error string would show the wrong download's
    /// failure on an unrelated DownloadButton if more than one item is downloading at once.
    var errors: [String: String] = [:]

    @ObservationIgnored private var modelContext: ModelContext?
    /// Weak, and only ever used for orphan recovery (see recoverOrphanedDownload) — every
    /// normal download call site already passes its own credential/authHeader explicitly.
    @ObservationIgnored private weak var authManager: AuthManager?
    @ObservationIgnored private let client = JellyfinMediaClient()
    @ObservationIgnored private var encodingByServer: [String: DownloadEncoding] = [:]
    @ObservationIgnored private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    /// A title downloading as several byte ranges at once (see downloadInParts).
    @ObservationIgnored private var partTasks: [String: [URLSessionDownloadTask]] = [:]
    @ObservationIgnored private var partBytes: [Int: Int64] = [:]
    @ObservationIgnored private var partTotals: [String: Int64] = [:]
    @ObservationIgnored private var taskItemIds: [Int: String] = [:]
    /// Queued titles whose video transfer was handed to the background session ahead of its
    /// turn, and how each ended if it did before its turn came.
    @ObservationIgnored private var handedOffItemIds: Set<String> = []
    /// Cancelled on purpose (by hand, or by Delete & Ignore), so its transfer ending isn't a failure.
    @ObservationIgnored private var cancelledItemIds: Set<String> = []
    @ObservationIgnored private var handedOffResults: [String: Result<Void, Error>] = [:]
    /// Each title's current run of performDownload. Cancelling clears it, so a run still
    /// waiting on the server stops at its next step, even if the title was queued again since.
    @ObservationIgnored private var runTokens: [String: UUID] = [:]
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
    /// The last title of a queue that drained while Smart Downloads may still add the next
    /// episodes: the activity shows it as done but stays up, so they join it instead of each
    /// starting an activity of its own (see settleLiveActivity).
    @ObservationIgnored private var liveActivityPendingFinish: (title: String, meta: (posterData: Data?, season: Int?, episode: Int?)?)?
    #endif
    /// Counts across the whole current queue run, including what Smart Downloads adds to it
    /// before the activity ends — drives the Live Activity's "N of M" display.
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
        case mobileData, lowDataMode, lowPowerMode, playing, storage

        var title: String {
            switch self {
            case .storage: String(localized: "Not Enough Space")
            case .playing: String(localized: "Waiting for the Video to End")
            case .mobileData: String(localized: "Waiting for Wi-Fi")
            case .lowDataMode: String(localized: "Low Data Mode Is On")
            case .lowPowerMode: String(localized: "Low Power Mode Is On")
            }
        }
        var detail: String {
            switch self {
            case .playing: String(localized: "Downloads carry on when you close the player, so the video gets the whole connection.")
            case .storage: String(localized: "The rest download once there's room. Delete watched titles in Manage Storage to make some.")
            case .mobileData: String(localized: "Downloads start when you're on Wi-Fi.")
            case .lowDataMode: String(localized: "Downloads start when Low Data Mode is off.")
            case .lowPowerMode: String(localized: "Downloads start when Low Power Mode is off.")
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
        if let need = storageNeeded {
            if let room = roomForDownloads(), room < need { return .storage }
            storageNeeded = nil
        }
        guard !holdOverridden else { return nil }
        let defaults = UserDefaults.standard
        if waitsForPlayer { return .playing }
        if isOnMobileData, viaSmart ? !smartDownloadsAllowMobileData : isWiFiOnly { return .mobileData }
        if isOnLowDataMode, defaults.bool(forKey: "pauseDownloadsInLowDataMode") { return .lowDataMode }
        if ProcessInfo.processInfo.isLowPowerModeEnabled, defaults.bool(forKey: "pauseDownloadsInLowPowerMode") { return .lowPowerMode }
        return nil
    }

    /// Settings › Downloads › Keep Downloading While Playing, off by default: a player open
    /// pauses transfers, the queue and Smart Downloads until it closes.
    static let downloadWhilePlayingKey = "downloadWhilePlaying"
    @ObservationIgnored private var isPlayerOpen = false
    /// Transfers suspended for the player, kept apart from ones paused by hand.
    @ObservationIgnored private var pausedForPlayer: Set<String> = []
    private var waitsForPlayer: Bool {
        isPlayerOpen && !UserDefaults.standard.bool(forKey: Self.downloadWhilePlayingKey)
    }

    func playerOpened() {
        isPlayerOpen = true
        holdOverridden = false
        guard waitsForPlayer else { return }
        for id in Set(downloadTasks.keys).union(partTasks.keys) where !pausedItemIds.contains(id) {
            let running = transfers(for: id).filter { $0.state == .running }
            guard !running.isEmpty else { continue }
            running.forEach { $0.suspend() }
            pausedForPlayer.insert(id)
            stats[id]?.bytesPerSecond = 0
            speedSamples[id] = nil
        }
        Self.smartLog.notice("Player open: \(self.pausedForPlayer.count, privacy: .public) download(s) paused until it closes")
    }

    func playerClosed() {
        let waited = waitsForPlayer
        isPlayerOpen = false
        for id in pausedForPlayer { transfers(for: id).forEach { $0.resume() } }
        pausedForPlayer = []
        recheckQueueHold()
        if waited { refreshSmartDownloads() }
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
        // Every window shares this manager; only the first one sets it up.
        guard self.modelContext == nil else { return }
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
        retryUnfinishedDownloads()
        Task { await restoreSavedQueue() }
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

    // MARK: - Room for downloads

    /// Left free on the device after every download, so the system and other apps keep working.
    private static let spaceReserve: Int64 = 1_000_000_000

    /// Set when the next title didn't fit: the queue waits until this much is free.
    @ObservationIgnored private var storageNeeded: Int64?
    /// What each running transfer will take in all, for working out what's left for the next.
    @ObservationIgnored private var expectedBytes: [String: Int64] = [:]
    /// The video file's own expected size, for progress when the server sends no length.
    @ObservationIgnored private var estimatedStreamBytes: [String: Int64] = [:]

    /// Free space a new download can use: what the device can give (purgeable space included),
    /// less the reserve and what running transfers still have to write. Nil when unknown.
    func roomForDownloads(excluding itemId: String? = nil) -> Int64? {
        #if os(tvOS)
        guard let free = Self.freeSpace() else { return nil }
        #else
        guard let values = try? DownloadStore.rootDirectory().deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]),
              let free = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init)
        else { return nil }
        #endif
        let incoming = expectedBytes.filter { $0.key != itemId }.reduce(Int64(0)) { total, entry in
            total + Int64(Double(entry.value) * (1 - (progress[entry.key] ?? 0)))
        }
        return max(free - Self.spaceReserve - incoming, 0)
    }

    /// The size a download will be: bitrate × runtime, or the chosen lower quality × runtime
    /// with each audio track it keeps.
    private static func expectedSize(of info: JellyfinPlaybackInfo, bitrateCap: Int?, extraAudioTracks: Int = 0) -> Int64? {
        guard let ticks = info.runTimeTicks, ticks > 0 else { return nil }
        let seconds = Double(ticks) / 10_000_000
        if let bitrateCap {
            let audio = Double(320_000 * (1 + max(extraAudioTracks, 0)))
            return Int64((Double(min(bitrateCap, info.bitrate ?? bitrateCap)) + audio) / 8 * seconds)
        }
        return info.bitrate.map { Int64(Double($0) / 8 * seconds) }
    }

    private struct NoRoomForDownload: Error { let bytes: Int64 }

    /// A write that failed because the disk is full, however the system reported it.
    private static func isOutOfSpace(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteOutOfSpaceError { return true }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOSPC) { return true }
        if (error as? URLError)?.code == .cannotWriteToFile, let free = freeSpace(), free < spaceReserve { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        return false
    }

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
                let wasFinished = item.finishedSinceDownload
                if item.playCountAtDownload == nil {
                    // Downloaded before the count was kept: it counts as finished since then only
                    // if the server's last finish (watched, position back at the start) came after
                    // the download. A rewatch under way keeps its position, so it doesn't.
                    let finishedAfter = remote.played && remote.playbackPositionTicks == 0
                        && (remote.lastPlayedDate.map { $0 > item.downloadedAt } ?? false)
                    item.playCountAtDownload = finishedAfter ? max(0, remote.playCount - 1) : remote.playCount
                }
                item.serverPlayCount = remote.playCount
                let newlyWatched = item.finishedSinceDownload && !wasFinished
                item.played = remote.played
                item.playbackPositionTicks = remote.played ? 0 : remote.playbackPositionTicks
                // Delete After Watching counts finishing it anywhere, not only here.
                if newlyWatched && deletesWatched { markForDeletionAfterWatching(itemId: item.itemId) }
            }
            await saveMissingSkipSegments(items, credential: credential, authHeader: authClient.authHeader(token: credential.accessToken))
        }
        try? modelContext.save()
    }

    /// Downloads made before every skip marker was saved get the rest while the server is
    /// reachable (it just answered for these items), a few at a time.
    private func saveMissingSkipSegments(_ items: [DownloadedItem], credential: ServerCredential, authHeader: String) async {
        for item in items.filter({ !$0.skipSegmentsSaved }).prefix(20) {
            item.skipSegments = await client.getSkipSegments(credential: credential, authHeader: authHeader, itemId: item.itemId)
        }
    }

    private func startWiFiMonitoringIfNeeded() {
        guard wifiPathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // isExpensive covers a personal hotspot too, which bills the same mobile data. A Mac
            // has no mobile data settings of its own, so a phone's synced ones never hold it;
            // Low Data Mode, which a hotspot usually has on, still does.
            #if os(macOS)
            let onMobileData = false
            #else
            let onMobileData = path.status == .satisfied && path.isExpensive
            #endif
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
            // Music downloads keep their own.
            for activity in Activity<DownloadActivityAttributes>.activities where activity.content.state.isMusic != true {
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
        if !isFinished, let pending = liveActivityPendingFinish {
            refreshLiveActivity(isFinished: true, finishedTitle: pending.title, finishedMeta: pending.meta)
            return
        }
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
          guard let data = await URLSession.arcfin.imageData(from: url) else { return }
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

    /// Ends a drained queue's activity once Smart Downloads has nothing more to add to it.
    private func settleLiveActivity() {
        guard let pending = liveActivityPendingFinish, !isRunningSmartDownloads,
              pendingQueue.isEmpty, activeItemIds.isEmpty else { return }
        liveActivityPendingFinish = nil
        endLiveActivity(lastTitle: pending.title, lastMeta: pending.meta)
    }

    /// Cancelling isn't completing — no "Download Complete" flourish, no lingering card.
    private func endLiveActivityImmediately() {
        liveActivityPendingFinish = nil
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
            savePendingDescriptor(itemId: itemId, credentialId: entry.credential.id.uuidString, bitrateCap: nil, tracks: entry.tracks)
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
        /// Set for a season: the sizes above cover this many episodes.
        var episodeCount: Int?
        /// What a lower quality tier is converted to.
        var encoding = DownloadEncoding.unknown
        var audioStreams: [JellyfinMediaStream] = []
        /// Subtitle tracks saved as their own files; embedded ones come with an original file.
        var subtitleStreams: [JellyfinMediaStream] = []
        var defaultAudioIndex: Int?
        var videoStream: JellyfinMediaStream?
    }

    /// Per server for this launch: what its encoding settings (readable by admins) and the
    /// Arcfin Sync plugin's test encodes say a converted download can be.
    func downloadEncoding(credential: ServerCredential, authHeader: String) async -> DownloadEncoding {
        let key = credential.baseURL.absoluteString
        if let known = encodingByServer[key] { return known }
        async let settings = try? JellyfinAdminClient().configuration("encoding", credential: credential, authHeader: authHeader)
        async let encoders = ArcfinSyncClient().fetchEncoders(credential: credential, authHeader: authHeader)
        let options = await settings.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let encoding = DownloadEncoding.choose(allowsHEVC: options?["AllowHevcEncoding"] as? Bool,
                                               allowsAV1: options?["AllowAv1Encoding"] as? Bool,
                                               encodesAV1: await encoders?.encoders["av1"])
        encodingByServer[key] = encoding
        return encoding
    }

    /// What the confirmation sheet shows before actually starting — same PlaybackInfo call
    /// the real download makes, plus a HEAD request against the resolved video URL for its
    /// size (Content-Length), without downloading anything yet.
    func preview(for item: MediaItem, credential: ServerCredential, authHeader: String) async -> DownloadPreview? {
        async let encoding = downloadEncoding(credential: credential, authHeader: authHeader)
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
            videoRange: info.videoStream?.videoRange,
            encoding: await encoding,
            audioStreams: info.audioStreams,
            subtitleStreams: info.subtitleStreams.filter { $0.deliveryUrl != nil },
            defaultAudioIndex: info.defaultAudioStreamIndex,
            videoStream: info.videoStream
        )
    }

    // MARK: - Start download

    private typealias PendingEntry = (item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int?, tracks: DownloadTracks, viaSmart: Bool)

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
        if pausedForPlayer.remove(itemId) != nil {
            pausedItemIds.insert(itemId)
            return
        }
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
    func startDownload(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int? = nil,
                       tracks: DownloadTracks = .all, viaSmart: Bool = false) async {
        guard addToQueue(item: item, credential: credential, authHeader: authHeader, bitrateCap: bitrateCap, tracks: tracks, viaSmart: viaSmart) else { return }
        await processQueue()
    }

    /// Queues without waiting for the queue to run. False when it's already downloaded or queued.
    @discardableResult
    private func addToQueue(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int?,
                            tracks: DownloadTracks = .all, viaSmart: Bool) -> Bool {
        guard modelContext != nil, !isDownloaded(item.id), !activeItemIds.contains(item.id),
              !pendingQueue.contains(where: { $0.item.id == item.id })
        else { return false }
        let isFreshQueue = activeItemIds.isEmpty && pendingQueue.isEmpty
        activeItemTitles[item.id] = item.name
        activeItems[item.id] = item
        cancelledItemIds.remove(item.id)
        if viaSmart { Self.smartItemIds.insert(item.id) }
        pendingQueue.append((item, credential, authHeader, bitrateCap, tracks, viaSmart))
        saveQueueEntry(SavedQueueEntry(item: item, credentialId: credential.id.uuidString, bitrateCap: bitrateCap, tracks: tracks, viaSmart: viaSmart))
        #if canImport(ActivityKit) && os(iOS)
        if isFreshQueue && liveActivityPendingFinish == nil {
            queueCompletedCount = 0
            queueTotalCount = 1
            beginLiveActivity(currentItemTitle: item.name)
        } else {
            liveActivityPendingFinish = nil
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
            removeSavedQueueEntry(itemId: next.item.id)
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
                        await self.performDownload(item: next.item, credential: next.credential, authHeader: next.authHeader, bitrateCap: next.bitrateCap, tracks: next.tracks)
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
        if downloadedEpisode, !isQueuePaused {
            refreshSmartDownloads()
        } else {
            #if canImport(ActivityKit) && os(iOS)
            settleLiveActivity()
            #endif
        }
    }

    /// `skipVideoDownload` is set only by orphan recovery (see recoverOrphanedDownload) —
    /// the video file is already correctly at its destination by that point (the OS-level
    /// delegate callback moved it there independent of whether this app process was alive),
    /// so only the metadata/subtitles/trickplay/poster/SwiftData tail needs to run.
    private func performDownload(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int?,
                                 tracks: DownloadTracks, skipVideoDownload: Bool = false) async {
        guard let modelContext else { return }
        let run = UUID()
        runTokens[item.id] = run
        activeItemIds.insert(item.id)
        progress[item.id] = skipVideoDownload ? 1 : 0
        beginBackgroundTaskIfNeeded()
        savePendingDescriptor(itemId: item.id, credentialId: credential.id.uuidString, bitrateCap: bitrateCap, tracks: tracks)
        #if canImport(ActivityKit) && os(iOS)
        liveActivityItemMeta[item.id] = (nil, item.parentIndexNumber, item.indexNumber)
        refreshLiveActivity()
        #endif

        var keptForRetry = false
        do {
            async let detailTask = client.getItemDetailData(credential: credential, authHeader: authHeader, itemId: item.id)
            async let playbackTask = client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: item.id)
            let detailData = try await detailTask
            let detail = try JellyfinMediaClient.decodeItemDetail(detailData)
            let info = try await playbackTask
            try checkStillWanted(item.id, run: run)
            let keptAudio = tracks.audioStreams(from: info.audioStreams, defaultIndex: info.defaultAudioStreamIndex)
            let encoding = bitrateCap == nil ? nil : await downloadEncoding(credential: credential, authHeader: authHeader)
            try checkStillWanted(item.id, run: run)
            let conversionBitrate: Int? = bitrateCap.flatMap { tier in
                guard let encoding,
                      !encoding.keepsOriginal(forTier: tier, sourceBitrate: info.bitrate, sourceCodec: info.videoStream?.codec)
                else { return nil }
                return encoding.videoBitrate(forTier: tier, sourceBitrate: info.bitrate, sourceCodec: info.videoStream?.codec)
            }

            if !skipVideoDownload, !handedOffItemIds.contains(item.id),
               let expected = Self.expectedSize(of: info, bitrateCap: conversionBitrate, extraAudioTracks: conversionBitrate == nil ? 0 : keptAudio.count - 1) {
                if let room = roomForDownloads(excluding: item.id), room < expected { throw NoRoomForDownload(bytes: expected) }
                expectedBytes[item.id] = expected
                estimatedStreamBytes[item.id] = Self.expectedSize(of: info, bitrateCap: conversionBitrate)
            }

            #if canImport(ActivityKit) && os(iOS)
            var posterItem = item
            posterItem.primaryImageTag = detail.item.primaryImageTag
            posterItem.thumbImageTag = detail.item.thumbImageTag
            posterItem.seriesId = detail.item.seriesId
            posterItem.seriesPrimaryImageTag = detail.item.seriesPrimaryImageTag
            await fetchLiveActivityPoster(item: posterItem, credential: credential)
            try checkStillWanted(item.id, run: run)
            #endif

            let dir = try DownloadStore.ensureDirectory(for: item.id)
            try? detailData.write(to: dir.appendingPathComponent(Self.savedDetailFileName))

            let savesPreviews = UserDefaults.standard.object(forKey: "downloadTrickplay") as? Bool ?? true
            let trickplay = detail.trickplay[info.mediaSourceId] ?? detail.trickplay.values.first
            let savedTrickplay = savesPreviews ? trickplay : nil
            // Everything besides the video, fetched side by side while the video comes down
            // rather than one request at a time after it.
            async let extras = fetchExtras(itemId: item.id, detail: detail, info: info, trickplay: savedTrickplay,
                                           subtitles: tracks.subtitleStreams(from: info.subtitleStreams),
                                           credential: credential, authHeader: authHeader, dir: dir)

            // Playback is always VLC for downloads, which plays the original file's container/
            // codec natively — no remux needed for compatibility. Only a lower quality tier
            // that actually makes the file smaller converts it.
            let sourceContainer = (info.container ?? "").lowercased()
            let needsRemux = conversionBitrate != nil
            let videoFileName = needsRemux ? "video.mp4" : "video.\(sourceContainer.nilIfEmpty ?? "mp4")"
            let videoURL = if let conversionBitrate, let encoding {
                JellyfinMediaClient.remuxDownloadURL(baseURL: credential.baseURL, itemID: item.id, mediaSourceId: info.mediaSourceId,
                                                     videoCodecs: encoding.videoCodecs, videoBitRate: conversionBitrate,
                                                     audioStreamIndex: keptAudio.first?.index, token: credential.accessToken)
            } else {
                JellyfinMediaClient.originalFileDownloadURL(baseURL: credential.baseURL, itemID: item.id, token: credential.accessToken)
            }
            if handedOffItemIds.contains(item.id) {
                try await awaitHandedOff(itemId: item.id)
            } else if !skipVideoDownload {
                try await downloadFile(from: videoURL, authHeader: authHeader, to: dir.appendingPathComponent(videoFileName),
                                       itemId: item.id, run: run, allowsParts: !needsRemux)
            }
            let staged = dir.appendingPathComponent(Self.stagedVideoFileName)
            if FileManager.default.fileExists(atPath: staged.path) {
                let final = dir.appendingPathComponent(videoFileName)
                try? FileManager.default.removeItem(at: final)
                try FileManager.default.moveItem(at: staged, to: final)
            }
            if needsRemux, keptAudio.count > 1 {
                await DownloadAudioTracks.add(Array(keptAudio.dropFirst()), to: dir.appendingPathComponent(videoFileName), itemID: item.id,
                                              mediaSourceId: info.mediaSourceId, credential: credential, authHeader: authHeader)
            }

            let fetched = await extras
            try checkStillWanted(item.id, run: run)

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(videoFileName).path)[.size] as? Int64) ?? 0

            // Starts from the server's watched state: a title already watched would otherwise
            // look newly watched at the next sync, and Delete After Watching would remove it.
            let userData = detail.item.userData ?? item.userData
            let alreadyPlayed = userData?.played ?? false
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
                fileSizeBytes: fileSize,
                playbackPositionTicks: alreadyPlayed ? 0 : (userData?.playbackPositionTicks ?? 0), played: alreadyPlayed
            )
            downloaded.playCountAtDownload = userData?.playCount ?? 0
            downloaded.serverPlayCount = userData?.playCount ?? 0
            downloaded.skipSegments = fetched.skips
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
            // Cancelled while it waited on the server: cancelDownload has cleared up after it,
            // and a run started since owns the folder.
            guard runTokens[item.id] == run else {
                cancelledItemIds.remove(item.id)
                if runTokens[item.id] == nil, !activeItemIds.contains(item.id), !handedOffItemIds.contains(item.id),
                   !pendingQueue.contains(where: { $0.item.id == item.id }) {
                    DownloadStore.deleteDirectory(for: item.id)
                }
                return
            }
            let cancelled = cancelledItemIds.remove(item.id) != nil
                || (error as? URLError)?.code == .cancelled || error is CancellationError
            // The video is already here (recovered, or handed off and finished before its
            // turn) and only its details failed: the file and descriptor stay for a retry.
            if !cancelled {
                if skipVideoDownload {
                    keptForRetry = true
                } else if handedOffItemIds.contains(item.id), case .success? = handedOffResults[item.id] {
                    keptForRetry = true
                }
            }
            // Failed before its handed-off transfer was waited on: that transfer stops too.
            if handedOffItemIds.contains(item.id) {
                if !keptForRetry { downloadTasks[item.id]?.cancel() }
                downloadTasks[item.id] = nil
                handedOffItemIds.remove(item.id)
                handedOffResults[item.id] = nil
            }
            if keptForRetry {
                Self.smartLog.notice("Download details failed, video kept for a retry: \(item.id, privacy: .public)")
            } else {
                DownloadStore.deleteDirectory(for: item.id)
            }
            // Out of room isn't a failure: the title goes back to the front and waits for space.
            if !cancelled, !keptForRetry, let need = (error as? NoRoomForDownload)?.bytes ?? (Self.isOutOfSpace(error) ? expectedBytes[item.id] ?? Int64(Self.lowSpaceThreshold) : nil) {
                Self.smartLog.notice("Downloads waiting for space: \(item.name, privacy: .public) needs \(need, privacy: .public) bytes")
                removePendingDescriptor(itemId: item.id)
                expectedBytes[item.id] = nil
                estimatedStreamBytes[item.id] = nil
                activeItemIds.remove(item.id)
                progress[item.id] = nil
                stats[item.id] = nil
                speedSamples[item.id] = nil
                runTokens[item.id] = nil
                pendingQueue.insert((item, credential, authHeader, bitrateCap, tracks, Self.smartItemIds.contains(item.id)), at: 0)
                storageNeeded = need
                queueHold = .storage
                endBackgroundTaskIfIdle()
                #if canImport(ActivityKit) && os(iOS)
                liveActivityItemMeta[item.id] = nil
                refreshLiveActivity()
                #endif
                return
            }
            if !cancelled, !keptForRetry {
                errors[item.id] = (error as? DownloadError)?.errorDescription ?? "Download failed: \(error.localizedDescription)"
            }
        }
        if !keptForRetry { removePendingDescriptor(itemId: item.id) }
        removeSavedQueueEntry(itemId: item.id)
        runTokens[item.id] = nil
        expectedBytes[item.id] = nil
        estimatedStreamBytes[item.id] = nil

        #if canImport(ActivityKit) && os(iOS)
        let finishedTitle = activeItemTitles[item.id] ?? item.name
        let finishedMeta = liveActivityItemMeta[item.id]
        #endif
        activeItemIds.remove(item.id)
        activeItemTitles[item.id] = nil
        activeItems[item.id] = nil
        progress[item.id] = nil
        stats[item.id] = nil
        speedSamples[item.id] = nil
        endBackgroundTaskIfIdle()
        #if canImport(ActivityKit) && os(iOS)
        liveActivityItemMeta[item.id] = nil
        queueCompletedCount += 1
        // Another title can still be transferring alongside (Downloads at Once).
        if pendingQueue.isEmpty && activeItemIds.isEmpty {
            // A queue run ends by asking Smart Downloads for the episodes after this one.
            if isProcessingQueue {
                liveActivityPendingFinish = (finishedTitle, finishedMeta)
                refreshLiveActivity()
            } else {
                endLiveActivity(lastTitle: finishedTitle, lastMeta: finishedMeta)
            }
        } else {
            refreshLiveActivity()
        }
        #endif
    }

    private func checkStillWanted(_ itemId: String, run: UUID) throws {
        guard runTokens[itemId] == run else { throw CancellationError() }
    }

    private struct DownloadExtras: Sendable {
        var subtitleFileNames: [String] = []
        var subtitleLanguages: [String] = []
        var trickplayFileNames: [String] = []
        var posterFileName: String?
        var backdropFileName: String?
        var skips = SkipSegments()
        var castPhotoFileNames: [String] = []
    }

    /// Subtitles, preview tiles, artwork, cast photos and skip markers, all at once.
    private func fetchExtras(itemId: String, detail: MediaItemDetail, info: JellyfinPlaybackInfo, trickplay: JellyfinTrickplayInfo?,
                             subtitles picked: [JellyfinMediaStream]?, credential: ServerCredential, authHeader: String, dir: URL) async -> DownloadExtras {
        let client = client
        async let subtitles = Self.saveSubtitles(info: info, picked: picked, credential: credential, to: dir)
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
            skips: skips, castPhotoFileNames: cast)
    }

    /// Settings › Downloads › Subtitles: all, only the preferred language, or none. Also what
    /// the download sheet starts with ticked.
    static func subtitlesFromSettings(_ streams: [JellyfinMediaStream]) -> [JellyfinMediaStream] {
        let choice = UserDefaults.standard.string(forKey: "downloadSubtitles") ?? "all"
        let preferred = UserDefaults.standard.string(forKey: "preferredSubtitleLanguage") ?? ""
        return streams.filter { stream in
            guard stream.deliveryUrl != nil else { return false }
            switch choice {
            case "none": return false
            case "preferred" where !preferred.isEmpty: return stream.language == preferred
            default: return true
            }
        }
    }

    /// External tracks only (embedded ones travel with the video file itself): the ones picked
    /// in the download sheet, else per Settings › Downloads › Subtitles.
    private static func saveSubtitles(info: JellyfinPlaybackInfo, picked: [JellyfinMediaStream]?, credential: ServerCredential,
                                      to dir: URL) async -> [(fileName: String, language: String)] {
        let wanted = (picked ?? subtitlesFromSettings(info.subtitleStreams)).filter { $0.deliveryUrl != nil }
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
        guard let data = await URLSession.arcfin.imageData(from: url),
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
                    guard let data = await URLSession.arcfin.imageData(from: url),
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
            if let data = await URLSession.arcfin.imageData(from: url) {
                posterFileName = "poster.jpg"
                try? data.write(to: dir.appendingPathComponent("poster.jpg"))
            }
        }
        var backdropFileName: String?
        if let tag = detail.item.backdropImageTags.first {
            let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: seriesId, tag: tag, type: .backdrop, fillWidth: 800, token: credential.accessToken)
            if let data = await URLSession.arcfin.imageData(from: url) {
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
        if activeItemIds.contains(itemId) { cancelledItemIds.insert(itemId) }
        runTokens[itemId] = nil
        let wasQueued = pendingQueue.contains(where: { $0.item.id == itemId }) || activeItemIds.contains(itemId)
        pendingQueue.removeAll { $0.item.id == itemId }
        if pendingQueue.isEmpty { queueHold = nil; storageNeeded = nil }
        transfers(for: itemId).forEach { $0.cancel() }
        downloadTasks[itemId] = nil
        clearParts(itemId: itemId)
        handedOffItemIds.remove(itemId)
        handedOffResults[itemId] = nil
        pausedItemIds.remove(itemId)
        activeItemIds.remove(itemId)
        activeItemTitles[itemId] = nil
        activeItems[itemId] = nil
        progress[itemId] = nil
        stats[itemId] = nil
        speedSamples[itemId] = nil
        // The run's own clean-up doesn't happen once it's cancelled: left here, these would
        // count as space still to be written for the rest of the session.
        expectedBytes[itemId] = nil
        estimatedStreamBytes[itemId] = nil
        DownloadStore.deleteDirectory(for: itemId)
        endBackgroundTaskIfIdle()
        removePendingDescriptor(itemId: itemId)
        removeSavedQueueEntry(itemId: itemId)
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
        var tracks: DownloadTracks?
    }

    private static let pendingDownloadsKey = "arcfin.pendingDownloads"

    private func savePendingDescriptor(itemId: String, credentialId: String, bitrateCap: Int?, tracks: DownloadTracks) {
        var all = loadPendingDescriptors().filter { $0.itemId != itemId }
        all.append(PendingDownloadDescriptor(itemId: itemId, credentialId: credentialId, bitrateCap: bitrateCap, tracks: tracks))
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
        // A background relaunch can deliver this before the saved sign-ins are read: wait for
        // them, and keep the descriptor while they aren't there to look the profile up in.
        guard let authManager else { return }
        await authManager.checkStoredAuthOnce()
        guard !authManager.profiles.isEmpty, !activeItemIds.contains(itemId) else { return }
        guard !isDownloaded(itemId),
              let descriptor = loadPendingDescriptors().first(where: { $0.itemId == itemId }),
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
        await performDownload(item: placeholder, credential: credential, authHeader: authHeader, bitrateCap: descriptor.bitrateCap,
                              tracks: descriptor.tracks ?? .all, skipVideoDownload: true)
    }

    /// Titles whose video arrived but whose details couldn't be fetched then (no connection,
    /// the server restarting), finished from the file. Run at launch and when the app comes
    /// back or reconnects, not from the queue, so being offline doesn't spin.
    func retryUnfinishedDownloads() {
        guard modelContext != nil else { return }
        let queued = Set(pendingQueue.map(\.item.id))
        for descriptor in loadPendingDescriptors() {
            let itemId = descriptor.itemId
            guard !activeItemIds.contains(itemId), !queued.contains(itemId), !handedOffItemIds.contains(itemId),
                  let path = Self.finishedVideoPath(for: itemId)
            else { continue }
            Task { await recoverOrphanedDownload(destinationPath: path) }
        }
    }

    /// The video file a title's folder holds once its transfer is done. Nil while any range
    /// part is still there: a join cut short leaves a partial file under the final name.
    private nonisolated static func finishedVideoPath(for itemId: String) -> String? {
        let dir = DownloadStore.directory(for: itemId)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              !names.contains(where: { $0.hasPrefix("video.part-") })
        else { return nil }
        return names.first { $0.hasPrefix("video.") }.map { dir.appendingPathComponent($0).path }
    }

    // MARK: - Saved queue (the app ended with titles waiting or downloading)

    /// A title waiting or downloading, kept until it ends so a relaunch can queue it again.
    /// The profile is looked up by id once the saved sign-ins are read; no token is kept here.
    private struct SavedQueueEntry: Codable {
        let itemId: String
        let name: String
        let typeRaw: String
        var seriesId: String?
        var seriesName: String?
        var seasonNumber: Int?
        var episodeNumber: Int?
        let credentialId: String
        let bitrateCap: Int?
        let tracks: DownloadTracks
        let viaSmart: Bool

        init(item: MediaItem, credentialId: String, bitrateCap: Int?, tracks: DownloadTracks, viaSmart: Bool) {
            itemId = item.id; name = item.name; typeRaw = item.type.rawValue
            seriesId = item.seriesId; seriesName = item.seriesName
            seasonNumber = item.parentIndexNumber; episodeNumber = item.indexNumber
            self.credentialId = credentialId; self.bitrateCap = bitrateCap; self.tracks = tracks; self.viaSmart = viaSmart
        }

        var item: MediaItem {
            MediaItem(id: itemId, name: name, type: MediaType(rawValue: typeRaw) ?? .movie, seriesName: seriesName,
                      indexNumber: episodeNumber, parentIndexNumber: seasonNumber, seriesId: seriesId)
        }
    }

    private static let savedQueueKey = "arcfin.downloadQueue"

    private func loadSavedQueue() -> [SavedQueueEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.savedQueueKey),
              let decoded = try? JSONDecoder().decode([SavedQueueEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private func storeSavedQueue(_ entries: [SavedQueueEntry]) {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: Self.savedQueueKey) }
    }

    private func saveQueueEntry(_ entry: SavedQueueEntry) {
        var all = loadSavedQueue()
        guard !all.contains(where: { $0.itemId == entry.itemId }) else { return }
        all.append(entry)
        storeSavedQueue(all)
    }

    private func removeSavedQueueEntry(itemId: String) {
        let all = loadSavedQueue()
        guard all.contains(where: { $0.itemId == itemId }) else { return }
        storeSavedQueue(all.filter { $0.itemId != itemId })
    }

    /// Queues again what was waiting or downloading when the app was last ended. A transfer
    /// the background session kept running is taken back as that title's own, so it shows in
    /// Downloads and can be cancelled; one that was cut off starts over from the queue.
    private func restoreSavedQueue() async {
        let saved = loadSavedQueue()
        guard !saved.isEmpty, let authManager else { return }
        await authManager.checkStoredAuthOnce()
        let profiles = authManager.profiles
        // Not read yet (a locked device, a slow Keychain): left for the next launch.
        guard !profiles.isEmpty else { return }
        var live: [String: [URLSessionTask]] = [:]
        for task in await session.allTasks where task.state == .running || task.state == .suspended {
            guard let path = task.taskDescription else { continue }
            live[URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent, default: []].append(task)
        }
        let descriptors = Set(loadPendingDescriptors().map(\.itemId))
        var restored = false
        for entry in saved {
            let itemId = entry.itemId
            guard !activeItemIds.contains(itemId), !pendingQueue.contains(where: { $0.item.id == itemId }) else { continue }
            guard !isDownloaded(itemId),
                  let credential = profiles.first(where: { $0.id.uuidString == entry.credentialId })
            else {
                removeSavedQueueEntry(itemId: itemId)
                continue
            }
            // The video is here already: retryUnfinishedDownloads finishes it from the file.
            if descriptors.contains(itemId), Self.finishedVideoPath(for: itemId) != nil {
                removeSavedQueueEntry(itemId: itemId)
                continue
            }
            let tasks = live[itemId] ?? []
            if tasks.count == 1, let task = tasks.first as? URLSessionDownloadTask,
               task.taskDescription?.contains("/video.part-") != true {
                taskItemIds[task.taskIdentifier] = itemId
                downloadTasks[itemId] = task
                handedOffItemIds.insert(itemId)
            } else {
                // Range parts can't be waited on as one transfer: they start over with the title.
                tasks.forEach { $0.cancel() }
            }
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            if addToQueue(item: entry.item, credential: credential, authHeader: authHeader, bitrateCap: entry.bitrateCap,
                          tracks: entry.tracks, viaSmart: entry.viaSmart) {
                restored = true
            }
        }
        if restored { await processQueue() }
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
        Self.smartItemIds.remove(item.itemId)
        DownloadStore.deleteDirectory(for: item.itemId)
        modelContext.delete(item)
        try? modelContext.save()
        if let seriesId {
            deleteSeriesMetadataIfNoEpisodesRemain(seriesId: seriesId)
        }
        if queueHold == .storage { recheckQueueHold() }
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

    private static let smartLog = Telemetry.logger(category: "SmartDownloads")
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
        keptShowsVersion += 1
        if episodeCount != nil {
            if ignoredTitles[seriesId] != nil { setIgnored(id: seriesId, name: name, ignored: false) }
            refreshSmartDownloads()
        }
    }

    /// Bumped on every Keep Downloaded change, for screens listing the kept shows.
    private(set) var keptShowsVersion = 0

    private static let ignoredKey = "smartDownloadsIgnored"
    private static let smartMoviesKey = "smartDownloadsMovieIds"

    /// Movies and shows (by series id) Smart Downloads leaves alone, with their names.
    /// Keep Downloaded is asked for by name, so ignoring a show stops keeping it too.
    private(set) var ignoredTitles: [String: String] =
        UserDefaults.standard.dictionary(forKey: ignoredKey) as? [String: String] ?? [:]

    func setIgnored(id: String, name: String, ignored: Bool) {
        ignoredTitles[id] = ignored ? name : nil
        UserDefaults.standard.set(ignoredTitles, forKey: Self.ignoredKey)
        if ignored, Self.keptShows[id] != nil { setKeptShow(seriesId: id, name: name, episodeCount: nil) }
        if ignored {
            // What Smart Downloads queued for it goes too; downloads someone started stay.
            let smart = Self.smartItemIds
            for item in activeItems.values where (item.id == id || item.seriesId == id) && smart.contains(item.id) {
                cancelDownload(itemId: item.id)
            }
        } else {
            refreshSmartDownloads()
        }
    }

    /// Movies Smart Downloads fetched from Continue Watching, so only those (not ones someone
    /// downloaded themselves) go once watched.
    /// Every title Smart Downloads or Keep Downloaded fetched, so deleting one by hand can
    /// offer to ignore it from then on.
    private static let smartItemsKey = "smartDownloadsItemIds"
    private static var smartItemIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: smartItemsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: smartItemsKey) }
    }

    /// What Delete & Ignore would ignore for a title Smart Downloads fetched: the movie, or
    /// the episode's show. nil for a title someone downloaded themselves.
    func smartIgnoreTarget(itemId: String) -> (id: String, name: String)? {
        guard Self.smartItemIds.contains(itemId) else { return nil }
        if let item = activeItems[itemId] {
            return item.seriesId.map { ($0, item.seriesName ?? item.name) } ?? (item.id, item.name)
        }
        guard let modelContext,
              let item = try? modelContext.fetch(FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })).first
        else { return nil }
        return item.seriesId.map { ($0, item.seriesName ?? item.name) } ?? (item.itemId, item.name)
    }

    /// Ignore in Smart Downloads for a title with downloads here, waiting for the person to
    /// say whether those go too.
    struct IgnoreRequest: Identifiable {
        let id: String
        let name: String
        let itemIds: [String]
    }
    var pendingIgnore: IgnoreRequest?

    /// Ignore in Smart Downloads, asking first when the movie or show has downloads here.
    func requestIgnore(id: String, name: String) {
        let itemIds = downloadIds(forTitle: id)
        if itemIds.isEmpty {
            setIgnored(id: id, name: name, ignored: true)
        } else {
            pendingIgnore = IgnoreRequest(id: id, name: name, itemIds: itemIds)
        }
    }

    /// Ignores the title, then removes its downloads, finished or under way.
    func ignoreAndDelete(_ request: IgnoreRequest) {
        setIgnored(id: request.id, name: request.name, ignored: true)
        for id in request.itemIds {
            if activeItemIds.contains(id) || pendingQueue.contains(where: { $0.item.id == id }) {
                cancelDownload(itemId: id)
            } else {
                deleteDownload(itemId: id)
            }
        }
    }

    /// A movie's download, or a show's episodes, here or still downloading.
    private func downloadIds(forTitle id: String) -> [String] {
        let saved = modelContext.flatMap {
            try? $0.fetch(FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == id || $0.seriesId == id }))
        } ?? []
        let underway = activeItems.values.filter { $0.id == id || $0.seriesId == id }.map(\.id)
        return Array(Set(saved.map(\.itemId) + underway))
    }

    /// Ignores the title in Smart Downloads first, so removing it doesn't start it again.
    func deleteAndIgnore(itemIds: [String]) {
        var ignored: Set<String> = []
        for id in itemIds {
            guard let target = smartIgnoreTarget(itemId: id), ignored.insert(target.id).inserted else { continue }
            setIgnored(id: target.id, name: target.name, ignored: true)
        }
        for id in itemIds {
            if activeItemIds.contains(id) || pendingQueue.contains(where: { $0.item.id == id }) {
                cancelDownload(itemId: id)
            } else {
                deleteDownload(itemId: id)
            }
        }
    }

    /// What Smart Downloads has fetched that's still here, against its storage limit.
    func smartDownloadsUsedBytes(of items: [DownloadedItem]) -> Int64 {
        let smart = Self.smartItemIds
        return items.filter { smart.contains($0.itemId) }.reduce(0) { $0 + $1.fileSizeBytes }
    }

    private static var smartMovieIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: smartMoviesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: smartMoviesKey) }
    }

    /// Catches downloads up with the server's watched state, then re-checks kept shows, from
    /// places other than launch: the app coming to the foreground, the connection coming back,
    /// the player closing, or a show being switched on.
    func refreshSmartDownloads() {
        if queueHold == .storage { recheckQueueHold() }
        retryUnfinishedDownloads()
        guard let authManager, let credential = authManager.state.credential else {
            #if canImport(ActivityKit) && os(iOS)
            settleLiveActivity()
            #endif
            return
        }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        Task {
            await reconcileWatchedState()
            await runSmartDownloadsIfNeeded(credential: credential, authHeader: authHeader)
            #if canImport(ActivityKit) && os(iOS)
            settleLiveActivity()
            #endif
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
        guard let modelContext, ProfileRules.shared.canDownload else {
            Self.smartLog.notice("Smart Downloads skipped: downloads not allowed for this profile")
            return
        }
        let globalOn = UserDefaults.standard.object(forKey: Self.smartDownloadsEnabledKey) as? Bool ?? false
        let kept = Self.keptShows
        guard globalOn || !kept.isEmpty else {
            Self.smartLog.notice("Smart Downloads skipped: off, and no show set to Keep Downloaded")
            return
        }
        guard !waitsForPlayer else {
            Self.smartLog.notice("Smart Downloads skipped: a video is playing")
            return
        }
        guard !isOnMobileData || smartDownloadsAllowMobileData else {
            Self.smartLog.notice("Smart Downloads skipped: on mobile data with Use Mobile Data off")
            return
        }
        // A check already running read the kept shows before this one was asked for (a show
        // just switched on, say), so it runs once more when it's done instead of dropping it.
        guard !isRunningSmartDownloads else {
            Self.smartLog.notice("Smart Downloads: check already running, will run again after it")
            smartDownloadsRerunRequested = true
            return
        }
        isRunningSmartDownloads = true
        defer {
            isRunningSmartDownloads = false
            if smartDownloadsRerunRequested {
                smartDownloadsRerunRequested = false
                Task {
                    await runSmartDownloadsIfNeeded(credential: credential, authHeader: authHeader)
                    #if canImport(ActivityKit) && os(iOS)
                    settleLiveActivity()
                    #endif
                }
            }
        }

        let episodeCount = max(1, min(5, UserDefaults.standard.object(forKey: Self.smartDownloadsEpisodeCountKey) as? Int ?? 2))
        let budgetGB = UserDefaults.standard.object(forKey: Self.smartDownloadsStorageBudgetGBKey) as? Int ?? 10
        let budgetBytes = Int64(budgetGB) * 1_000_000_000

        let allDownloaded = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>())) ?? []
        var targets: [String: Int] = [:]
        var movies: [MediaItem] = []
        if globalOn {
            for seriesId in Set(allDownloaded.compactMap(\.seriesId)) { targets[seriesId] = episodeCount }
            // What's being watched: shows in Continue Watching or Next Up, and movies part-way through.
            async let resuming = client.getContinueWatching(credential: credential, authHeader: authHeader)
            async let upNext = client.getNextUpIncludingRecent(credential: credential, authHeader: authHeader)
            for item in ((try? await resuming) ?? []) + ((try? await upNext) ?? []) {
                if let seriesId = item.seriesId { targets[seriesId] = episodeCount }
                else if item.type == .movie { movies.append(item) }
            }
            for id in ignoredTitles.keys { targets[id] = nil }
            movies.removeAll { ignoredTitles[$0.id] != nil }
        }
        for (seriesId, show) in kept { targets[seriesId] = show.episodeCount }
        Self.smartLog.notice("Smart Downloads check: \(targets.count, privacy: .public) show(s), \(movies.count, privacy: .public) movie(s), keep \(episodeCount, privacy: .public), budget \(budgetGB, privacy: .public) GB")

        // Finished since it was downloaded, not just marked watched: a movie in Continue
        // Watching can be a rewatch of one watched before, and is still wanted.
        for item in allDownloaded where item.finishedSinceDownload && Self.smartMovieIds.contains(item.itemId) {
            markForDeletionAfterWatching(itemId: item.itemId)
            Self.smartMovieIds.remove(item.itemId)
        }
        guard !targets.isEmpty || !movies.isEmpty else { return }

        // Watched episodes are queued for removal rather than deleted here: this also runs
        // while a downloads screen may be showing those rows (see markForDeletionAfterWatching).
        for item in allDownloaded where item.finishedSinceDownload {
            guard let seriesId = item.seriesId, targets[seriesId] != nil else { continue }
            markForDeletionAfterWatching(itemId: item.itemId)
        }

        // Only the shows it looks after: movies and other downloads someone started themselves
        // would otherwise use up the budget and quietly stop every show.
        func totalDownloadedBytes() -> Int64 {
            let current = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>())) ?? []
            let smartMovies = Self.smartMovieIds
            return current.filter { $0.seriesId.map { targets[$0] != nil } ?? smartMovies.contains($0.itemId) }
                .reduce(0) { $0 + $1.fileSizeBytes }
        }

        var smart: [MediaItem] = []
        for (seriesId, count) in targets {
            // The episode up next plus the `count` after it: the one you're on doesn't use
            // up the allowance.
            guard var nextUp = try? await client.getUpcomingEpisodes(credential: credential, authHeader: authHeader, seriesId: seriesId, count: count + 1) else {
                Self.smartLog.error("Smart Downloads: couldn't get upcoming episodes for \(seriesId, privacy: .public)")
                continue
            }
            let fromWatchHistory = !nextUp.isEmpty
            if nextUp.isEmpty {
                nextUp = await episodesAfterDownloads(seriesId: seriesId, downloaded: allDownloaded, count: count + 1,
                                                      credential: credential, authHeader: authHeader)
            }
            // Listed ahead of airing, with no file to fetch yet.
            nextUp.removeAll(where: \.isVirtual)
            Self.smartLog.notice("Smart Downloads: \(seriesId, privacy: .public) up next \(nextUp.map { "S\($0.parentIndexNumber ?? 0)E\($0.indexNumber ?? 0)" }.joined(separator: " "), privacy: .public)")
            // Episodes before the next one up were watched, possibly streamed on another
            // device, which the downloaded copy's own played flag never hears about.
            if fromWatchHistory, kept[seriesId] != nil, let first = nextUp.first,
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
                    addToQueue(item: episode, credential: credential, authHeader: authHeader, bitrateCap: DownloadQuality.saved.tier, viaSmart: true)
                }
                Task { await processQueue() }
                continue
            }
            smart.append(contentsOf: nextUp)
        }
        smart.append(contentsOf: movies)

        // Downloads at Once titles at a time, each batch finishing before the budget is checked
        // again, so it can go over by at most one batch less one title.
        var batch = 0
        for item in smart where !isDownloaded(item.id) && !activeItemIds.contains(item.id) {
            // Ignored while an earlier batch ran.
            if ignoredTitles[item.id] != nil || item.seriesId.map({ ignoredTitles[$0] != nil }) == true { continue }
            if batch == 0, totalDownloadedBytes() >= budgetBytes {
                Self.smartLog.notice("Smart Downloads stopped: storage budget of \(budgetGB, privacy: .public) GB reached")
                break
            }
            if batch == 0, queueHold == .storage {
                Self.smartLog.notice("Smart Downloads stopped: the device is out of room")
                break
            }
            guard addToQueue(item: item, credential: credential, authHeader: authHeader, bitrateCap: DownloadQuality.saved.tier, viaSmart: true) else { continue }
            Self.smartLog.notice("Smart Downloads queuing \(item.name, privacy: .public)")
            if item.seriesId == nil { Self.smartMovieIds.insert(item.id) }
            batch += 1
            if batch >= concurrentDownloadLimit {
                batch = 0
                await processQueue()
            }
        }
        if batch > 0 { await processQueue() }
    }

    /// When watch history gives no next episode (a later episode is marked watched, say), the
    /// episodes from the first unwatched one downloaded here, or after the last one downloaded.
    private func episodesAfterDownloads(seriesId: String, downloaded: [DownloadedItem], count: Int,
                                        credential: ServerCredential, authHeader: String) async -> [MediaItem] {
        guard let all = try? await client.getEpisodes(credential: credential, authHeader: authHeader, seriesId: seriesId, seasonId: nil) else {
            Self.smartLog.error("Smart Downloads: couldn't list episodes for \(seriesId, privacy: .public)")
            return []
        }
        let downloadedIds = Set(downloaded.filter { $0.seriesId == seriesId }.map(\.itemId))
        let positions = all.indices.filter { downloadedIds.contains(all[$0].id) }
        let start = positions.first { all[$0].userData?.played != true } ?? positions.last.map { $0 + 1 } ?? 0
        Self.smartLog.notice("Smart Downloads: \(seriesId, privacy: .public) has \(all.count, privacy: .public) episodes, \(all.filter { $0.userData?.played == true }.count, privacy: .public) watched, downloaded at \(positions.map(String.init).joined(separator: ","), privacy: .public); starting at \(start, privacy: .public)")
        return Array(all.dropFirst(start).filter { $0.userData?.played != true && $0.parentIndexNumber != 0 }.prefix(count))
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
    private func downloadFile(from url: URL, authHeader: String, to destination: URL, itemId: String, run: UUID, allowsParts: Bool) async throws {
        try checkStillWanted(itemId, run: run)
        if allowsParts, try await downloadInParts(from: url, authHeader: authHeader, to: destination, itemId: itemId, run: run) { return }
        try checkStillWanted(itemId, run: run)
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
    private func downloadInParts(from url: URL, authHeader: String, to destination: URL, itemId: String, run: UUID) async throws -> Bool {
        let size = await Self.rangeSupportedSize(of: url, authHeader: authHeader)
        try checkStillWanted(itemId, run: run)
        guard let total = size, total >= Self.minimumSizeForParts else { return false }
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
            var isEstimate = false
            if totalBytesExpectedToWrite <= 0, let estimate = self.estimatedStreamBytes[itemId], estimate > 0 {
                // A guess can come in under the real size; keep it ahead of what's arrived so
                // the bar never claims it's finished before it is.
                totalBytesExpectedToWrite = max(estimate, Int64(Double(totalBytesWritten) * 1.02))
                isEstimate = true
            }
            if totalBytesExpectedToWrite > 0 {
                self.progress[itemId] = min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), isEstimate ? 0.99 : 1)
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
            self.stats[itemId] = DownloadStats(bytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite,
                                               bytesPerSecond: bytesPerSecond, isEstimate: isEstimate)
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
        // An error page (no permission, gone, a failed conversion) arrives as a finished
        // download too; it's left for the system to delete instead of saved as the video.
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status != 200, status != 206 {
            moveError = status == 401 || status == 403 ? DownloadError.permissionDenied : URLError(.badServerResponse)
        } else if let path = downloadTask.taskDescription {
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
            // Orphaned and refused by the server: there's no file to finish it from.
            if capturedMoveError != nil, let capturedPath {
                self.removePendingDescriptor(itemId: URL(fileURLWithPath: capturedPath).deletingLastPathComponent().lastPathComponent)
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

extension DownloadedItem {
    /// The skip markers saved with the download, in the streaming player's shape. A download
    /// from before intro starts were saved treats its intro as starting at the beginning.
    var skipSegments: SkipSegments {
        get {
            func span(_ start: Double?, _ end: Double?) -> ClosedRange<Double>? {
                guard let start, let end else { return nil }
                return start...max(start, end)
            }
            let runtime = runtimeTicks > 0 ? Double(runtimeTicks) / 10_000_000 : .greatestFiniteMagnitude
            return SkipSegments(
                intro: span(introEndSeconds.map { _ in introStartSeconds ?? 0 }, introEndSeconds),
                recap: span(recapStartSeconds, recapEndSeconds),
                credits: span(creditsStartSeconds, creditsEndSeconds ?? creditsStartSeconds.map { _ in runtime }),
                preview: span(previewStartSeconds, previewEndSeconds),
                commercials: (commercialSpans ?? "").split(separator: ",").compactMap { pair in
                    let bounds = pair.split(separator: "-").compactMap { Double($0) }
                    return bounds.count == 2 ? span(bounds[0], bounds[1]) : nil
                }
            )
        }
        set {
            introStartSeconds = newValue.intro?.lowerBound
            introEndSeconds = newValue.intro?.upperBound
            recapStartSeconds = newValue.recap?.lowerBound
            recapEndSeconds = newValue.recap?.upperBound
            creditsStartSeconds = newValue.credits?.lowerBound
            creditsEndSeconds = newValue.credits?.upperBound
            previewStartSeconds = newValue.preview?.lowerBound
            previewEndSeconds = newValue.preview?.upperBound
            commercialSpans = newValue.commercials.isEmpty ? nil
                : newValue.commercials.map { "\($0.lowerBound)-\($0.upperBound)" }.joined(separator: ",")
            skipSegmentsSaved = true
        }
    }
}
