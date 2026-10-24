// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence
import JellyfinAPI
import AuthCore

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
    @Environment(AuthManager.self) private var authManager
    @Query(sort: [SortDescriptor(\DownloadedItem.downloadedAt, order: .reverse)]) private var items: [DownloadedItem]

    @State private var pendingDelete: DownloadedItem?
    @State private var pendingDeleteSeriesId: String?
    // Owned here rather than relying on an ancestor's navigationDestination(for:) — this
    // view is itself pushed non-root (Library's Downloads row, offline mode's stack), and a
    // NavigationLink(value:) pushed from a nested view can silently fail to resolve against
    // a destination declared further up the stack (see the See All fix, 306aaf3).
    @State private var selectedItem: DownloadedItem?
    @State private var selectedSeriesRef: DownloadedSeriesRef?
    @State private var selectedMedia: MediaItem?
    @State private var playingItem: DownloadedItem?
    @State private var isSelecting = false
    @State private var selection = Set<String>()
    @State private var showBulkDeleteConfirm = false
    @State private var showMobileDataConfirm = false
    @State private var showCancelAllConfirm = false
    @State private var freeBytes: Int64?

    /// With a connection, a download opens the title's full page; offline, the saved one.
    private var isOnline: Bool { goBackOnline == nil && authManager.state.credential != nil }

    private var movies: [DownloadedItem] { items.filter { $0.seriesId == nil }.sorted { $0.name < $1.name } }

    private var seriesGroups: [(seriesId: String, seriesName: String, episodes: [DownloadedItem])] {
        let grouped = Dictionary(grouping: items.filter { $0.seriesId != nil }) { $0.seriesId! }
        return grouped.map { (id, episodes) in
            (seriesId: id, seriesName: episodes.first?.seriesName ?? "Unknown Series",
             episodes: episodes.sorted { ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) < ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0) })
        }.sorted { $0.seriesName < $1.seriesName }
    }

    private var inProgress: [DownloadedItem] {
        items.filter { $0.playbackPositionTicks > 0 && !$0.played }
    }

    private var totalSizeBytes: Int64 { items.reduce(0) { $0 + $1.fileSizeBytes } }

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
                        if !inProgress.isEmpty, !isSelecting { continueSection }
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
        .screenBackground()
        .onAppear {
            downloadManager.removeExpiredDownloads()
            downloadManager.purgeWatchedDownloads()
        }
        .task(id: items.count) { freeBytes = Self.availableBytes() }
        .task { if isOnline { await downloadManager.saveMissingDetails() } }
        .navigationTitle("Downloads")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { toolbarContent }
        .navigationDestination(item: $selectedItem) { item in
            DownloadedItemDetailView(item: item)
        }
        .navigationDestination(item: $selectedSeriesRef) { ref in
            DownloadedSeriesDetailView(seriesId: ref.seriesId)
        }
        .navigationDestination(item: $selectedMedia) { item in
            MediaDetailView(item: item)
        }
        #if os(iOS)
        .fullScreenCover(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item)
        }
        #elseif os(macOS)
        .sheet(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item)
                .frame(minWidth: 900, minHeight: 560)
        }
        #endif
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
        .alert(downloadManager.queueHold == .mobileData ? "Download on Mobile Data?" : "Download Now?",
               isPresented: $showMobileDataConfirm) {
            Button("Download") { downloadManager.startHeldDownloads() }
            Button("Cancel", role: .cancel) {}
        } message: {
            switch downloadManager.queueHold {
            case .mobileData: Text("You're not on Wi-Fi. Downloading uses your mobile data, and charges may apply.")
            case .lowDataMode: Text("Low Data Mode is on. Downloading uses data your device is trying to save.")
            default: Text("Low Power Mode is on. Downloading uses more battery.")
            }
        }
        .confirmationDialog("Cancel all downloads?", isPresented: $showCancelAllConfirm, titleVisibility: .visible) {
            Button("Cancel All Downloads", role: .destructive) { downloadManager.cancelAllDownloads() }
            Button("Keep Downloading", role: .cancel) {}
        } message: {
            Text("What's already downloaded of them is discarded.")
        }
        .alert("Delete \(selection.count) selected download\(selection.count == 1 ? "" : "s")?", isPresented: $showBulkDeleteConfirm) {
            Button("Delete", role: .destructive) {
                deleteSelection()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let goBackOnline {
            ToolbarItem(placement: .primaryAction) {
                Button("Go Back Online", action: goBackOnline)
            }
        }
        #if !os(tvOS)
        if goBackOnline == nil, !items.isEmpty {
            if isSelecting && !selection.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete (\(selection.count))", role: .destructive) {
                        showBulkDeleteConfirm = true
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation(DT.Animation.fast) { isSelecting.toggle() }
                    selection.removeAll()
                }
            }
        }
        #endif
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
        isSelecting = false
    }

    // MARK: - Navigation

    private func open(_ item: DownloadedItem) {
        if isOnline {
            selectedMedia = downloadManager.savedDetail(itemId: item.itemId)?.item ?? Self.mediaItem(for: item)
        } else {
            selectedItem = item
        }
    }

    private func openSeries(_ seriesId: String, name: String) {
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

    private func play(_ item: DownloadedItem) {
        #if os(tvOS)
        open(item)
        #else
        playingItem = item
        #endif
    }

    // MARK: - Storage

    private static func availableBytes() -> Int64? {
        let values = try? DownloadStore.rootDirectory().deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    private var storageCard: some View {
        let used = totalSizeBytes
        let free = freeBytes ?? 0
        let share = used + free > 0 ? Double(used) / Double(used + free) : 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(.title2))
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(items.count == 1 ? "1 title" : "\(items.count) titles")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text(storageCaption(used: used))
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                #if !os(tvOS)
                NavigationLink {
                    StorageManagementView()
                } label: {
                    Text("Manage")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .buttonStyle(.glass)
                #endif
            }
            if freeBytes != nil {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DT.Color.textPrimary.opacity(0.1))
                        Capsule()
                            .fill(DT.Color.accent)
                            .frame(width: max(geo.size.width * share, used > 0 ? 6 : 0))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }

    private func storageCaption(used: Int64) -> String {
        let usedText = ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
        guard let freeBytes else { return "\(usedText) used" }
        return "\(usedText) used · \(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)) free"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
            .fill(DT.Color.backgroundSecondary)
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
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
            Image(systemName: hold == .mobileData ? "wifi.exclamationmark" : hold == .lowDataMode ? "antenna.radiowaves.left.and.right.slash" : "battery.25percent")
                .font(.system(.title3))
                .foregroundStyle(.orange)
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
            Button("Start") { showMobileDataConfirm = true }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)
                .accessibilityHint("Starts the downloads now")
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
                    Button(role: .destructive) { showCancelAllConfirm = true } label: {
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
                    inProgressRow(itemId)
                        .contextMenu {
                            if downloadManager.queuedItemIds.first != itemId,
                               downloadManager.queuedItemIds.contains(itemId) {
                                Button { downloadManager.moveToFront(itemId: itemId) } label: {
                                    Label("Download Next", systemImage: "arrow.up.to.line")
                                }
                            }
                            Button(role: .destructive) { downloadManager.cancelDownload(itemId: itemId) } label: {
                                Label("Cancel Download", systemImage: "xmark.circle")
                            }
                        }
                }
            }
            .background(cardBackground)
        }
    }

    private func inProgressRow(_ itemId: String) -> some View {
        let stats = downloadManager.stats[itemId]
        let fraction = downloadManager.progress[itemId] ?? 0
        let isActive = downloadManager.activeItemIds.contains(itemId) && !downloadManager.queuedItemIds.contains(itemId)
        let isPaused = downloadManager.pausedItemIds.contains(itemId)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(downloadManager.activeItemTitles[itemId] ?? "Downloading…")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(isActive ? DT.Color.textPrimary : DT.Color.textSecondary)
                    .lineLimit(1)
                Spacer()
                if let stats, stats.totalBytes > 0 {
                    Text("\(Int(fraction * 100))%")
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
                Button { downloadManager.cancelDownload(itemId: itemId) } label: {
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
                .tint(isPaused ? .orange : DT.Color.accent)
            }
            HStack {
                if let stats, stats.bytesWritten > 0, stats.totalBytes > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: stats.bytesWritten, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: stats.totalBytes, countStyle: .file))")
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
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(stats.bytesPerSecond), countStyle: .file))/s")
                }
            }
            .font(.system(.caption))
            .monospacedDigit()
            .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Continue watching

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Spacing.shelfGap) {
                    ForEach(inProgress) { item in
                        Button { play(item) } label: {
                            ContinueCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { play(item) } label: { Label("Resume", systemImage: "play.fill") }
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
                        if isSelecting { toggleSelection(id) } else { openSeries(group.seriesId, name: group.seriesName) }
                    } label: {
                        PosterTile(
                            artwork: seriesPosterURL(group.seriesId, fallback: group.episodes.first),
                            title: group.seriesName,
                            caption: "\(group.episodes.count) episode\(group.episodes.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))",
                            badge: "\(group.episodes.count)",
                            progress: nil, isWatched: group.episodes.allSatisfy(\.played),
                            selection: isSelecting ? selection.contains(id) : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !isSelecting {
                            Button { openSeries(group.seriesId, name: group.seriesName) } label: {
                                Label("Details", systemImage: "info.circle")
                            }
                            Button(role: .destructive) { pendingDeleteSeriesId = group.seriesId } label: {
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
                        if isSelecting { toggleSelection(id) } else { open(item) }
                    } label: {
                        PosterTile(
                            artwork: fileURL(item.posterFileName, in: item.itemId),
                            title: item.name,
                            caption: [item.productionYear.map(String.init), ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file)]
                                .compactMap { $0 }.joined(separator: " · "),
                            badge: nil,
                            progress: item.played || item.runtimeTicks <= 0 || item.playbackPositionTicks <= 0
                                ? nil : min(Double(item.playbackPositionTicks) / Double(item.runtimeTicks), 1),
                            isWatched: item.played,
                            selection: isSelecting ? selection.contains(id) : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !isSelecting {
                            Button { play(item) } label: {
                                Label(item.playbackPositionTicks > 0 && !item.played ? "Resume" : "Play", systemImage: "play.fill")
                            }
                            Button { open(item) } label: { Label("Details", systemImage: "info.circle") }
                            Button(role: .destructive) { pendingDelete = item } label: {
                                Label("Delete Download", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    // MARK: - Artwork

    private func fileURL(_ name: String?, in itemId: String) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return DownloadStore.directory(for: itemId).appendingPathComponent(name)
    }

    private func seriesPosterURL(_ seriesId: String, fallback: DownloadedItem?) -> URL? {
        let poster = DownloadStore.directory(for: seriesId).appendingPathComponent("poster.jpg")
        if FileManager.default.fileExists(atPath: poster.path) { return poster }
        return fallback.flatMap { fileURL($0.posterFileName, in: $0.itemId) }
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
            parts.append("\(max(Int(Double(item.runtimeTicks - item.playbackPositionTicks) / 600_000_000), 1)) min left")
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
