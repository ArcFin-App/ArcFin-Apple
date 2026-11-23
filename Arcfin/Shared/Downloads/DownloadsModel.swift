// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Persistence
import JellyfinAPI

/// Navigation payload for a series container row — a thin wrapper instead of a bare String
/// so `.navigationDestination(for:)` can dispatch to the series detail view specifically,
/// without colliding with any other String-based destination elsewhere in the app.
struct DownloadedSeriesRef: Hashable {
    let seriesId: String
}

/// What Downloads has picked, open and asked to confirm, shared by every platform's `DownloadsView`.
@MainActor @Observable
final class DownloadsModel {
    var pendingDelete: DownloadedItem?
    /// A title Smart Downloads fetched, waiting for Cancel or Cancel & Ignore.
    var pendingSmartCancel: String?
    var pendingDeleteSeriesId: String?
    // Owned here rather than relying on an ancestor's navigationDestination(for:) — this
    // view is itself pushed non-root (Library's Downloads row, offline mode's stack), and a
    // NavigationLink(value:) pushed from a nested view can silently fail to resolve against
    // a destination declared further up the stack (see the See All fix, 306aaf3).
    var selectedItem: DownloadedItem?
    var selectedSeriesRef: DownloadedSeriesRef?
    var selectedMedia: MediaItem?
    var playingItem: DownloadedItem?
    var isSelecting = false
    var selection = Set<String>()
    var showBulkDeleteConfirm = false
    var showMobileDataConfirm = false
    var showCancelAllConfirm = false
    var freeBytes: Int64?

    struct SeriesGroup {
        let seriesId: String
        let seriesName: String
        let episodes: [DownloadedItem]
    }

    static func movies(in items: [DownloadedItem]) -> [DownloadedItem] {
        items.filter { $0.seriesId == nil }.sorted { $0.name < $1.name }
    }

    static func seriesGroups(in items: [DownloadedItem]) -> [SeriesGroup] {
        let grouped = Dictionary(grouping: items.filter { $0.seriesId != nil }) { $0.seriesId! }
        return grouped.map { (id, episodes) in
            SeriesGroup(seriesId: id, seriesName: episodes.first?.seriesName ?? String(localized: "Unknown Series"),
                        episodes: episodes.sorted { ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) < ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0) })
        }.sorted { $0.seriesName < $1.seriesName }
    }

    static func inProgress(in items: [DownloadedItem]) -> [DownloadedItem] {
        items.filter { $0.playbackPositionTicks > 0 && !$0.played }
    }

    /// Each downloaded show's next episode, for one with nothing part-way through: the first
    /// unwatched one downloaded, specials last.
    static func upNext(in items: [DownloadedItem]) -> [DownloadedItem] {
        Dictionary(grouping: items.filter { $0.seriesId != nil }) { $0.seriesId! }.values.compactMap { episodes in
            guard !episodes.contains(where: { $0.playbackPositionTicks > 0 && !$0.played }) else { return nil }
            return episodes.filter { !$0.played }.min {
                let a = ($0.seasonNumber == 0 ? Int.max : $0.seasonNumber ?? 0, $0.episodeNumber ?? 0)
                let b = ($1.seasonNumber == 0 ? Int.max : $1.seasonNumber ?? 0, $1.episodeNumber ?? 0)
                return a < b
            }
        }
        .sorted { ($0.seriesName ?? $0.name) < ($1.seriesName ?? $1.name) }
    }

    static func totalSizeBytes(of items: [DownloadedItem]) -> Int64 { items.reduce(0) { $0 + $1.fileSizeBytes } }

    func deleteSelection(in items: [DownloadedItem], downloadManager: DownloadManager) {
        var toDelete: [DownloadedItem] = []
        for id in selection {
            if id.hasPrefix("series:") {
                let seriesId = String(id.dropFirst("series:".count))
                toDelete.append(contentsOf: items.filter { $0.seriesId == seriesId })
            } else if id.hasPrefix("movie:") {
                let itemId = String(id.dropFirst("movie:".count))
                if let item = items.first(where: { $0.itemId == itemId }) { toDelete.append(item) }
            }
        }
        downloadManager.deleteDownloads(toDelete)
        selection.removeAll()
        isSelecting = false
    }

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    // MARK: - Navigation

    /// With a connection, a download opens the title's full page; offline, the saved one.
    func open(_ item: DownloadedItem, isOnline: Bool, downloadManager: DownloadManager) {
        if isOnline {
            selectedMedia = downloadManager.savedDetail(itemId: item.itemId)?.item ?? Self.mediaItem(for: item)
        } else {
            selectedItem = item
        }
    }

    func openSeries(_ seriesId: String, name: String, isOnline: Bool, downloadManager: DownloadManager) {
        if isOnline {
            selectedMedia = downloadManager.savedDetail(itemId: seriesId)?.item
                ?? MediaItem(id: seriesId, name: name, type: .series)
        } else {
            selectedSeriesRef = DownloadedSeriesRef(seriesId: seriesId)
        }
    }

    private static func mediaItem(for item: DownloadedItem) -> MediaItem {
        MediaItem(
            id: item.itemId, name: item.name, overview: item.overview,
            type: MediaType(rawValue: item.typeRaw) ?? .movie,
            productionYear: item.productionYear, communityRating: item.communityRating,
            seriesName: item.seriesName, indexNumber: item.episodeNumber,
            parentIndexNumber: item.seasonNumber, seriesId: item.seriesId
        )
    }

    // MARK: - Storage

    func refreshFreeBytes() {
        freeBytes = StorageManagement.freeBytes()
    }

    // MARK: - Artwork

    static func fileURL(_ name: String?, of item: DownloadedItem) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return DownloadStore.directory(for: item).appendingPathComponent(name)
    }

    static func seriesPosterURL(_ seriesId: String, fallback: DownloadedItem?) -> URL? {
        let poster = DownloadStore.directory(for: seriesId).appendingPathComponent("poster.jpg")
        if FileManager.default.fileExists(atPath: poster.path) { return poster }
        return fallback.flatMap { fileURL($0.posterFileName, of: $0) }
    }
}
