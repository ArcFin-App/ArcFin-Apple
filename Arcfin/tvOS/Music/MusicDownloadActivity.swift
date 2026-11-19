// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Apple TV has no Live Activities.
@MainActor
enum MusicDownloadActivity {
    struct Snapshot {
        var title: String
        var artist: String?
        var next: String?
        var written: Int64
        var total: Int64
        var bytesPerSecond: Double
        var saved: Int
        var count: Int
        var waitingForWiFi: Bool
        var waitingForNetwork: Bool
        var coverURL: URL?
        var albumID: String?
    }

    static func update(_ snapshot: Snapshot) {}
    static func finish(count: Int) {}
    static func end() {}
    static func endStale() {}
}
