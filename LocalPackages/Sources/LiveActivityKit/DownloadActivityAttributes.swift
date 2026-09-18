import Foundation

// canImport(ActivityKit) alone isn't enough to gate this — the module itself is importable
// on macOS (for Mac-mirroring purposes), but ActivityAttributes/starting an Activity is
// iOS-only, so this needs an explicit os(iOS) check instead.
#if os(iOS)
import ActivityKit

/// One Live Activity represents the whole download queue, not one per item — the HIG's own
/// guidance is to let people track multiple related events through a single Live Activity
/// rather than one they have to juggle per download.
public struct DownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var currentItemTitle: String
        public var bytesWritten: Int64
        public var totalBytes: Int64
        public var bytesPerSecond: Double
        /// Items already finished in this queue run, and the total queued when it started —
        /// drives "2 of 6" style progress independent of the current item's own byte progress.
        public var completedCount: Int
        public var totalCount: Int
        public var isFinished: Bool
        /// Small (≈120px) JPEG thumbnail — no App Group is set up to share a file path with
        /// the widget extension, so this rides along in the content state itself instead.
        /// Kept intentionally tiny to stay well clear of ActivityKit's payload limits.
        public var posterImageData: Data?
        public var seasonNumber: Int?
        public var episodeNumber: Int?

        public init(
            currentItemTitle: String, bytesWritten: Int64, totalBytes: Int64, bytesPerSecond: Double,
            completedCount: Int, totalCount: Int, isFinished: Bool = false,
            posterImageData: Data? = nil, seasonNumber: Int? = nil, episodeNumber: Int? = nil
        ) {
            self.currentItemTitle = currentItemTitle
            self.bytesWritten = bytesWritten
            self.totalBytes = totalBytes
            self.bytesPerSecond = bytesPerSecond
            self.completedCount = completedCount
            self.totalCount = totalCount
            self.isFinished = isFinished
            self.posterImageData = posterImageData
            self.seasonNumber = seasonNumber
            self.episodeNumber = episodeNumber
        }

        public var fractionComplete: Double {
            guard totalBytes > 0 else { return 0 }
            return min(max(Double(bytesWritten) / Double(totalBytes), 0), 1)
        }

        public var episodeLabel: String? {
            guard let seasonNumber else { return nil }
            let s = "S\(seasonNumber)"
            let e = episodeNumber.map { "E\($0)" } ?? ""
            return s + e
        }
    }

    /// Static for the life of the Activity — the queue's own name/count doesn't change,
    /// only ContentState updates as items complete.
    public var startedAt: Date

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }
}
#endif
