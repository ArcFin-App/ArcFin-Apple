import Foundation
import Observation
import SwiftData
import AuthCore
import JellyfinAPI
import Persistence

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

@MainActor
@Observable
final class DownloadManager: NSObject {

    private(set) var progress: [String: Double] = [:]
    private(set) var activeItemIds: Set<String> = []
    /// Keyed by itemId — a shared single error string would show the wrong download's
    /// failure on an unrelated DownloadButton if more than one item is downloading at once.
    var errors: [String: String] = [:]

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private let client = JellyfinMediaClient()
    @ObservationIgnored private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var taskItemIds: [Int: String] = [:]
    @ObservationIgnored private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func isDownloaded(_ itemId: String) -> Bool {
        guard let modelContext else { return false }
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    // MARK: - Start download

    func startDownload(item: MediaItem, credential: ServerCredential, authHeader: String) async {
        guard let modelContext, !isDownloaded(item.id), !activeItemIds.contains(item.id) else { return }
        activeItemIds.insert(item.id)
        progress[item.id] = 0

        do {
            async let detailTask = client.getItemDetail(credential: credential, authHeader: authHeader, itemId: item.id)
            async let playbackTask = client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: item.id)
            let detail = try await detailTask
            let info = try await playbackTask

            let dir = try DownloadStore.ensureDirectory(for: item.id)

            // Video — the original file, not a transcode. Progress-tracked via the
            // delegate below since this is the one file large enough to matter.
            // info.container reflects the source's real container regardless of play
            // method — info.playURL's extension would be wrong for a transcode-eligible
            // item (e.g. ".../master.m3u8"), which doesn't describe the original file
            // this endpoint actually returns.
            let ext = info.container?.nilIfEmpty ?? "mp4"
            let videoFileName = "video.\(ext)"
            let videoURL = JellyfinMediaClient.originalFileDownloadURL(
                baseURL: credential.baseURL, itemID: item.id, token: credential.accessToken)
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
        progress[item.id] = nil
    }

    func cancelDownload(itemId: String) {
        downloadTasks[itemId]?.cancel()
        downloadTasks[itemId] = nil
        activeItemIds.remove(itemId)
        progress[itemId] = nil
        DownloadStore.deleteDirectory(for: itemId)
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
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let itemId = self.taskItemIds[taskId] else { return }
            self.progress[itemId] = fraction
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
}
