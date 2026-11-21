// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Music downloads on a background session: the system carries them on while the app is
/// suspended, and hands back the ones that finished meanwhile when it's running again.
nonisolated final class MusicTransfers: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.psmattas.arcfin.music"
    static let shared = MusicTransfers()
    /// From the app delegate, when the system woke the app to hand over finished songs.
    nonisolated(unsafe) static var pendingCompletionHandler: (() -> Void)?

    struct Finished: Sendable {
        let songID: String
        /// The downloaded file, moved out of the system's hands; nil when it failed.
        let file: URL?
        let fileExtension: String
        let status: Int
        let error: URLError?
    }

    private let lock = NSLock()
    private var waiting: [String: CheckedContinuation<Finished, Never>] = [:]
    private var progress: [String: @Sendable (Int64, Int64) -> Void] = [:]
    private var landed: [Int: (file: URL, status: Int)] = [:]
    /// Finished with nothing waiting for it: handed over in the background, or from before a
    /// relaunch.
    private var unclaimed: (@Sendable (Finished) -> Void)?
    /// Handed over before `connect` set where they go.
    private var early: [Finished] = []

    private var session: URLSession!

    override private init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Where songs that finished with nothing waiting for them go. Set at launch, before the
    /// session hands any over.
    func connect(unclaimed handler: @escaping @Sendable (Finished) -> Void) {
        let early = lock.withLock {
            unclaimed = handler
            defer { self.early = [] }
            return self.early
        }
        early.forEach(handler)
    }

    /// Downloads a song, or picks up its transfer if one is already running.
    func download(_ request: URLRequest, songID: String, resumeData: Data?,
                  progress report: @escaping @Sendable (Int64, Int64) -> Void) async -> Finished {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    waiting[songID] = continuation
                    progress[songID] = report
                }
                start(request, songID: songID, resumeData: resumeData)
            }
        } onCancel: {
            session.getAllTasks { tasks in
                for task in tasks where task.taskDescription == songID { task.cancel() }
            }
        }
    }

    /// Starts a song without waiting for it: the rest of the queue, as the app leaves the
    /// foreground.
    func handOff(_ request: URLRequest, songID: String) {
        start(request, songID: songID, resumeData: nil)
    }

    private func start(_ request: URLRequest, songID: String, resumeData: Data?) {
        session.getAllTasks { [self] tasks in
            if tasks.contains(where: { $0.taskDescription == songID && $0.state == .running }) { return }
            let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: request)
            task.taskDescription = songID
            task.resume()
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes its file once this returns.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("music-\(UUID().uuidString)")
        guard (try? FileManager.default.moveItem(at: location, to: kept)) != nil else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        lock.withLock { landed[downloadTask.taskIdentifier] = (kept, status) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let songID = downloadTask.taskDescription else { return }
        let report = lock.withLock { progress[songID] }
        report?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let songID = task.taskDescription else { return }
        let (file, continuation, unclaimed) = lock.withLock {
            progress[songID] = nil
            return (landed.removeValue(forKey: task.taskIdentifier), waiting.removeValue(forKey: songID), self.unclaimed)
        }
        let status = file?.status ?? (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let finished = Finished(songID: songID, file: file?.file,
                                fileExtension: task.originalRequest?.url?.pathExtension ?? "mp3", status: status,
                                error: file == nil ? (error as? URLError ?? URLError(.unknown)) : nil)
        if let continuation {
            continuation.resume(returning: finished)
        } else if let unclaimed {
            unclaimed(finished)
        } else {
            lock.withLock { early.append(finished) }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            Self.pendingCompletionHandler?()
            Self.pendingCompletionHandler = nil
        }
    }
}
