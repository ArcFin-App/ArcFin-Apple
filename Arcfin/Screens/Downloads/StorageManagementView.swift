import SwiftUI
import SwiftData
import Persistence

struct StorageManagementView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Query(sort: [SortDescriptor(\DownloadedItem.downloadedAt, order: .reverse)]) private var items: [DownloadedItem]

    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #elseif os(macOS)
    @State private var isSelectingMac = false
    #endif
    @State private var selection = Set<String>()
    @State private var showBulkDeleteConfirm = false
    @State private var pendingDeleteMovie: DownloadedItem?
    @State private var pendingDeleteSeriesId: String?

    private struct StorageEntry: Identifiable {
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
    private var entries: [StorageEntry] {
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

    private var totalSizeBytes: Int64 { items.reduce(0) { $0 + $1.fileSizeBytes } }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "internaldrive",
                    description: Text("Downloaded movies and shows will appear here once you have some.")
                )
            } else {
                List {
                    Section {
                        Text("\(ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)) used by \(items.count) download\(items.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    #if os(iOS)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    #endif

                    Section("Largest First") {
                        ForEach(entries) { entry in
                            entryRow(entry)
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
        .navigationTitle("Manage Storage")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            #if os(iOS)
            if !entries.isEmpty {
                if editMode.isEditing && !selection.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Free Up Space (\(selection.count))", role: .destructive) {
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
            if !entries.isEmpty {
                if isSelectingMac && !selection.isEmpty {
                    ToolbarItem {
                        Button("Free Up Space (\(selection.count))", role: .destructive) {
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
        .alert("Delete this download?", isPresented: Binding(
            get: { pendingDeleteMovie != nil }, set: { if !$0 { pendingDeleteMovie = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteMovie { downloadManager.deleteDownload(pendingDeleteMovie) }
                pendingDeleteMovie = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteMovie = nil }
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
        .alert("Free up space by deleting \(selection.count) selected download\(selection.count == 1 ? "" : "s")?", isPresented: $showBulkDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteSelection() {
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
            .font(.system(size: 20))
            .foregroundStyle(selection.contains(id) ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
    }
    #endif

    private var isSelecting: Bool {
        #if os(iOS)
        editMode.isEditing
        #elseif os(macOS)
        isSelectingMac
        #else
        false
        #endif
    }

    @ViewBuilder
    private func entryRow(_ entry: StorageEntry) -> some View {
        #if os(iOS) || os(macOS)
        if isSelecting {
            Button { toggleSelection(entry.id) } label: {
                HStack(spacing: 12) {
                    selectionIndicator(entry.id)
                    entryRowContent(entry)
                }
            }
            .buttonStyle(.plain)
        } else {
            entryRowContent(entry)
                #if os(macOS)
                .contextMenu {
                    Button(role: .destructive) {
                        if let movie = entry.movie {
                            pendingDeleteMovie = movie
                        } else {
                            pendingDeleteSeriesId = entry.seriesId
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                #endif
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if let movie = entry.movie {
                            pendingDeleteMovie = movie
                        } else {
                            pendingDeleteSeriesId = entry.seriesId
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
        #else
        entryRowContent(entry)
        #endif
    }

    private func entryRowContent(_ entry: StorageEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { StorageManagementView() }
}
