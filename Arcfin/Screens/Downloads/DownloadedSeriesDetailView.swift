import SwiftUI
import SwiftData
import Persistence

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
    #endif
    @State private var selection = Set<String>()
    @State private var showBulkDeleteConfirm = false

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
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DT.Color.textSecondary)
                            if let year = series?.productionYear {
                                Text("· \(String(year))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                            Text("· \(episodes.count) episode\(episodes.count == 1 ? "" : "s") downloaded")
                                .font(.system(size: 11))
                                .foregroundStyle(DT.Color.textSecondary)
                            if let rating = series?.communityRating, rating > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "star.fill").font(.system(size: 9))
                                    Text(String(format: "%.1f", rating))
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(Color(hex: "f59e0b"))
                            }
                        }

                        if let genres = series?.genres, !genres.isEmpty {
                            Text(genres.joined(separator: " · "))
                                .font(.system(size: 12))
                                .foregroundStyle(DT.Color.textSecondary)
                        }

                        if let overview = series?.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 13))
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
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
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
            #endif
        }
        .onAppear {
            if selectedSeason == nil { selectedSeason = seasonNumbers.first }
        }
        #if os(iOS)
        .fullScreenCover(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item, startPositionOverride: playStartOverride)
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
        #endif
    }

    private var backdrop: some View {
        ZStack(alignment: .bottomLeading) {
            #if canImport(UIKit)
            if let fileName = series?.backdropFileName ?? series?.posterFileName,
               let uiImage = UIImage(contentsOfFile: dir.appendingPathComponent(fileName).path) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #else
            DT.Color.backgroundSecondary
            #endif
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            Text(series?.name ?? episodes.first?.seriesName ?? "Show")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(DT.Spacing.pagePad)
                .shadow(color: .black.opacity(0.6), radius: 6)
        }
        .frame(height: 220)
        .clipped()
    }

    private var seasonPicker: some View {
        Menu {
            ForEach(seasonNumbers, id: \.self) { season in
                Button("Season \(String(season))") { selectedSeason = season }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedSeason.map { "Season \(String($0))" } ?? "Season")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    #if os(iOS)
    private func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func selectionIndicator(_ id: String) -> some View {
        Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .foregroundStyle(selection.contains(id) ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
    }
    #endif

    @ViewBuilder
    private func episodeRow(_ episode: DownloadedItem) -> some View {
        #if os(iOS)
        if editMode.isEditing {
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
            .contextMenu {
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
            }
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                Text(episode.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: episode.fileSizeBytes, countStyle: .file))
                    .font(.system(size: 10))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.7))
            }
            Spacer()
            Image(systemName: episode.played ? "checkmark.circle.fill" : "play.circle")
                .font(.system(size: 20))
                .foregroundStyle(episode.played ? Color(hex: "10b981") : DT.Color.textSecondary)
        }
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
