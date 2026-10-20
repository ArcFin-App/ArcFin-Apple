// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence
#if os(macOS)
import AppKit
#endif

/// Navigation payload for a series container row — a thin wrapper instead of a bare String
/// so `.navigationDestination(for:)` can dispatch to the series detail view specifically,
/// without colliding with any other String-based destination elsewhere in the app.
struct DownloadedSeriesRef: Hashable {
    let seriesId: String
}

struct DownloadsView: View {
    /// Non-nil only when this is standing in for the whole app (offline mode) — shows a
    /// "Go Back Online" affordance and skips the normal nav chrome.
    var goBackOnline: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager
    @Query(sort: [SortDescriptor(\DownloadedItem.downloadedAt, order: .reverse)]) private var items: [DownloadedItem]

    @State private var pendingDelete: DownloadedItem?
    @State private var pendingDeleteSeriesId: String?
    // Owned here rather than relying on an ancestor's navigationDestination(for:) — this
    // view is itself pushed non-root (Library's Downloads row, offline mode's stack), and a
    // NavigationLink(value:) pushed from a nested view can silently fail to resolve against
    // a destination declared further up the stack (see the See All fix, 306aaf3).
    @State private var selectedItem: DownloadedItem?
    @State private var selectedSeriesRef: DownloadedSeriesRef?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #elseif os(macOS)
    @State private var isSelectingMac = false
    #endif
    @State private var selection = Set<String>()
    @State private var showBulkDeleteConfirm = false

    private var movies: [DownloadedItem] { items.filter { $0.seriesId == nil }.sorted { $0.name < $1.name } }

