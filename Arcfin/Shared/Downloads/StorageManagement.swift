// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence

/// Manage Storage's list, largest first, and what's picked or about to be deleted, shared by
/// the iPhone, iPad and Mac `StorageManagementView`.
@MainActor @Observable
final class StorageManagementModel {
    var selection = Set<String>()
    var showBulkDeleteConfirm = false
    var pendingDeleteMovie: DownloadedItem?
    var pendingDeleteSeriesId: String?

    struct StorageEntry: Identifiable {
        let id: String
        let name: String
        let subtitle: String
        let sizeBytes: Int64
        let movie: DownloadedItem?
        let seriesId: String?
        let seriesEpisodes: [DownloadedItem]
    }

    // fileSizeBytes only covers each item's video file (not subtitles/trickplay/poster),
    // same as DownloadsView's own totalSizeBytes — kept consistent with what that list
    // already shows rather than re-walking the filesystem for a slightly larger number.
    static func entries(of items: [DownloadedItem]) -> [StorageEntry] {
        let movies = items.filter { $0.seriesId == nil }.map { item in
            StorageEntry(id: "movie:\(item.itemId)", name: item.name, subtitle: "Movie",
                         sizeBytes: item.fileSizeBytes, movie: item, seriesId: nil, seriesEpisodes: [])
        }
        let grouped = Dictionary(grouping: items.filter { $0.seriesId != nil }) { $0.seriesId! }
        let series = grouped.map { (seriesId, episodes) -> StorageEntry in
            StorageEntry(
                id: "series:\(seriesId)", name: episodes.first?.seriesName ?? "Unknown Series",
                subtitle: "\(episodes.count) episode\(episodes.count == 1 ? "" : "s")",
                sizeBytes: episodes.reduce(0) { $0 + $1.fileSizeBytes },
                movie: nil, seriesId: seriesId, seriesEpisodes: episodes
            )
        }
        return (movies + series).sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func totalSizeBytes(of items: [DownloadedItem]) -> Int64 { items.reduce(0) { $0 + $1.fileSizeBytes } }

    func deleteSelection(of entries: [StorageEntry], downloadManager: DownloadManager) {
        var toDelete: [DownloadedItem] = []
        for id in selection {
            guard let entry = entries.first(where: { $0.id == id }) else { continue }
            if let movie = entry.movie {
                toDelete.append(movie)
            } else {
                toDelete.append(contentsOf: entry.seriesEpisodes)
            }
        }
        downloadManager.deleteDownloads(toDelete)
        selection.removeAll()
    }

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func askToDelete(_ entry: StorageEntry) {
        if let movie = entry.movie {
            pendingDeleteMovie = movie
        } else {
            pendingDeleteSeriesId = entry.seriesId
        }
    }
}

/// A title or show in Manage Storage, with its size.
struct StorageEntryRowContent: View {
    let entry: StorageManagementModel.StorageEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// The check beside a title or show while picking several.
struct StorageEntrySelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(.title3))
            .foregroundStyle(isSelected ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
            .accessibilityHidden(true)
    }
}

/// Manage Storage's confirmations: deleting a title, a show or the selection.
struct StorageManagementAlerts: ViewModifier {
    let items: [DownloadedItem]
    @Bindable var model: StorageManagementModel
    let onBulkDelete: () -> Void

    @Environment(DownloadManager.self) private var downloadManager

    func body(content: Content) -> some View {
        content
            .alert("Delete this download?", isPresented: Binding(
                get: { model.pendingDeleteMovie != nil }, set: { if !$0 { model.pendingDeleteMovie = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let pendingDeleteMovie = model.pendingDeleteMovie { downloadManager.deleteDownload(pendingDeleteMovie) }
                    model.pendingDeleteMovie = nil
                }
                if let pendingDeleteMovie = model.pendingDeleteMovie, downloadManager.smartIgnoreTarget(itemId: pendingDeleteMovie.itemId) != nil {
                    Button("Delete & Ignore in Smart Downloads", role: .destructive) {
                        downloadManager.deleteAndIgnore(itemIds: [pendingDeleteMovie.itemId])
                        model.pendingDeleteMovie = nil
                    }
                }
                Button("Cancel", role: .cancel) { model.pendingDeleteMovie = nil }
            }
            .alert("Delete this show's downloads?", isPresented: Binding(
                get: { model.pendingDeleteSeriesId != nil }, set: { if !$0 { model.pendingDeleteSeriesId = nil } }
            )) {
                Button("Delete All Episodes", role: .destructive) {
                    if let seriesId = model.pendingDeleteSeriesId {
                        downloadManager.deleteDownloads(items.filter { $0.seriesId == seriesId })
                    }
                    model.pendingDeleteSeriesId = nil
                }
                if let seriesId = model.pendingDeleteSeriesId {
                    let ids = items.filter { $0.seriesId == seriesId }.map(\.itemId)
                    if ids.contains(where: { downloadManager.smartIgnoreTarget(itemId: $0) != nil }) {
                        Button("Delete & Ignore in Smart Downloads", role: .destructive) {
                            downloadManager.deleteAndIgnore(itemIds: ids)
                            model.pendingDeleteSeriesId = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) { model.pendingDeleteSeriesId = nil }
            }
            .alert("Free up space by deleting \(model.selection.count) selected download\(model.selection.count == 1 ? "" : "s")?", isPresented: $model.showBulkDeleteConfirm) {
                Button("Delete", role: .destructive) { onBulkDelete() }
                Button("Cancel", role: .cancel) {}
            }
    }
}
