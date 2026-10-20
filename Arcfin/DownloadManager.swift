// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network
import Observation
import SwiftData
import AuthCore
import JellyfinAPI
import LiveActivityKit
import Persistence
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
    @ObservationIgnored private var taskItemIds: [Int: String] = [:]
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
    @ObservationIgnored private var isOnWiFi = true
    @ObservationIgnored private var isRunningSmartDownloads = false
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
        #else
        let config = URLSessionConfiguration.default
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
        startWiFiMonitoringIfNeeded()
        #if canImport(ActivityKit) && os(iOS)
        reconcileStaleActivitiesOnLaunch()
        #endif
        runSmartDownloadsOnLaunch()
        purgeWatchedDownloads()
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
        guard !ids.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingWatchedDeleteKey)
        for id in ids { deleteDownload(itemId: id) }
    }

    private func startWiFiMonitoringIfNeeded() {
        guard wifiPathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let onWiFi = path.usesInterfaceType(.wifi)
            guard let self else { return }
            Task { @MainActor in self.isOnWiFi = onWiFi }
        }
        monitor.start(queue: DispatchQueue(label: "arcfin.downloads.pathMonitor"))
        wifiPathMonitor = monitor
    }

    /// Mirrors reconcileStaleActivitiesOnLaunch's own delay — authManager.checkStoredAuth()
    /// runs concurrently from ContentView's own `.task`, so `authManager.state` isn't
    /// reliably `.authenticated` yet at the moment `configure` itself is called.
    private func runSmartDownloadsOnLaunch() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard let authManager, let credential = authManager.state.credential else { return }
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            await runSmartDownloadsIfNeeded(credential: credential, authHeader: authHeader)
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
        let title = isFinished ? (finishedTitle ?? "") : (itemId.flatMap { activeItemTitles[$0] } ?? "")
        let state = DownloadActivityAttributes.ContentState(
            currentItemTitle: title,
            bytesWritten: stat?.bytesWritten ?? 0, totalBytes: stat?.totalBytes ?? 0,
            bytesPerSecond: stat?.bytesPerSecond ?? 0,
            completedCount: queueCompletedCount, totalCount: queueTotalCount, isFinished: isFinished,
            posterImageData: meta?.posterData, seasonNumber: meta?.season, episodeNumber: meta?.episode
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

    @ObservationIgnored private var pendingQueue: [(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int?)] = []
    @ObservationIgnored private var isProcessingQueue = false

    /// Queues the download — a season's worth of episodes all calling this at once
    /// shouldn't fire a dozen simultaneous video downloads, so only one actually runs at a
    /// time; the rest wait their turn here. `bitrateCap` (bits/sec), when set, forces a
    /// remux even for an otherwise direct-downloadable source — that's the only way to
    /// actually reduce a download's bitrate below the source's own.
    func startDownload(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int? = nil) async {
        guard modelContext != nil, !isDownloaded(item.id), !activeItemIds.contains(item.id),
              !pendingQueue.contains(where: { $0.item.id == item.id })
        else { return }
        let isFreshQueue = activeItemIds.isEmpty && pendingQueue.isEmpty
        activeItemTitles[item.id] = item.name
        pendingQueue.append((item, credential, authHeader, bitrateCap))
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
        await processQueue()
    }

    private func processQueue() async {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        while !pendingQueue.isEmpty {
            let next = pendingQueue.removeFirst()
            guard !isDownloaded(next.item.id) else { continue }
            await performDownload(item: next.item, credential: next.credential, authHeader: next.authHeader, bitrateCap: next.bitrateCap)
        }
        isProcessingQueue = false
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
            async let detailTask = client.getItemDetail(credential: credential, authHeader: authHeader, itemId: item.id)
            async let playbackTask = client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: item.id)
            let detail = try await detailTask
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
            if !skipVideoDownload {
                try await downloadFile(from: videoURL, authHeader: authHeader, to: dir.appendingPathComponent(videoFileName), itemId: item.id)
            }

            // Subtitles — external tracks only (embedded ones travel with the video file itself).
            var subtitleFileNames: [String] = []
            var subtitleLanguages: [String] = []
            for stream in info.subtitleStreams where stream.deliveryUrl != nil {
                guard let deliveryUrl = stream.deliveryUrl,
                      let data = await SubtitleLoader.fetchRawVTTData(deliveryUrl: deliveryUrl, credential: credential)
                else { continue }
                let fileName = "sub-\(stream.index).vtt"
                try? data.write(to: dir.appendingPathComponent(fileName))
                subtitleFileNames.append(fileName)
                subtitleLanguages.append(stream.language ?? stream.displayTitle ?? "Unknown")
            }

            // Trickplay — every tile for the preferred (smallest) width. Array position
            // must equal tileIndex (that's how playback looks tiles up), so a failed tile
            // still gets an empty-string placeholder rather than shifting every index after it.
            var trickplayFileNames: [String] = []
            let trickplay = detail.trickplay[info.mediaSourceId] ?? detail.trickplay.values.first
            if let trickplay, trickplay.tileWidth > 0, trickplay.tileHeight > 0, trickplay.thumbnailCount > 0 {
                let tileCount = Int(ceil(Double(trickplay.thumbnailCount) / Double(trickplay.tileWidth * trickplay.tileHeight)))
                for tileIndex in 0..<max(tileCount, 1) {
                    let tileURL = client.trickplayTileURL(credential: credential, itemId: item.id, width: trickplay.width, tileIndex: tileIndex)
                    var req = URLRequest(url: tileURL)
                    req.setValue(authHeader, forHTTPHeaderField: "Authorization")
                    guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
                          (resp as? HTTPURLResponse)?.statusCode == 200
                    else {
                        trickplayFileNames.append("")
                        continue
                    }
                    let fileName = "tile-\(tileIndex).jpg"
                    try? data.write(to: dir.appendingPathComponent(fileName))
                    trickplayFileNames.append(fileName)
                }
            }

            // Poster / backdrop, for the Downloads list and player UI while offline.
            var posterFileName: String?
            if let tag = detail.item.primaryImageTag {
                let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: item.id, tag: tag, type: .primary, fillWidth: 400, token: credential.accessToken)
                if let (data, _) = try? await URLSession.arcfin.data(from: url) {
                    posterFileName = "poster.jpg"
                    try? data.write(to: dir.appendingPathComponent("poster.jpg"))
                }
            }
            var backdropFileName: String?
            if let tag = detail.item.backdropImageTags.first {
                let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: item.id, tag: tag, type: .backdrop, fillWidth: 800, token: credential.accessToken)
                if let (data, _) = try? await URLSession.arcfin.data(from: url) {
                    backdropFileName = "backdrop.jpg"
                    try? data.write(to: dir.appendingPathComponent("backdrop.jpg"))
                }
            }

            // Skip intro/credits — small, and completes the offline playback feature set.
            var introEnd: Double?
            var creditsStart: Double?
            if detail.item.type == .episode {
                let segments = await client.getSkipSegments(credential: credential, authHeader: authHeader, itemId: item.id)
                introEnd = segments.introEnd
                creditsStart = segments.creditsStart
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(videoFileName).path)[.size] as? Int64) ?? 0

            let downloaded = DownloadedItem(
                itemId: item.id, name: detail.item.name, typeRaw: detail.item.type.rawValue,
                overview: detail.item.overview, runtimeTicks: detail.runTimeTicks ?? 0,
                productionYear: detail.item.productionYear, communityRating: detail.item.communityRating,
                officialRating: detail.officialRating, genres: detail.genres,
                seriesId: detail.item.seriesId, seriesName: detail.item.seriesName,
                seasonNumber: detail.item.parentIndexNumber, episodeNumber: detail.item.indexNumber,
                serverId: credential.id.uuidString, serverBaseURL: credential.baseURL.absoluteString, userId: credential.userID,
                videoFileName: videoFileName, posterFileName: posterFileName, backdropFileName: backdropFileName,
                subtitleFileNames: subtitleFileNames, subtitleLanguages: subtitleLanguages,
                trickplayFileNames: trickplayFileNames,
                trickplayWidth: trickplay?.width, trickplayHeight: trickplay?.height,
                trickplayTileWidth: trickplay?.tileWidth, trickplayTileHeight: trickplay?.tileHeight,
                trickplayIntervalMs: trickplay?.intervalMs, trickplayThumbnailCount: trickplay?.thumbnailCount,
                introEndSeconds: introEnd, creditsStartSeconds: creditsStart,
                fileSizeBytes: fileSize
            )
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
        if pendingQueue.isEmpty {
            endLiveActivity(lastTitle: finishedTitle, lastMeta: finishedMeta)
        } else {
            refreshLiveActivity()
        }
        #endif
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
        guard let detail = try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: seriesId),
              let dir = try? DownloadStore.ensureDirectory(for: seriesId)
        else { return }

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

    func cancelDownload(itemId: String) {
        let wasQueued = pendingQueue.contains(where: { $0.item.id == itemId }) || activeItemIds.contains(itemId)
        pendingQueue.removeAll { $0.item.id == itemId }
        downloadTasks[itemId]?.cancel()
        downloadTasks[itemId] = nil
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

    /// Netflix-style auto-management for shows the user already has downloads/progress in:
    /// tops up the next few unwatched episodes per show and clears out watched ones to make
    /// room, all capped by a hard storage budget. Only wired to run at launch (see
    /// runSmartDownloadsOnLaunch) — deliberately NOT called from performDownload's own
    /// completion path: that would reenter this same queue (pendingQueue/isProcessingQueue)
    /// while its own while-loop is still mid-iteration, so startDownload would just append
    /// and return immediately instead of actually awaiting the download, which would make
    /// the budget check below (totalDownloadedBytes) race against downloads that haven't
    /// happened yet. isRunningSmartDownloads still guards reentrancy generally.
    func runSmartDownloadsIfNeeded(credential: ServerCredential, authHeader: String) async {
        guard let modelContext else { return }
        guard UserDefaults.standard.object(forKey: Self.smartDownloadsEnabledKey) as? Bool ?? false else { return }
        let wifiOnly = UserDefaults.standard.object(forKey: "wifiOnly") as? Bool ?? true
        guard !wifiOnly || isOnWiFi else { return }
        guard !isRunningSmartDownloads else { return }
        isRunningSmartDownloads = true
        defer { isRunningSmartDownloads = false }

        let episodeCount = max(1, min(5, UserDefaults.standard.object(forKey: Self.smartDownloadsEpisodeCountKey) as? Int ?? 2))
        let budgetGB = UserDefaults.standard.object(forKey: Self.smartDownloadsStorageBudgetGBKey) as? Int ?? 10
        let budgetBytes = Int64(budgetGB) * 1_000_000_000

        let allDownloaded = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>())) ?? []
        let seriesIds = Set(allDownloaded.compactMap { $0.seriesId })
        guard !seriesIds.isEmpty else { return }

        // Clear fully watched episodes first, freeing space for whatever's next up.
        for item in allDownloaded where item.seriesId != nil && item.played {
            deleteDownload(item)
        }

        func totalDownloadedBytes() -> Int64 {
            let current = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>())) ?? []
            return current.reduce(0) { $0 + $1.fileSizeBytes }
        }

        for seriesId in seriesIds {
            guard let nextUp = try? await client.getNextUp(credential: credential, authHeader: authHeader, seriesId: seriesId, limit: episodeCount) else { continue }
            for episode in nextUp {
                guard !isDownloaded(episode.id), !activeItemIds.contains(episode.id) else { continue }
                guard totalDownloadedBytes() < budgetBytes else { return }
                await startDownload(item: episode, credential: credential, authHeader: authHeader)
            }
        }
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
    private func downloadFile(from url: URL, authHeader: String, to destination: URL, itemId: String) async throws {
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
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let taskId = downloadTask.taskIdentifier
        let now = Date()
        Task { @MainActor in
            guard let itemId = self.taskItemIds[taskId] else { return }
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
            // No continuation means this app instance didn't originate the transfer — most
            // likely relaunched specifically to receive this exact redelivered event. The
            // file's already safely moved above; finish the rest of the pipeline for it.
            if capturedMoveError == nil, let capturedPath {
                await self.recoverOrphanedDownload(destinationPath: capturedPath)
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
