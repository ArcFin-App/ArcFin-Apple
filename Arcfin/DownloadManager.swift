import Foundation
import Observation
import SwiftData
import AuthCore
import JellyfinAPI
import Persistence
#if canImport(UIKit) && !os(tvOS)
import UIKit
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
    @ObservationIgnored private let client = JellyfinMediaClient()
    @ObservationIgnored private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var taskItemIds: [Int: String] = [:]
    @ObservationIgnored private var speedSamples: [String: (time: Date, bytes: Int64)] = [:]
    #if canImport(UIKit) && !os(tvOS)
    @ObservationIgnored private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    #endif
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

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        var estimatedSizeBytes: Int64?
        var willRemux: Bool
        /// Source's own bitrate (bits/sec), when the server reports it — the ceiling for
        /// any bitrate the confirm sheet lets the user pick (no point offering to "upscale").
        var sourceBitrate: Int?
        var runtimeTicks: Int64?
    }

    /// What the confirmation sheet shows before actually starting — same PlaybackInfo call
    /// the real download makes, plus a HEAD request against the resolved video URL for its
    /// size (Content-Length), without downloading anything yet.
    func preview(for item: MediaItem, credential: ServerCredential, authHeader: String) async -> DownloadPreview? {
        guard let info = try? await client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: item.id) else {
            return nil
        }
        let needsRemux = JellyfinMediaClient.downloadNeedsRemux(container: info.container, videoCodec: info.videoStream?.codec)
        let videoURL = needsRemux
            ? JellyfinMediaClient.remuxDownloadURL(baseURL: credential.baseURL, itemID: item.id, mediaSourceId: info.mediaSourceId, videoBitRate: max(info.bitrate ?? 20_000_000, 4_000_000), token: credential.accessToken)
            : JellyfinMediaClient.originalFileDownloadURL(baseURL: credential.baseURL, itemID: item.id, token: credential.accessToken)

        var headReq = URLRequest(url: videoURL)
        headReq.httpMethod = "HEAD"
        headReq.setValue(authHeader, forHTTPHeaderField: "Authorization")
        headReq.timeoutInterval = 10
        var estimatedSize: Int64?
        if let (_, response) = try? await URLSession.shared.data(for: headReq),
           let http = response as? HTTPURLResponse, http.expectedContentLength > 0 {
            estimatedSize = http.expectedContentLength
        }

        let languages = info.subtitleStreams.compactMap { $0.deliveryUrl != nil ? ($0.language ?? $0.displayTitle ?? "Unknown") : nil }
        return DownloadPreview(subtitleLanguages: languages, estimatedSizeBytes: estimatedSize, willRemux: needsRemux,
                                sourceBitrate: info.bitrate, runtimeTicks: info.runTimeTicks)
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
        activeItemTitles[item.id] = item.name
        pendingQueue.append((item, credential, authHeader, bitrateCap))
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

    private func performDownload(item: MediaItem, credential: ServerCredential, authHeader: String, bitrateCap: Int?) async {
        guard let modelContext else { return }
        activeItemIds.insert(item.id)
        progress[item.id] = 0
        beginBackgroundTaskIfNeeded()

        do {
            async let detailTask = client.getItemDetail(credential: credential, authHeader: authHeader, itemId: item.id)
            async let playbackTask = client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: item.id)
            let detail = try await detailTask
            let info = try await playbackTask

            let dir = try DownloadStore.ensureDirectory(for: item.id)

            // Video — the original file when its container is one AVFoundation can actually
            // open, its video codec isn't HEVC, and the user didn't ask for a lower bitrate;
            // otherwise a remux download instead. HEVC sources are routinely tagged hev1
            // rather than the hvc1 tag AVFoundation requires (plays audio with a black
            // screen), and a raw file download has no way to fix that server-side tag —
            // only forcing h264 output sidesteps it. A bitrateCap forces the same remux
            // path since that's the only way to actually shrink a download below source.
            let sourceContainer = (info.container ?? "").lowercased()
            let needsRemux = JellyfinMediaClient.downloadNeedsRemux(container: info.container, videoCodec: info.videoStream?.codec) || bitrateCap != nil
            let videoFileName = needsRemux ? "video.mp4" : "video.\(sourceContainer.nilIfEmpty ?? "mp4")"
            // A user-picked cap is respected as-is (that's the point of picking "Low"); an
            // unrequested remux (bad container/HEVC tag) instead floors at 4 Mbps so a
            // missing/garbage source bitrate doesn't silently tank quality nobody asked to reduce.
            let remuxBitrate = bitrateCap.map { cap in info.bitrate.map { min(cap, $0) } ?? cap } ?? max(info.bitrate ?? 20_000_000, 4_000_000)
            let videoURL = needsRemux
                ? JellyfinMediaClient.remuxDownloadURL(baseURL: credential.baseURL, itemID: item.id, mediaSourceId: info.mediaSourceId, videoBitRate: remuxBitrate, token: credential.accessToken)
                : JellyfinMediaClient.originalFileDownloadURL(baseURL: credential.baseURL, itemID: item.id, token: credential.accessToken)
            try await downloadFile(from: videoURL, authHeader: authHeader, to: dir.appendingPathComponent(videoFileName), itemId: item.id)

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
                    guard let (data, resp) = try? await URLSession.shared.data(for: req),
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
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    posterFileName = "poster.jpg"
                    try? data.write(to: dir.appendingPathComponent("poster.jpg"))
                }
            }
            var backdropFileName: String?
            if let tag = detail.item.backdropImageTags.first {
                let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: item.id, tag: tag, type: .backdrop, fillWidth: 800, token: credential.accessToken)
                if let (data, _) = try? await URLSession.shared.data(from: url) {
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
                fileSizeBytes: fileSize ?? 0
            )
            modelContext.insert(downloaded)
            try? modelContext.save()
        } catch {
            errors[item.id] = (error as? DownloadError)?.errorDescription ?? "Download failed: \(error.localizedDescription)"
            DownloadStore.deleteDirectory(for: item.id)
        }

        activeItemIds.remove(item.id)
        activeItemTitles[item.id] = nil
        progress[item.id] = nil
        stats[item.id] = nil
        speedSamples[item.id] = nil
        endBackgroundTaskIfIdle()
    }

    func cancelDownload(itemId: String) {
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
    }

    // MARK: - Background continuation

    /// Not a true background URLSession (that needs app-delegate wiring to reconnect a
    /// completion handler after relaunch) — this just asks iOS for extra runtime so a
    /// download in flight has a real chance to finish if the user backgrounds the app
    /// mid-download, rather than being killed within seconds.
    private func beginBackgroundTaskIfNeeded() {
        #if canImport(UIKit) && !os(tvOS)
        guard backgroundTaskId == .invalid else { return }
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "ArcfinDownload") { [weak self] in
            Task { @MainActor in self?.endBackgroundTaskIfIdle(force: true) }
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
        DownloadStore.deleteDirectory(for: item.itemId)
        modelContext.delete(item)
        try? modelContext.save()
    }

    func deleteDownload(itemId: String) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        deleteDownload(item)
    }

    // MARK: - Video download with progress

    private func downloadFile(from url: URL, authHeader: String, to destination: URL, itemId: String) async throws {
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60 * 60

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = session.downloadTask(with: req)
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
            if let last = self.speedSamples[itemId], now.timeIntervalSince(last.time) >= 0.5 {
                let elapsed = now.timeIntervalSince(last.time)
                bytesPerSecond = elapsed > 0 ? Double(totalBytesWritten - last.bytes) / elapsed : 0
                self.speedSamples[itemId] = (now, totalBytesWritten)
            } else if self.speedSamples[itemId] == nil {
                self.speedSamples[itemId] = (now, totalBytesWritten)
                bytesPerSecond = self.stats[itemId]?.bytesPerSecond ?? 0
            } else {
                bytesPerSecond = self.stats[itemId]?.bytesPerSecond ?? 0
            }
            self.stats[itemId] = DownloadStats(bytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite, bytesPerSecond: bytesPerSecond)
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
        Task { @MainActor in
            guard let continuation = self.continuations[taskId] else { return }
            self.continuations[taskId] = nil
            if let moveError { continuation.resume(throwing: moveError) } else { continuation.resume() }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        let taskId = task.taskIdentifier
        Task { @MainActor in
            guard let continuation = self.continuations[taskId] else { return }
            self.continuations[taskId] = nil
            continuation.resume(throwing: error)
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
