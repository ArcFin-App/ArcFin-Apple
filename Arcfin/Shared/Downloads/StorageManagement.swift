// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence

/// What Manage Storage is about to delete, waiting for a yes.
struct StoragePendingDelete: Identifiable {
    let id = UUID()
    let title: String
    let itemIds: [String]
    let sizeBytes: Int64
}

/// Manage Storage's groupings: shows (by season) and movies, largest first.
enum StorageManagement {
    struct Show: Identifiable {
        let id: String
        let name: String
        let seasons: [Season]
        var episodes: [DownloadedItem] { seasons.flatMap(\.episodes) }
        var sizeBytes: Int64 { seasons.reduce(0) { $0 + $1.sizeBytes } }
    }

    struct Season: Identifiable {
        let id: String
        let number: Int?
        let episodes: [DownloadedItem]
        var sizeBytes: Int64 { size(of: episodes) }
    }

    static func shows(in items: [DownloadedItem]) -> [Show] {
        Dictionary(grouping: items.filter { $0.seriesId != nil }) { $0.seriesId! }.map { seriesId, episodes in
            let seasons = Dictionary(grouping: episodes) { $0.seasonNumber }.map { number, episodes in
                Season(id: "\(seriesId):\(number.map(String.init) ?? "-")", number: number,
                       episodes: episodes.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) })
            }
            // Specials after the numbered seasons.
            .sorted { ($0.number == 0 ? Int.max : $0.number ?? Int.max) < ($1.number == 0 ? Int.max : $1.number ?? Int.max) }
            return Show(id: seriesId, name: episodes.first?.seriesName ?? String(localized: "Unknown Series"), seasons: seasons)
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func movies(in items: [DownloadedItem]) -> [DownloadedItem] {
        items.filter { $0.seriesId == nil }.sorted { $0.fileSizeBytes > $1.fileSizeBytes }
    }

    // fileSizeBytes only covers each item's video file (not subtitles/trickplay/poster),
    // same as the Downloads list, rather than re-walking the filesystem for a slightly larger number.
    static func size(of items: [DownloadedItem]) -> Int64 { items.reduce(0) { $0 + $1.fileSizeBytes } }

    static func formatted(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    static func seasonTitle(_ number: Int?) -> String {
        switch number {
        case 0: String(localized: "Specials")
        case let number?: String(localized: "Season \(number)")
        case nil: String(localized: "Episodes")
        }
    }

    static func episodeCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 episode") : String(localized: "\(count) episodes")
    }
}

/// Manage Storage on iPhone, iPad and Mac: how space stands, then every show (opening into
/// its seasons and episodes) and movie, each with its own delete and Smart Downloads choices.
struct StorageManagementContent: View {
    let items: [DownloadedItem]

    @Environment(DownloadManager.self) private var downloadManager
    @State private var pendingDelete: StoragePendingDelete?
    @State private var expandedShows: Set<String> = []
    @State private var freeBytes: Int64?
    @State private var deviceTotalBytes: Int64?

    private var shows: [StorageManagement.Show] { StorageManagement.shows(in: items) }
    private var movies: [DownloadedItem] { StorageManagement.movies(in: items) }
    private var watched: [DownloadedItem] { items.filter(\.played) }

    private enum Entry: Identifiable {
        case show(StorageManagement.Show)
        case movie(DownloadedItem)
        var id: String {
            switch self {
            case .show(let show): "show:\(show.id)"
            case .movie(let movie): "movie:\(movie.itemId)"
            }
        }
        var sizeBytes: Int64 {
            switch self {
            case .show(let show): show.sizeBytes
            case .movie(let movie): movie.fileSizeBytes
            }
        }
    }

