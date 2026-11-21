// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence
import JellyfinAPI

/// The Downloads list: storage, the queue, Continue Watching, shows and movies. `play` starts a
/// download the way the platform does, and `manage` sits at the end of the storage card.
struct DownloadsContent<Manage: View>: View {
    let items: [DownloadedItem]
    let model: DownloadsModel
    let isOnline: Bool
    let play: (DownloadedItem) -> Void
    @ViewBuilder let manage: () -> Manage

    @Environment(DownloadManager.self) private var downloadManager

    private var movies: [DownloadedItem] { DownloadsModel.movies(in: items) }
    private var seriesGroups: [DownloadsModel.SeriesGroup] { DownloadsModel.seriesGroups(in: items) }
    private var inProgress: [DownloadedItem] { DownloadsModel.inProgress(in: items) }
    private var upNext: [DownloadedItem] { DownloadsModel.upNext(in: items) }
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueAndUpNext = false
    private var totalSizeBytes: Int64 { DownloadsModel.totalSizeBytes(of: items) }

    private let gridColumns = [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 14, alignment: .top)]

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
                    VStack(alignment: .leading, spacing: 28) {
                        storageCard
                        if let hold = downloadManager.queueHold { heldCard(hold) }
                        if !downloadManager.activeItemTitles.isEmpty { downloadingSection }
                        if !model.isSelecting {
                            if mergeContinueAndUpNext {
                                if !(inProgress + upNext).isEmpty { continueSection("Continue Watching", inProgress + upNext) }
                            } else {
                                if !inProgress.isEmpty { continueSection("Continue Watching", inProgress) }
                                if !upNext.isEmpty { continueSection("Up Next", upNext) }
                            }
                        }
                        if !seriesGroups.isEmpty { showsSection }
                        if !movies.isEmpty { moviesSection }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .animation(DT.Animation.standard, value: downloadManager.orderedInProgressIds)
                }
            }
        }
    }

    private func open(_ item: DownloadedItem) {
        model.open(item, isOnline: isOnline, downloadManager: downloadManager)
    }

    private func openSeries(_ seriesId: String, name: String) {
        model.openSeries(seriesId, name: name, isOnline: isOnline, downloadManager: downloadManager)
    }

    // MARK: - Storage

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.system(.title3))
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Storage")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text(items.count == 1 ? "1 title" : "\(items.count) titles")
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                manage()
            }
            StorageBreakdown(items: items,
                             smartUsedBytes: downloadManager.smartDownloadsUsedBytes(of: items),
                             freeBytes: model.freeBytes)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
            .fill(DT.Color.backgroundSecondary)
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private func sectionHeader(_ title: LocalizedStringKey, count: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
                .tracking(-0.2)
            if let count {
                Text("\(count)")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Held queue

    private func heldCard(_ hold: DownloadManager.QueueHold) -> some View {
        HStack(spacing: 12) {
            Image(systemName: hold == .storage ? "externaldrive.badge.exclamationmark" : hold == .playing ? "play.circle" : hold == .mobileData ? "wifi.exclamationmark" : hold == .lowDataMode ? "antenna.radiowaves.left.and.right.slash" : "battery.25percent")
                .font(.system(.title3))
                .foregroundStyle(DT.Color.palette("F59E0B"))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hold.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Text(hold.detail)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            if hold == .storage {
                manage()
            } else {
                Button("Start") { model.showMobileDataConfirm = true }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                    .accessibilityHint("Starts the downloads now")
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Downloading

    private var downloadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Downloading", count: downloadManager.orderedInProgressIds.count)
                Spacer()
                Menu {
                    if downloadManager.isQueuePaused {
                        Button { downloadManager.resumeQueue() } label: {
                            Label("Resume Queue", systemImage: "play.fill")
                        }
                    } else if !downloadManager.queuedItemIds.isEmpty || !downloadManager.activeItemIds.isEmpty {
                        Button { downloadManager.pauseQueue() } label: {
                            Label("Pause Queue", systemImage: "pause.fill")
                        }
                    }
                    Button(role: .destructive) { model.showCancelAllConfirm = true } label: {
                        Label("Cancel All", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(.title3))
                        .foregroundStyle(DT.Color.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Download queue options")
            }
            VStack(spacing: 0) {
                ForEach(Array(downloadManager.orderedInProgressIds.enumerated()), id: \.element) { index, itemId in
                    if index > 0 {
                        Divider().overlay(DT.Color.textPrimary.opacity(0.06)).padding(.leading, 16)
                    }
                    DownloadingRow(itemId: itemId, cancel: cancel)
                        .contextMenu {
                            if downloadManager.queuedItemIds.first != itemId,
                               downloadManager.queuedItemIds.contains(itemId) {
                                Button { downloadManager.moveToFront(itemId: itemId) } label: {
                                    Label("Download Next", systemImage: "arrow.up.to.line")
                                }
                            }
                            Button(role: .destructive) { cancel(itemId) } label: {
                                Label("Cancel Download", systemImage: "xmark.circle")
                            }
                        }
                }
            }
            .background(cardBackground)
        }
    }

    /// A title Smart Downloads fetched asks whether to ignore it too.
    private func cancel(_ itemId: String) {
        if downloadManager.smartIgnoreTarget(itemId: itemId) != nil {
            model.pendingSmartCancel = itemId
        } else {
            downloadManager.cancelDownload(itemId: itemId)
        }
    }

    // MARK: - Continue watching

    private func continueSection(_ title: LocalizedStringKey, _ shelf: [DownloadedItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Spacing.shelfGap) {
                    ForEach(shelf) { item in
                        Button { play(item) } label: {
                            ContinueCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { play(item) } label: {
                                Label(item.playbackPositionTicks > 0 ? "Resume" : "Play", systemImage: "play.fill")
                            }
                            Button { open(item) } label: { Label("Details", systemImage: "info.circle") }
                        }
                    }
                }
            }
            .shelfScrollButtons()
            .padding(.horizontal, -DT.Spacing.pagePad)
            .contentMargins(.horizontal, DT.Spacing.pagePad, for: .scrollContent)
        }
    }

    // MARK: - Shows and movies

    private var showsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Shows", count: seriesGroups.count)
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(seriesGroups, id: \.seriesId) { group in
                    let id = "series:\(group.seriesId)"
                    let size = group.episodes.reduce(0) { $0 + $1.fileSizeBytes }
                    Button {
                        if model.isSelecting { model.toggleSelection(id) } else { openSeries(group.seriesId, name: group.seriesName) }
                    } label: {
                        PosterTile(
                            artwork: DownloadsModel.seriesPosterURL(group.seriesId, fallback: group.episodes.first),
                            title: group.seriesName,
                            caption: [group.episodes.count == 1 ? String(localized: "1 episode") : String(localized: "\(group.episodes.count) episodes"),
                                      ByteCountFormatter.string(fromByteCount: size, countStyle: .file)].joined(separator: " · "),
                            badge: "\(group.episodes.count)",
                            progress: nil, isWatched: group.episodes.allSatisfy(\.played),
                            selection: model.isSelecting ? model.selection.contains(id) : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !model.isSelecting {
                            Button { openSeries(group.seriesId, name: group.seriesName) } label: {
                                Label("Details", systemImage: "info.circle")
                            }
                            SmartDownloadsIgnoreButton(id: group.seriesId, name: group.seriesName)
                            Button(role: .destructive) { model.pendingDeleteSeriesId = group.seriesId } label: {
                                Label("Delete All Episodes", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Movies", count: movies.count)
            LazyVGrid(columns: gridColumns, spacing: 20) {
                ForEach(movies) { item in
                    let id = "movie:\(item.itemId)"
                    Button {
                        if model.isSelecting { model.toggleSelection(id) } else { open(item) }
                    } label: {
                        PosterTile(
                            artwork: DownloadsModel.fileURL(item.posterFileName, in: item.itemId),
                            title: item.name,
                            caption: [item.productionYear.map(String.init), ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file)]
                                .compactMap { $0 }.joined(separator: " · "),
                            badge: nil,
                            progress: item.played || item.runtimeTicks <= 0 || item.playbackPositionTicks <= 0
                                ? nil : min(Double(item.playbackPositionTicks) / Double(item.runtimeTicks), 1),
                            isWatched: item.played,
                            selection: model.isSelecting ? model.selection.contains(id) : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !model.isSelecting {
                            Button { play(item) } label: {
                                Label(item.playbackPositionTicks > 0 && !item.played ? "Resume" : "Play", systemImage: "play.fill")
                            }
                            Button { open(item) } label: { Label("Details", systemImage: "info.circle") }
                            SmartDownloadsIgnoreButton(id: item.itemId, name: item.name)
                            Button(role: .destructive) { model.pendingDelete = item } label: {
                                Label("Delete Download", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Downloads' confirmations: deleting a title, a show or the selection, starting held
/// downloads and cancelling the queue.
struct DownloadsAlerts: ViewModifier {
    let items: [DownloadedItem]
    @Bindable var model: DownloadsModel

    @Environment(DownloadManager.self) private var downloadManager

    func body(content: Content) -> some View {
        content
            .alert("Smart Downloads fetched this. Cancel it?", isPresented: Binding(
                get: { model.pendingSmartCancel != nil }, set: { if !$0 { model.pendingSmartCancel = nil } }
            )) {
                Button("Cancel Download", role: .destructive) {
                    if let id = model.pendingSmartCancel { downloadManager.cancelDownload(itemId: id) }
                    model.pendingSmartCancel = nil
                }
                Button("Cancel & Ignore in Smart Downloads", role: .destructive) {
                    if let id = model.pendingSmartCancel { downloadManager.deleteAndIgnore(itemIds: [id]) }
                    model.pendingSmartCancel = nil
                }
                Button("Keep Downloading", role: .cancel) { model.pendingSmartCancel = nil }
            }
            .alert("Delete this download?", isPresented: Binding(
                get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let pendingDelete = model.pendingDelete { downloadManager.deleteDownload(pendingDelete) }
                    model.pendingDelete = nil
                }
                if let pendingDelete = model.pendingDelete, downloadManager.smartIgnoreTarget(itemId: pendingDelete.itemId) != nil {
                    Button("Delete & Ignore in Smart Downloads", role: .destructive) {
                        downloadManager.deleteAndIgnore(itemIds: [pendingDelete.itemId])
                        model.pendingDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { model.pendingDelete = nil }
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
            .alert(downloadManager.queueHold == .mobileData ? "Download on Mobile Data?" : "Download Now?",
                   isPresented: $model.showMobileDataConfirm) {
                Button("Download") { downloadManager.startHeldDownloads() }
                Button("Cancel", role: .cancel) {}
            } message: {
                switch downloadManager.queueHold {
                case .mobileData: Text("You're not on Wi-Fi. Downloading uses your mobile data, and charges may apply.")
                case .lowDataMode: Text("Low Data Mode is on. Downloading uses data your device is trying to save.")
                case .playing: Text("A video is playing. Downloading now shares its connection, which can lower its quality.")
                default: Text("Low Power Mode is on. Downloading uses more battery.")
                }
            }
            .alert("Cancel all downloads?", isPresented: $model.showCancelAllConfirm) {
                Button("Cancel All Downloads", role: .destructive) { downloadManager.cancelAllDownloads() }
                Button("Keep Downloading", role: .cancel) {}
            } message: {
                Text("What's already downloaded of them is discarded.")
            }
            .alert(model.selection.count == 1 ? "Delete 1 selected download?" : "Delete \(model.selection.count) selected downloads?",
                   isPresented: $model.showBulkDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    model.deleteSelection(in: items, downloadManager: downloadManager)
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

/// Select and Delete for picking several downloads at once, where the platform offers it.
struct DownloadsSelectionToolbar: ToolbarContent {
    let isOffline: Bool
    let hasItems: Bool
    let model: DownloadsModel

    var body: some ToolbarContent {
        if !isOffline, hasItems {
            if model.isSelecting && !model.selection.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete (\(model.selection.count))", role: .destructive) {
                        model.showBulkDeleteConfirm = true
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(model.isSelecting ? "Done" : "Select") {
                    withAnimation(DT.Animation.fast) { model.isSelecting.toggle() }
                    model.selection.removeAll()
                }
            }
        }
    }
}

// MARK: - Downloading row

/// One title in Downloading. Its own view, so a progress tick redraws this row and not the
/// whole Downloads list.
private struct DownloadingRow: View {
    let itemId: String
    let cancel: (String) -> Void

    @Environment(DownloadManager.self) private var downloadManager

    var body: some View {
        let stats = downloadManager.stats[itemId]
        let fraction = downloadManager.progress[itemId] ?? 0
        let isActive = downloadManager.activeItemIds.contains(itemId) && !downloadManager.queuedItemIds.contains(itemId)
        let isPaused = downloadManager.pausedItemIds.contains(itemId)
        let item = downloadManager.activeItems[itemId]
        let isEpisode = item?.type == .episode
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((isEpisode ? item?.seriesName : nil) ?? downloadManager.activeItemTitles[itemId] ?? String(localized: "Downloading…"))
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(isActive ? DT.Color.textPrimary : DT.Color.textSecondary)
                        .lineLimit(1)
                    if isEpisode, let item, let subtitle = HomeText.subtitle(item) {
                        Text(subtitle)
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let stats, stats.totalBytes > 0 {
                    Text(Double(fraction), format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
                        .font(.system(.caption, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DT.Color.textSecondary)
                        .contentTransition(.numericText())
                        .animation(.default, value: fraction)
                }
                if isActive {
                    Button {
                        if isPaused { downloadManager.resumeDownload(itemId: itemId) }
                        else { downloadManager.pauseDownload(itemId: itemId) }
                    } label: {
                        Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.system(.title3))
                            .foregroundStyle(DT.Color.textSecondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(isPaused ? "Resume download" : "Pause download")
                    .buttonStyle(.plain)
                }
                Button { cancel(itemId) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.title3))
                        .foregroundStyle(DT.Color.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Cancel download")
                .buttonStyle(.plain)
            }
            if isActive {
                Group {
                    if let stats, stats.totalBytes > 0 {
                        ProgressView(value: fraction)
                    } else if stats != nil {
                        // Total size isn't knowable ahead of time for a server-side remux
                        // download — still show that data IS flowing, not a static empty bar.
                        ProgressView()
                    } else {
                        ProgressView(value: 0)
                    }
                }
                .tint(isPaused ? DT.Color.palette("F59E0B") : DT.Color.accent)
            }
            HStack {
                if let stats, stats.bytesWritten > 0, stats.totalBytes > 0 {
                    let total = (stats.isEstimate ? "~" : "") + ByteCountFormatter.string(fromByteCount: stats.totalBytes, countStyle: .file)
                    Text("\(ByteCountFormatter.string(fromByteCount: stats.bytesWritten, countStyle: .file)) of \(total)")
                } else if let stats, stats.bytesWritten > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: stats.bytesWritten, countStyle: .file)) downloaded")
                } else if downloadManager.queuedItemIds.contains(itemId) {
                    Text(downloadManager.isQueuePaused ? "Paused"
                         : downloadManager.queueHold?.title ?? "Waiting in queue")
                } else {
                    Text("Preparing…")
                }
                Spacer()
                if isPaused {
                    Text("Paused")
                } else if let stats, stats.bytesPerSecond > 0 {
                    let speed = "\(ByteCountFormatter.string(fromByteCount: Int64(stats.bytesPerSecond), countStyle: .file))/s"
                    if stats.totalBytes > stats.bytesWritten {
                        let left = (stats.isEstimate ? "~" : "") + Duration.seconds(Double(stats.totalBytes - stats.bytesWritten) / stats.bytesPerSecond)
                            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
                        Text("\(speed) · \(left) left")
                    } else {
                        Text(speed)
                    }
                }
            }
            .font(.system(.caption))
            .monospacedDigit()
            .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Poster tile

/// A poster with its title and size under it, like the library grids; while selecting, a
/// check in the corner shows whether it's picked.
private struct PosterTile: View {
    let artwork: URL?
    let title: String
    let caption: String
    let badge: String?
    let progress: Double?
    let isWatched: Bool
    /// nil when not selecting.
    let selection: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    CachedAsyncImage(url: artwork) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default:
                            ZStack {
                                DT.Color.backgroundSecondary
                                Image(systemName: "film").foregroundStyle(DT.Color.textSecondary.opacity(0.5))
                            }
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.5))
                                Rectangle().fill(DT.Color.accent).frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let selection {
                        Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(selection ? DT.Color.accent : .white)
                            .shadow(color: .black.opacity(0.5), radius: 4)
                            .padding(6)
                    } else if isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white, DT.Color.accent)
                            .padding(6)
                    } else if let badge {
                        Text(badge)
                            .font(.system(.caption2, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                        .stroke(selection == true ? DT.Color.accent : DT.Color.textPrimary.opacity(0.08), lineWidth: selection == true ? 2 : 1)
                )
                .opacity(selection == false ? 0.7 : 1)
            Text(title)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            Text(caption)
                .font(.system(.caption2))
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selection == true ? .isSelected : [])
    }
}

// MARK: - Continue card

private struct ContinueCard: View {
    let item: DownloadedItem

    private var artwork: URL? {
        let dir = DownloadStore.directory(for: item.itemId)
        if let backdrop = item.backdropFileName { return dir.appendingPathComponent(backdrop) }
        if let seriesId = item.seriesId {
            let seriesBackdrop = DownloadStore.directory(for: seriesId).appendingPathComponent("backdrop.jpg")
            if FileManager.default.fileExists(atPath: seriesBackdrop.path) { return seriesBackdrop }
        }
        return item.posterFileName.map { dir.appendingPathComponent($0) }
    }

    private var fraction: Double {
        item.runtimeTicks > 0 ? min(Double(item.playbackPositionTicks) / Double(item.runtimeTicks), 1) : 0
    }

    private var subtitle: String {
        var parts: [String] = []
        if let season = item.seasonNumber, let episode = item.episodeNumber { parts.append("S\(season) E\(episode)") }
        if item.runtimeTicks > item.playbackPositionTicks {
            parts.append(String(localized: "\(max(Int(Double(item.runtimeTicks - item.playbackPositionTicks) / 600_000_000), 1)) min left"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: artwork) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: DT.Color.backgroundSecondary
                }
            }
            .frame(width: DT.Size.backdropCard.width, height: DT.Size.backdropCard.height)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.seriesName ?? item.name)
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(.caption2))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle.fill")
                        .font(.system(.title2))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3))
                        Capsule().fill(DT.Color.accent).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
            }
            .padding(10)
        }
        .frame(width: DT.Size.backdropCard.width, height: DT.Size.backdropCard.height)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous).stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resume \(item.seriesName.map { "\($0), \(item.name)" } ?? item.name)")
    }
}
