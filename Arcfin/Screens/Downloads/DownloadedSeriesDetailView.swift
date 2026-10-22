// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence
#if os(macOS)
import AppKit
#endif

/// Series container detail for downloads — mirrors MediaDetailView's shape (backdrop,
/// overview, season picker, episode list) but only ever shows what's actually downloaded:
/// seasons with zero downloaded episodes never appear in the picker at all.
struct DownloadedSeriesDetailView: View {
    let seriesId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(DownloadManager.self) private var downloadManager
    @Query private var allSeries: [DownloadedSeries]
    @Query(sort: [SortDescriptor(\DownloadedItem.seasonNumber), SortDescriptor(\DownloadedItem.episodeNumber)])
    private var allItems: [DownloadedItem]

    @State private var selectedSeason: Int?
    @State private var playingItem: DownloadedItem?
    @State private var playStartOverride: Int64?
    @State private var pendingDelete: DownloadedItem?
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #elseif os(macOS)
    @State private var isSelectingMac = false
    #endif
    @State private var selection = Set<String>()
    @State private var showBulkDeleteConfirm = false
    @State private var heroTint: Color?

    private var series: DownloadedSeries? { allSeries.first { $0.seriesId == seriesId } }
    private var episodes: [DownloadedItem] { allItems.filter { $0.seriesId == seriesId } }
    private var seasonNumbers: [Int] { Array(Set(episodes.compactMap(\.seasonNumber))).sorted() }
    private var episodesInSelectedSeason: [DownloadedItem] {
        episodes.filter { $0.seasonNumber == selectedSeason }
    }