    private var entries: [Entry] {
        (shows.map(Entry.show) + movies.map(Entry.movie)).sorted { $0.sizeBytes > $1.sizeBytes }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "internaldrive",
                    description: Text("Downloaded movies and shows will appear here once you have some.")
                )
            } else {
                List {
                    Section { summary }
                    Section("Largest First") {
                        ForEach(entries) { entry in
                            switch entry {
                            case .show(let show): showGroup(show)
                            case .movie(let movie): movieRow(movie)
                            }
                        }
                    }
                }
                .arcfinListStyle()
            }
        }
        .screenBackground()
        .onAppear(perform: refreshDeviceSpace)
        .onChange(of: items.count) { refreshDeviceSpace() }
        .alert(pendingDelete?.title ?? "", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { pending in
            Button("Delete", role: .destructive) {
                for id in pending.itemIds { downloadManager.deleteDownload(itemId: id) }
            }
            if pending.itemIds.contains(where: { downloadManager.smartIgnoreTarget(itemId: $0) != nil }) {
                Button("Delete & Ignore in Smart Downloads", role: .destructive) {
                    downloadManager.deleteAndIgnore(itemIds: pending.itemIds)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text("Frees up \(StorageManagement.formatted(pending.sizeBytes)) on this device.")
        }
    }

    // MARK: - Summary

    private var summary: some View {
        let watchedSize = StorageManagement.size(of: watched)
        return VStack(alignment: .leading, spacing: 14) {
            StorageBreakdown(items: items,
                             smartUsedBytes: downloadManager.smartDownloadsUsedBytes(of: items),
                             freeBytes: freeBytes,
                             deviceTotalBytes: deviceTotalBytes)
            if !watched.isEmpty {
                Button {
                    pendingDelete = StoragePendingDelete(title: String(localized: "Delete everything you've watched?"),
                                                         itemIds: watched.map(\.itemId), sizeBytes: watchedSize)
                } label: {
                    Label("Delete Watched · \(StorageManagement.formatted(watchedSize))", systemImage: "checkmark.circle")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(DT.Color.accent)
            }
        }
        .padding(.vertical, 6)
    }

    private func refreshDeviceSpace() {
        let values = try? DownloadStore.rootDirectory().deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
        freeBytes = values?.volumeAvailableCapacity.map(Int64.init)
        deviceTotalBytes = values?.volumeTotalCapacity.map(Int64.init)
    }

    // MARK: - Shows

    @ViewBuilder
    private func showGroup(_ show: StorageManagement.Show) -> some View {
        let isExpanded = expandedShows.contains(show.id)
        StorageRow(artwork: DownloadsModel.seriesPosterURL(show.id, fallback: show.episodes.first),
                   title: show.name,
                   detail: StorageManagement.episodeCount(show.episodes.count),
                   sizeBytes: show.sizeBytes,
                   isExpanded: isExpanded,
                   onTap: {
                       withAnimation(DT.Animation.motion(.snappy)) {
                           if isExpanded { expandedShows.remove(show.id) } else { expandedShows.insert(show.id) }
                       }
                   }) {
            showMenu(show)
        }
        if isExpanded {
            ForEach(show.seasons) { season in
                seasonRow(season, show: show)
                ForEach(season.episodes) { episode in episodeRow(episode) }
            }
        }
    }

    @ViewBuilder
    private func showMenu(_ show: StorageManagement.Show) -> some View {
        let watchedEpisodes = show.episodes.filter(\.played)
        let _ = downloadManager.keptShowsVersion
        Button(role: .destructive) {
            pendingDelete = StoragePendingDelete(title: String(localized: "Delete every episode of \(show.name)?"),
                                                 itemIds: show.episodes.map(\.itemId), sizeBytes: show.sizeBytes)
        } label: { Label("Delete All Episodes", systemImage: "trash") }
        if !watchedEpisodes.isEmpty {
            Button(role: .destructive) {
                pendingDelete = StoragePendingDelete(title: String(localized: "Delete the episodes of \(show.name) you've watched?"),
                                                     itemIds: watchedEpisodes.map(\.itemId),
                                                     sizeBytes: StorageManagement.size(of: watchedEpisodes))
            } label: { Label("Delete Watched", systemImage: "checkmark.circle") }
        }
        Divider()
        Picker(selection: Binding(
            get: { DownloadManager.keptShows[show.id]?.episodeCount ?? 0 },
            set: { downloadManager.setKeptShow(seriesId: show.id, name: show.name, episodeCount: $0 == 0 ? nil : $0) }
        )) {
            Text("Off").tag(0)
            ForEach([1, 2, 3, 5], id: \.self) { count in
                Text(count == 1 ? "Next Episode" : "Next \(count) Episodes").tag(count)
            }
        } label: {
            Label("Keep Downloaded", systemImage: "arrow.down.circle.dotted")
        }
        .pickerStyle(.menu)
        SmartDownloadsIgnoreButton(id: show.id, name: show.name)
    }

    private func seasonRow(_ season: StorageManagement.Season, show: StorageManagement.Show) -> some View {
        HStack {
            Text(StorageManagement.seasonTitle(season.number))
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
            Text(StorageManagement.episodeCount(season.episodes.count))
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
            Spacer()
            Text(StorageManagement.formatted(season.sizeBytes))
                .font(.system(.caption, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DT.Color.textSecondary)
            Menu {
                Button(role: .destructive) {
                    pendingDelete = StoragePendingDelete(
                        title: String(localized: "Delete \(StorageManagement.seasonTitle(season.number)) of \(show.name)?"),
                        itemIds: season.episodes.map(\.itemId), sizeBytes: season.sizeBytes)
                } label: { Label("Delete Season", systemImage: "trash") }
                let watchedEpisodes = season.episodes.filter(\.played)
                if !watchedEpisodes.isEmpty {
                    Button(role: .destructive) {
                        pendingDelete = StoragePendingDelete(
                            title: String(localized: "Delete the watched episodes of \(StorageManagement.seasonTitle(season.number))?"),
                            itemIds: watchedEpisodes.map(\.itemId), sizeBytes: StorageManagement.size(of: watchedEpisodes))
                    } label: { Label("Delete Watched", systemImage: "checkmark.circle") }
                }
            } label: {
                StorageMenuLabel()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Options for \(StorageManagement.seasonTitle(season.number))")
        }
        .padding(.top, 6)
    }

    private func episodeRow(_ episode: DownloadedItem) -> some View {
        StorageRow(artwork: nil,
                   title: [episode.episodeNumber.map { "E\($0)" }, episode.name].compactMap { $0 }.joined(separator: " · "),
                   detail: episode.played ? String(localized: "Watched") : nil,
                   sizeBytes: episode.fileSizeBytes) {
            itemMenu(episode, title: String(localized: "Delete \(episode.name)?"))
        }
        .padding(.leading, 12)
    }

    // MARK: - Movies

    private func movieRow(_ movie: DownloadedItem) -> some View {
        StorageRow(artwork: DownloadsModel.fileURL(movie.posterFileName, in: movie.itemId),
                   title: movie.name,
                   detail: [movie.productionYear.map(String.init), movie.played ? String(localized: "Watched") : nil]
                    .compactMap { $0 }.joined(separator: " · "),
                   sizeBytes: movie.fileSizeBytes) {
            itemMenu(movie, title: String(localized: "Delete \(movie.name)?"))
            SmartDownloadsIgnoreButton(id: movie.itemId, name: movie.name)
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: DownloadedItem, title: String) -> some View {
        Button(role: .destructive) {
            pendingDelete = StoragePendingDelete(title: title, itemIds: [item.itemId], sizeBytes: item.fileSizeBytes)
        } label: { Label("Delete Download", systemImage: "trash") }
    }
}

/// One line in Manage Storage: artwork for a show or movie, its name, a detail, its size and
/// its ⋯ menu.
private struct StorageRow<MenuContent: View>: View {
    let artwork: URL?
    let title: String
    let detail: String?
    let sizeBytes: Int64
    /// Set for a show, which opens into its seasons and episodes when tapped.
    var isExpanded: Bool? = nil
    var onTap: (() -> Void)? = nil
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: 12) {
            if let onTap {
                Button(action: onTap) { rowLabel }
                    .buttonStyle(.plain)
                    .accessibilityHint(isExpanded == true ? "Hides its episodes" : "Shows its episodes")
            } else {
                rowLabel
            }
            Text(StorageManagement.formatted(sizeBytes))
                .font(.system(.caption, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(DT.Color.textSecondary)
            Menu(content: menu) { StorageMenuLabel() }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Options for \(title)")
        }
        .padding(.vertical, 2)
    }

    private var rowLabel: some View {
        HStack(spacing: 12) {
            if let isExpanded {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            if let artwork {
                CachedAsyncImage(url: artwork) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: DT.Color.backgroundTertiary
                    }
                }
                .frame(width: 36, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.footnote, weight: artwork == nil ? .regular : .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}

private struct StorageMenuLabel: View {
    var body: some View {
        Image(systemName: "ellipsis.circle")
            .font(.system(.body))
            .foregroundStyle(DT.Color.textSecondary)
            .frame(minWidth: 32, minHeight: 32)
            .contentShape(Rectangle())
    }
}
