// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

#if os(iOS)
import ActivityKit

/// What another device plays while this iPhone is its remote (#457), on the Lock Screen and
/// in the Dynamic Island. One activity per device: switching device ends it and starts another.
public struct RemotePlaybackActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var title: String
        public var subtitle: String?
        public var deviceName: String
        public var isPaused: Bool
        public var positionSeconds: Double
        public var durationSeconds: Double
        /// When the position was read, so the bar keeps moving while the app is suspended.
        public var updatedAt: Date
        /// A tiny JPEG: the content state has to stay within ActivityKit's payload limit.
        public var artwork: Data?

        public init(title: String, subtitle: String?, deviceName: String, isPaused: Bool,
                    positionSeconds: Double, durationSeconds: Double, updatedAt: Date, artwork: Data?) {
            self.title = title
            self.subtitle = subtitle
            self.deviceName = deviceName
            self.isPaused = isPaused
            self.positionSeconds = positionSeconds
            self.durationSeconds = durationSeconds
            self.updatedAt = updatedAt
            self.artwork = artwork
        }

        /// From the start to the end of the title, while it plays.
        public var playbackSpan: ClosedRange<Date>? {
            guard !isPaused, durationSeconds > 0, positionSeconds < durationSeconds else { return nil }
            let start = updatedAt.addingTimeInterval(-positionSeconds)
            return start...start.addingTimeInterval(durationSeconds)
        }

        public var fraction: Double {
            guard durationSeconds > 0 else { return 0 }
            return min(max(positionSeconds / durationSeconds, 0), 1)
        }
    }

    public var sessionID: String

    public init(sessionID: String) {
        self.sessionID = sessionID
    }
}
#endif