    private var dir: URL { DownloadStore.directory(for: seriesId) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    backdrop

                    VStack(alignment: .leading, spacing: DT.Spacing.md) {
                        HStack(spacing: 8) {
                            Text("Series")
                                .font(.system(.caption2, design: .default, weight: .semibold))
                                .foregroundStyle(DT.Color.textSecondary)
                            if let year = series?.productionYear {
                                Text("· \(String(year))")
                                    .font(.system(.caption2))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                            if let rating = series?.communityRating, rating > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill").font(.system(.caption2))
                                    Text(String(format: "%.1f", rating))
                                }
                                .font(.system(.caption2))
                                .foregroundStyle(Color(hex: "f59e0b"))
                            }
                        }

                        if let genres = series?.genres, !genres.isEmpty {
                            Text(genres.joined(separator: " · "))
                                .font(.system(.caption))
                                .foregroundStyle(DT.Color.textSecondary)
                        }

                        if let overview = series?.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(.footnote))
                                .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                                .lineSpacing(3)
                        }

                        if seasonNumbers.count > 1 {
                            seasonPicker
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.top, DT.Spacing.md)
                }
            }
            .listRowInsets(EdgeInsets())
            #if os(iOS)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            #endif

            Section {
                ForEach(episodesInSelectedSeason) { episode in
                    episodeRow(episode)
                }
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        #endif
        .detailPageBackground(tint: heroTint)
        .ignoresSafeArea(edges: .top)
        .task(id: seriesId) {
            if let url = heroURL { heroTint = await AverageColor.load(from: url) }
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .toolbar {
            #if os(iOS)
            if editMode.isEditing && !selection.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete (\(selection.count))", role: .destructive) {
                        showBulkDeleteConfirm = true
                    }
                }
            }
            if !episodes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        editMode = editMode.isEditing ? .inactive : .active
                        selection.removeAll()
                    }
                }
            }
            #elseif os(macOS)
            if isSelectingMac && !selection.isEmpty {
                ToolbarItem {
                    Button("Delete (\(selection.count))", role: .destructive) {
                        showBulkDeleteConfirm = true
                    }
                }
            }
            if !episodes.isEmpty {
                ToolbarItem {
                    Button(isSelectingMac ? "Done" : "Select") {
                        isSelectingMac.toggle()
                        selection.removeAll()
                    }
                }
            }
            #endif
        }
        .onAppear {
            if selectedSeason == nil { selectedSeason = seasonNumbers.first }
        }
        #if os(iOS)
        .fullScreenCover(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item, startPositionOverride: playStartOverride)
        }
        #elseif os(macOS)
        // fullScreenCover is unavailable on macOS — OfflinePlayerView has its own in-window
        // fullscreen (F key) now that it has a real macOS video surface, so a sheet is enough.
        .sheet(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item, startPositionOverride: playStartOverride)
                .frame(minWidth: 900, minHeight: 560)
        }
        #endif
        .alert("Delete this episode?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { downloadManager.deleteDownload(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .alert("Delete \(selection.count) selected episode\(selection.count == 1 ? "" : "s")?", isPresented: $showBulkDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteSelection() {
        let toDelete = episodes.filter { selection.contains($0.itemId) }
        downloadManager.deleteDownloads(toDelete)
        selection.removeAll()
        #if os(iOS)
        editMode = .inactive
        #elseif os(macOS)
        isSelectingMac = false
        #endif
    }

    private func fileURL(_ name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return dir.appendingPathComponent(name)
    }

    private var heroURL: URL? { fileURL(series?.backdropFileName) ?? fileURL(series?.posterFileName) }

    /// The same hero and poster-and-title block as a show's page online.
    private var backdrop: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeroBackdrop(url: heroURL)
            HStack(alignment: .bottom, spacing: 14) {
                CachedAsyncImage(url: fileURL(series?.posterFileName)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: DT.Color.backgroundSecondary
                    }
                }
                .frame(width: 90, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(series?.name ?? episodes.first?.seriesName ?? "Show")
                        .font(.system(.title3, weight: .heavy))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(3)
                    Label("\(episodes.count) episode\(episodes.count == 1 ? "" : "s") downloaded", systemImage: "arrow.down.circle.fill")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, -60)
        }
    }

    private var seasonPicker: some View {
        Menu {
            ForEach(seasonNumbers, id: \.self) { season in
                Button("Season \(String(season))") { selectedSeason = season }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedSeason.map { "Season \(String($0))" } ?? "Season")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
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
    private func episodeRow(_ episode: DownloadedItem) -> some View {
        #if os(iOS) || os(macOS)
        if isSelecting {
            Button { toggleSelection(episode.itemId) } label: {
                HStack(spacing: 12) {
                    selectionIndicator(episode.itemId)
                    episodeRowContent(episode)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button {
                playStartOverride = nil
                playingItem = episode
            } label: {
                episodeRowContent(episode)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu(menuItems: {
                if episode.playbackPositionTicks > 0 && !episode.played {
                    Button {
                        playStartOverride = 0
                        playingItem = episode
                    } label: {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                    }
                }
                Button(role: .destructive) { pendingDelete = episode } label: {
                    Label("Delete Download", systemImage: "trash")
                }
            }, preview: {
                episodeRowPreview(episode)
            })
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDelete = episode } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        #else
        Button {
            playStartOverride = nil
            playingItem = episode
        } label: {
            episodeRowContent(episode)
        }
        .buttonStyle(.plain)
        #endif
    }

    private func episodeRowContent(_ episode: DownloadedItem) -> some View {
        HStack(spacing: 12) {
            episodeThumbnail(episode)
            VStack(alignment: .leading, spacing: 3) {
                Text(episodeLabel(episode))
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                Text(episode.name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: episode.fileSizeBytes, countStyle: .file))
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            Image(systemName: episode.played ? "checkmark.circle.fill" : "play.circle")
                .font(.system(.title3))
                .foregroundStyle(episode.played ? Color(hex: "10b981") : DT.Color.textSecondary)
        }
    }

    private func episodeRowPreview(_ episode: DownloadedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                #if canImport(UIKit)
                if let fileName = episode.posterFileName,
                   let uiImage = UIImage(contentsOfFile: DownloadStore.directory(for: episode.itemId).appendingPathComponent(fileName).path) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    DT.Color.backgroundSecondary
                }
                #elseif os(macOS)
                if let fileName = episode.posterFileName,
                   let nsImage = NSImage(contentsOfFile: DownloadStore.directory(for: episode.itemId).appendingPathComponent(fileName).path) {
                    Image(nsImage: nsImage).resizable().scaledToFill()
                } else {
                    DT.Color.backgroundSecondary
                }
                #else
                DT.Color.backgroundSecondary
                #endif
            }
            .frame(width: 240, height: 135)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(episode.name)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 240, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }

    private func episodeThumbnail(_ episode: DownloadedItem) -> some View {
        Group {
            #if canImport(UIKit)
            if let fileName = episode.posterFileName,
               let uiImage = UIImage(contentsOfFile: DownloadStore.directory(for: episode.itemId).appendingPathComponent(fileName).path) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #elseif os(macOS)
            if let fileName = episode.posterFileName,
               let nsImage = NSImage(contentsOfFile: DownloadStore.directory(for: episode.itemId).appendingPathComponent(fileName).path) {
                Image(nsImage: nsImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #else
            DT.Color.backgroundSecondary
            #endif
        }
        .frame(width: 80, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private func episodeLabel(_ episode: DownloadedItem) -> String {
        let s = episode.seasonNumber.map { "S\($0)" } ?? ""
        let e = episode.episodeNumber.map { "E\($0)" } ?? ""
        return s + e
    }
}
