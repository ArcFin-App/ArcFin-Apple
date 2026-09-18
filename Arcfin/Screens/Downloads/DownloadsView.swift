import SwiftUI
import SwiftData
import Persistence

struct DownloadsView: View {
    /// Non-nil only when this is standing in for the whole app (offline mode) — shows a
    /// "Go Back Online" affordance and skips the normal nav chrome.
    var goBackOnline: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager
    @Query(sort: [SortDescriptor(\DownloadedItem.downloadedAt, order: .reverse)]) private var items: [DownloadedItem]

    @State private var selectedItem: DownloadedItem?
    @State private var pendingDelete: DownloadedItem?

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
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                        if !items.isEmpty {
                            Text("\(items.count) downloaded — \(ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)) used")
                                .font(.system(size: 12))
                                .foregroundStyle(DT.Color.textSecondary)
                                .padding(.horizontal, DT.Spacing.pagePad)
                        }

                        if !downloadManager.activeItemTitles.isEmpty {
                            inProgressSection
                        }

                        ForEach(seriesGroups, id: \.seriesId) { group in
                            seriesSection(group)
                        }

                        if !movies.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Movies")
                                    .font(DT.Font.cardTitle)
                                    .foregroundStyle(DT.Color.textPrimary)
                                    .padding(.horizontal, DT.Spacing.pagePad)
                                ForEach(movies) { item in
                                    downloadRow(item)
                                }
                            }
                        }
                    }
                    .padding(.vertical, DT.Spacing.md)
                    .padding(.bottom, 32)
                }
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
        }
        .navigationDestination(item: $selectedItem) { item in
            DownloadedItemDetailView(item: item)
        }
        .confirmationDialog("Delete this download?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { downloadManager.deleteDownload(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    // MARK: - In progress

    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Downloading")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, DT.Spacing.pagePad)
            ForEach(Array(downloadManager.activeItemTitles.keys).sorted(), id: \.self) { itemId in
                inProgressRow(itemId)
            }
        }
    }

    private func inProgressRow(_ itemId: String) -> some View {
        let stats = downloadManager.stats[itemId]
        let fraction = downloadManager.progress[itemId] ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(downloadManager.activeItemTitles[itemId] ?? "Downloading…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button { downloadManager.cancelDownload(itemId: itemId) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .buttonStyle(.plain)
            }
            ProgressView(value: fraction)
                .tint(DT.Color.accent)
            HStack {
                if let stats, stats.totalBytes > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: stats.bytesWritten, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: stats.totalBytes, countStyle: .file))")
                } else {
                    Text("Preparing…")
                }
                Spacer()
                if let stats, stats.bytesPerSecond > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(stats.bytesPerSecond), countStyle: .file))/s")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(12)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private func seriesSection(_ group: (seriesId: String, seriesName: String, episodes: [DownloadedItem])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.seriesName)
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, DT.Spacing.pagePad)
            ForEach(group.episodes) { item in
                downloadRow(item)
            }
        }
    }

    private func downloadRow(_ item: DownloadedItem) -> some View {
        Button { selectedItem = item } label: {
            HStack(spacing: 12) {
                posterThumbnail(item)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rowTitle(item))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                    if let subtitle = rowSubtitle(item) {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineLimit(1)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))
                        .font(.system(size: 10))
                        .foregroundStyle(DT.Color.textSecondary.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { pendingDelete = item } label: {
                Label("Delete Download", systemImage: "trash")
            }
        }
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
            #else
            DT.Color.backgroundSecondary
            #endif
        }
        .frame(width: 46, height: 69)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private func rowTitle(_ item: DownloadedItem) -> String {
        item.seriesId != nil ? (item.seriesName ?? item.name) : item.name
    }

    private func rowSubtitle(_ item: DownloadedItem) -> String? {
        guard item.seriesId != nil else { return item.productionYear.map { String($0) } }
        let s = item.seasonNumber.map { "S\($0)" }
        let e = item.episodeNumber.map { "E\($0)" }
        let code = [s, e].compactMap { $0 }.joined()
        return [code.isEmpty ? nil : code, item.name].compactMap { $0 }.joined(separator: " · ")
    }
}
