// SPDX-License-Identifier: AGPL-3.0-or-later

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
        /// The transfer is suspended (Pause in Downloads).
        public var isPaused: Bool?
        /// The next title waiting in the queue, if any.
        public var nextItemTitle: String?
        /// The current title's progress as a span of time at the last known speed, so the
        /// bar and countdown keep moving while iOS has the app suspended and it can't update.
        public var estimateStart: Date?
        public var estimatedFinish: Date?
        /// Held because Wi-Fi Only is on and the connection is mobile data.
        public var isWaitingForWiFi: Bool?

        public init(
            currentItemTitle: String, bytesWritten: Int64, totalBytes: Int64, bytesPerSecond: Double,
            completedCount: Int, totalCount: Int, isFinished: Bool = false,
            posterImageData: Data? = nil, seasonNumber: Int? = nil, episodeNumber: Int? = nil,
            isPaused: Bool = false, nextItemTitle: String? = nil,
            estimateStart: Date? = nil, estimatedFinish: Date? = nil,
            isWaitingForWiFi: Bool = false
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
            self.isPaused = isPaused
            self.nextItemTitle = nextItemTitle
            self.estimateStart = estimateStart
            self.estimatedFinish = estimatedFinish
            self.isWaitingForWiFi = isWaitingForWiFi
        }

        /// The estimated span, when the transfer is moving.
        public var estimate: ClosedRange<Date>? {
            guard isPaused != true, !isFinished, let estimateStart, let estimatedFinish, estimateStart < estimatedFinish
            else { return nil }
            return estimateStart...estimatedFinish
        }

        /// Seconds left on the current title at the present speed, when it's moving.
        public var secondsRemaining: Double? {
            guard bytesPerSecond > 0, totalBytes > bytesWritten, isPaused != true else { return nil }
            return Double(totalBytes - bytesWritten) / bytesPerSecond
        }

        /// The title being downloaded now, counting from one.
        public var position: Int { min(completedCount + (isFinished ? 0 : 1), max(totalCount, 1)) }

        public var fractionComplete: Double {
            guard totalBytes > 0 else { return 0 }
            return min(max(Double(bytesWritten) / Double(totalBytes), 0), 1)
        }

        public var episodeLabel: String? {
            guard let seasonNumber else { return nil }
            let s = "S\(seasonNumber)"
            let e = episodeNumber.map { " E\($0)" } ?? ""
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
