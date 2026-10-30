// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence

/// Series container detail for downloads — mirrors MediaDetailView's shape (backdrop,
/// overview, season picker, episode list) but only ever shows what's actually downloaded:
/// seasons with zero downloaded episodes never appear in the picker at all.
struct DownloadedSeriesDetailView: View {
    let seriesId: String

    @Environment(DownloadManager.self) private var downloadManager
    @Query private var allSeries: [DownloadedSeries]
    @Query(sort: [SortDescriptor(\DownloadedItem.seasonNumber), SortDescriptor(\DownloadedItem.episodeNumber)])
    private var allItems: [DownloadedItem]

    @State private var model = DownloadedSeriesDetailModel()
    @State private var editMode: EditMode = .inactive

    private var series: DownloadedSeries? { DownloadedSeriesDetailModel.series(seriesId, in: allSeries) }
    private var episodes: [DownloadedItem] { DownloadedSeriesDetailModel.episodes(of: seriesId, in: allItems) }

    var body: some View {
        List {
            Section {
                DownloadedSeriesHeader(seriesId: seriesId, model: model, series: series, episodes: episodes)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                ForEach(model.episodesInSelectedSeason(of: episodes)) { episode in
                    episodeRow(episode)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .detailPageBackground(tint: model.heroTint)
        .ignoresSafeArea(edges: .top)
        .task(id: seriesId) {
            await model.loadHeroTint(seriesId: seriesId, series: series)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if editMode.isEditing && !model.selection.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Delete (\(model.selection.count))", role: .destructive) {
                        model.showBulkDeleteConfirm = true
                    }
                }
            }
            if !episodes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        editMode = editMode.isEditing ? .inactive : .active
                        model.selection.removeAll()
                    }
                }
            }
        }
        .onAppear {
            if model.selectedSeason == nil { model.selectedSeason = DownloadedSeriesDetailModel.seasonNumbers(of: episodes).first }
        }
        .fullScreenCover(item: $model.playingItem) { item in
            OfflinePlayerView(downloadedItem: item, startPositionOverride: model.playStartOverride)
        }
        .alert("Delete this episode?", isPresented: Binding(
            get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete = model.pendingDelete { downloadManager.deleteDownload(pendingDelete) }
                model.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { model.pendingDelete = nil }
        }
        .alert("Delete \(model.selection.count) selected episode\(model.selection.count == 1 ? "" : "s")?", isPresented: $model.showBulkDeleteConfirm) {
            Button("Delete", role: .destructive) {
                model.deleteSelection(of: episodes, downloadManager: downloadManager)
                editMode = .inactive
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func episodeRow(_ episode: DownloadedItem) -> some View {
        if editMode.isEditing {
            Button { model.toggleSelection(episode.itemId) } label: {
                HStack(spacing: 12) {
                    DownloadedEpisodeSelectionIndicator(isSelected: model.selection.contains(episode.itemId))
                    DownloadedEpisodeRowContent(episode: episode)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.selection.contains(episode.itemId) ? .isSelected : [])
        } else {
            Button {
                model.play(episode, startOverride: nil)
            } label: {
                DownloadedEpisodeRowContent(episode: episode)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu(menuItems: {
                if episode.playbackPositionTicks > 0 && !episode.played {
                    Button {
                        model.play(episode, startOverride: 0)
                    } label: {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                    }
                }
                Button(role: .destructive) { model.pendingDelete = episode } label: {
                    Label("Delete Download", systemImage: "trash")
                }
            }, preview: {
                DownloadedEpisodeRowPreview(episode: episode)
            })
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { model.pendingDelete = episode } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
