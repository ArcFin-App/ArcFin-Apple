// SPDX-License-Identifier: AGPL-3.0-or-later

import ActivityKit
import Foundation
import JellyfinAPI
import LiveActivityKit
import UIKit

/// The music download queue on the Lock Screen and in the Dynamic Island, the same way video
/// downloads show: one activity for the whole queue.
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

    private static var activity: Activity<DownloadActivityAttributes>?
    private static var cover: (albumID: String?, data: Data?)?

    static func update(_ snapshot: Snapshot) {
        let albumID = snapshot.albumID
        if cover == nil || cover?.albumID != albumID {
            cover = (albumID, nil)
            Task {
                let data = await coverData(snapshot.coverURL)
                guard cover?.albumID == albumID else { return }
                cover = (albumID, data)
                update(snapshot)
            }
        }
        let state = state(for: snapshot)
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = Activity<DownloadActivityAttributes>.activities.first { $0.content.state.isMusic == true }
                ?? (try? Activity.request(attributes: DownloadActivityAttributes(),
                                          content: ActivityContent(state: state, staleDate: nil)))
        }
    }

    /// Shows the queue as done for a few seconds, then goes.
    static func finish(count: Int) {
        guard let activity else { return }
        self.activity = nil
        cover = nil
        let state = DownloadActivityAttributes.ContentState(
            currentItemTitle: "", bytesWritten: 0, totalBytes: 0, bytesPerSecond: 0,
            completedCount: count, totalCount: count, isFinished: true, isMusic: true)
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: .after(.now.addingTimeInterval(8)))
        }
    }

    static func end() {
        guard let activity else { return }
        self.activity = nil
        cover = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// One left from before the app was closed, with nothing left to download.
    static func endStale() {
        for stale in Activity<DownloadActivityAttributes>.activities where stale.content.state.isMusic == true {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static func state(for snapshot: Snapshot) -> DownloadActivityAttributes.ContentState {
        // Spread the song over time at the present speed, so the bar keeps moving while the
        // app is suspended.
        var estimate: (start: Date, finish: Date)?
        if snapshot.bytesPerSecond > 0, snapshot.total > snapshot.written {
            let remaining = Double(snapshot.total - snapshot.written) / snapshot.bytesPerSecond
            let fraction = Double(snapshot.written) / Double(snapshot.total)
            estimate = (.now.addingTimeInterval(-remaining / (1 - fraction) * fraction), .now.addingTimeInterval(remaining))
        }
        return DownloadActivityAttributes.ContentState(
            currentItemTitle: snapshot.artist.map { "\(snapshot.title) · \($0)" } ?? snapshot.title,
            bytesWritten: snapshot.written, totalBytes: snapshot.total, bytesPerSecond: snapshot.bytesPerSecond,
            completedCount: snapshot.saved, totalCount: snapshot.count,
            posterImageData: cover?.data, nextItemTitle: snapshot.next,
            estimateStart: estimate?.start, estimatedFinish: estimate?.finish,
            isWaitingForWiFi: snapshot.waitingForWiFi, isMusic: true, isWaitingForNetwork: snapshot.waitingForNetwork)
    }

    /// A small JPEG: it rides along in the activity's state, which has a size limit.
    private static func coverData(_ url: URL?) async -> Data? {
        let data: Data? = if let url, url.isFileURL {
            try? Data(contentsOf: url)
        } else if let url {
            await URLSession.arcfin.imageData(from: url)
        } else {
            nil
        }
        guard let data, let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 120
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return small.jpegData(compressionQuality: 0.7)
    }
}