    private var seriesGroups: [(seriesId: String, seriesName: String, episodes: [DownloadedItem])] {
        let grouped = Dictionary(grouping: items.filter { $0.seriesId != nil }) { $0.seriesId! }
        return grouped.map { (id, episodes) in
            (seriesId: id, seriesName: episodes.first?.seriesName ?? "Unknown Series",
             episodes: episodes.sorted { ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) < ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0) })
        }.sorted { $0.seriesName < $1.seriesName }
    }

    private var totalSizeBytes: Int64 { items.reduce(0) { $0 + $1.fileSizeBytes } }

    var body: some View {
        Group {
            if items.isEmpty && downloadManager.activeItemTitles.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Download movies and episodes to watch them without a connection.")
                )
            } else {
                // Deliberately NOT List(selection:) — combining native List selection with
                // NavigationLink(value:) rows produced exactly the "tap does nothing, back
                // reveals it actually pushed" bug: the first tap in a fresh List seems to
                // get absorbed by the selection machinery instead of the navigation link,
                // even with editMode inactive. Selection is fully manual instead (a checkmark
                // row replacing the NavigationLink while editing), which has no such ambiguity.
                List {
                    if !items.isEmpty {
                        Section {
                            Text("\(items.count) downloaded — \(ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)) used")
                                .font(.system(.caption))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        #if os(iOS)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        #endif
                    }

                    if !downloadManager.activeItemTitles.isEmpty {
                        Section("Downloading") {
                            ForEach(Array(downloadManager.activeItemTitles.keys).sorted(), id: \.self) { itemId in
                                inProgressRow(itemId)
                                    #if os(iOS)
                                    .listRowSeparator(.hidden)
                                    #endif
                            }
                        }
                    }

                    if !seriesGroups.isEmpty {
                        Section("Shows") {
                            ForEach(seriesGroups, id: \.seriesId) { group in
                                seriesRow(group)
                            }
                        }
                    }

                    if !movies.isEmpty {
                        Section("Movies") {
                            ForEach(movies) { item in
                                movieRow(item)
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                #endif
            }
        }
        .background(DT.Color.backgroundPrimary)
        .navigationTitle("Downloads")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            if let goBackOnline {
                ToolbarItem(placement: .primaryAction) {
                    Button("Go Back Online", action: goBackOnline)
                }
            }
            #if os(iOS)
            if goBackOnline == nil, !items.isEmpty {
                if editMode.isEditing && !selection.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Delete (\(selection.count))", role: .destructive) {
                            showBulkDeleteConfirm = true
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        editMode = editMode.isEditing ? .inactive : .active
                        selection.removeAll()
                    }
                }
            }
            #elseif os(macOS)
            if goBackOnline == nil, !items.isEmpty {
                if isSelectingMac && !selection.isEmpty {
                    ToolbarItem {
                        Button("Delete (\(selection.count))", role: .destructive) {
                            showBulkDeleteConfirm = true
                        }
                    }
                }
                ToolbarItem {
                    Button(isSelectingMac ? "Done" : "Select") {
                        isSelectingMac.toggle()
                        selection.removeAll()
                    }
                }
            }
            #endif
        }
        .navigationDestination(item: $selectedItem) { item in
            DownloadedItemDetailView(item: item)
        }
        .navigationDestination(item: $selectedSeriesRef) { ref in
            DownloadedSeriesDetailView(seriesId: ref.seriesId)
        }
        .alert("Delete this download?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { downloadManager.deleteDownload(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .alert("Delete this show's downloads?", isPresented: Binding(
            get: { pendingDeleteSeriesId != nil }, set: { if !$0 { pendingDeleteSeriesId = nil } }
        )) {
            Button("Delete All Episodes", role: .destructive) {
                if let seriesId = pendingDeleteSeriesId {
                    downloadManager.deleteDownloads(items.filter { $0.seriesId == seriesId })
                }
                pendingDeleteSeriesId = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteSeriesId = nil }
        }
        .alert("Delete \(selection.count) selected download\(selection.count == 1 ? "" : "s")?", isPresented: $showBulkDeleteConfirm) {
            Button("Delete", role: .destructive) {
                deleteSelection()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteSelection() {
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
        #if os(iOS)
        editMode = .inactive
        #elseif os(macOS)
        isSelectingMac = false
        #endif
    }

    #if os(iOS) || os(macOS)
    private func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func selectionIndicator(_ id: String) -> some View {
        Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle")
            .font(.system(.title3))
            .foregroundStyle(selection.contains(id) ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
    }
    #endif

    @ViewBuilder
    private func seriesRow(_ group: (seriesId: String, seriesName: String, episodes: [DownloadedItem])) -> some View {
        #if os(iOS)
        if editMode.isEditing {
            let id = "series:\(group.seriesId)"
            Button { toggleSelection(id) } label: {
                HStack(spacing: 12) {
                    selectionIndicator(id)
                    seriesRowContent(group)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button { selectedSeriesRef = DownloadedSeriesRef(seriesId: group.seriesId) } label: {
                seriesRowContent(group)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDeleteSeriesId = group.seriesId } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        #elseif os(macOS)
        if isSelectingMac {
            let id = "series:\(group.seriesId)"
            Button { toggleSelection(id) } label: {
                HStack(spacing: 12) {
                    selectionIndicator(id)
                    seriesRowContent(group)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button { selectedSeriesRef = DownloadedSeriesRef(seriesId: group.seriesId) } label: {
                seriesRowContent(group)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu(menuItems: {
                Button(role: .destructive) { pendingDeleteSeriesId = group.seriesId } label: {
                    Label("Delete All Episodes", systemImage: "trash")
                }
            }, preview: {
                seriesRowPreview(group)
            })
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDeleteSeriesId = group.seriesId } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        #else
        Button { selectedSeriesRef = DownloadedSeriesRef(seriesId: group.seriesId) } label: {
            seriesRowContent(group)
        }
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    private func movieRow(_ item: DownloadedItem) -> some View {
        #if os(iOS)
        if editMode.isEditing {
            let id = "movie:\(item.itemId)"
            Button { toggleSelection(id) } label: {
                HStack(spacing: 12) {
                    selectionIndicator(id)
                    downloadRowContent(item)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button { selectedItem = item } label: {
                downloadRowContent(item)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDelete = item } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        #elseif os(macOS)
        if isSelectingMac {
            let id = "movie:\(item.itemId)"
            Button { toggleSelection(id) } label: {
                HStack(spacing: 12) {
                    selectionIndicator(id)
                    downloadRowContent(item)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button { selectedItem = item } label: {
                downloadRowContent(item)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu(menuItems: {
                Button(role: .destructive) { pendingDelete = item } label: {
                    Label("Delete Download", systemImage: "trash")
                }
            }, preview: {
                movieRowPreview(item)
            })
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDelete = item } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        #else
        Button { selectedItem = item } label: {
            downloadRowContent(item)
        }
        .buttonStyle(.plain)
        #endif
    }

    // MARK: - In progress

    private func inProgressRow(_ itemId: String) -> some View {
        let stats = downloadManager.stats[itemId]
        let fraction = downloadManager.progress[itemId] ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(downloadManager.activeItemTitles[itemId] ?? "Downloading…")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let stats, stats.totalBytes > 0 {
                    Text("\(Int(fraction * 100))%")
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(DT.Color.textSecondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: fraction)
                }
                Button { downloadManager.cancelDownload(itemId: itemId) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.body))
                        .foregroundStyle(DT.Color.textSecondary)
                        // This row only exists while the item is actively downloading, so the
                        // pulse is inherently scoped to that — no extra on/off plumbing needed.
                        .symbolEffect(.pulse)
                }
                .accessibilityLabel("Cancel download")
                .buttonStyle(.plain)
            }
            if let stats, stats.totalBytes > 0 {
                ProgressView(value: fraction).tint(DT.Color.accent)
            } else if stats != nil {
                // Total size isn't knowable ahead of time for a server-side remux/transcode
                // download — still show that data IS flowing, not a static empty bar.
                ProgressView().tint(DT.Color.accent)
            } else {
                ProgressView(value: 0).tint(DT.Color.accent)
            }
            HStack {
                if let stats, stats.bytesWritten > 0, stats.totalBytes > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: stats.bytesWritten, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: stats.totalBytes, countStyle: .file))")
                } else if let stats, stats.bytesWritten > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: stats.bytesWritten, countStyle: .file)) downloaded")
                } else {
                    Text("Preparing…")
                }
                Spacer()
                if let stats, stats.bytesPerSecond > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(stats.bytesPerSecond), countStyle: .file))/s")
                }
            }
            .font(.system(.caption2))
            .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Series container row

    private func seriesRowContent(_ group: (seriesId: String, seriesName: String, episodes: [DownloadedItem])) -> some View {
        let totalSize = group.episodes.reduce(0) { $0 + $1.fileSizeBytes }
        return HStack(spacing: 12) {
            seriesPosterThumbnail(group.seriesId, fallbackItem: group.episodes.first)
            VStack(alignment: .leading, spacing: 3) {
                Text(group.seriesName)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text("\(group.episodes.count) episode\(group.episodes.count == 1 ? "" : "s") downloaded")
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
                Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.7))
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func seriesRowPreview(_ group: (seriesId: String, seriesName: String, episodes: [DownloadedItem])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                #if canImport(UIKit)
                if let uiImage = UIImage(contentsOfFile: DownloadStore.directory(for: group.seriesId).appendingPathComponent("poster.jpg").path) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else if let fallbackItem = group.episodes.first, let fileName = fallbackItem.posterFileName,
                          let uiImage = UIImage(contentsOfFile: DownloadStore.directory(for: fallbackItem.itemId).appendingPathComponent(fileName).path) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    DT.Color.backgroundSecondary
                }
                #elseif os(macOS)
                if let nsImage = NSImage(contentsOfFile: DownloadStore.directory(for: group.seriesId).appendingPathComponent("poster.jpg").path) {
                    Image(nsImage: nsImage).resizable().scaledToFill()
                } else if let fallbackItem = group.episodes.first, let fileName = fallbackItem.posterFileName,
                          let nsImage = NSImage(contentsOfFile: DownloadStore.directory(for: fallbackItem.itemId).appendingPathComponent(fileName).path) {
                    Image(nsImage: nsImage).resizable().scaledToFill()
                } else {
                    DT.Color.backgroundSecondary
                }
                #else
                DT.Color.backgroundSecondary
                #endif
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(group.seriesName)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }

    private func seriesPosterThumbnail(_ seriesId: String, fallbackItem: DownloadedItem?) -> some View {
        Group {
            #if canImport(UIKit)
            if let uiImage = UIImage(contentsOfFile: DownloadStore.directory(for: seriesId).appendingPathComponent("poster.jpg").path) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else if let fallbackItem, let fileName = fallbackItem.posterFileName,
                      let uiImage = UIImage(contentsOfFile: DownloadStore.directory(for: fallbackItem.itemId).appendingPathComponent(fileName).path) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #elseif os(macOS)
            if let nsImage = NSImage(contentsOfFile: DownloadStore.directory(for: seriesId).appendingPathComponent("poster.jpg").path) {
                Image(nsImage: nsImage).resizable().scaledToFill()
            } else if let fallbackItem, let fileName = fallbackItem.posterFileName,
                      let nsImage = NSImage(contentsOfFile: DownloadStore.directory(for: fallbackItem.itemId).appendingPathComponent(fileName).path) {
                Image(nsImage: nsImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #else
            DT.Color.backgroundSecondary
            #endif
        }
        .frame(width: 46, height: 69)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Movie row

    private func downloadRowContent(_ item: DownloadedItem) -> some View {
        HStack(spacing: 12) {
            posterThumbnail(item)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                if let year = item.productionYear {
                    Text(String(year))
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Text(ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.7))
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func movieRowPreview(_ item: DownloadedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                #if canImport(UIKit)
                if let fileName = item.posterFileName,
                   let uiImage = UIImage(contentsOfFile: DownloadStore.directory(for: item.itemId).appendingPathComponent(fileName).path) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    DT.Color.backgroundSecondary
                }
                #elseif os(macOS)
                if let fileName = item.posterFileName,
                   let nsImage = NSImage(contentsOfFile: DownloadStore.directory(for: item.itemId).appendingPathComponent(fileName).path) {
                    Image(nsImage: nsImage).resizable().scaledToFill()
                } else {
                    DT.Color.backgroundSecondary
                }
                #else
                DT.Color.backgroundSecondary
                #endif
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(item.name)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }

    private func posterThumbnail(_ item: DownloadedItem) -> some View {
        Group {
            #if canImport(UIKit)
            if let fileName = item.posterFileName,
               let uiImage = UIImage(contentsOfFile: DownloadStore.directory(for: item.itemId).appendingPathComponent(fileName).path) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #elseif os(macOS)
            if let fileName = item.posterFileName,
               let nsImage = NSImage(contentsOfFile: DownloadStore.directory(for: item.itemId).appendingPathComponent(fileName).path) {
                Image(nsImage: nsImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #else
            DT.Color.backgroundSecondary
            #endif
        }
        .frame(width: 46, height: 69)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}
