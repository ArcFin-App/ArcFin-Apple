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

    private var series: DownloadedSeries? { DownloadedSeriesDetailModel.series(seriesId, in: allSeries) }
    private var episodes: [DownloadedItem] { DownloadedSeriesDetailModel.episodes(of: seriesId, in: allItems) }

    var body: some View {
        List {
            Section {
                DownloadedSeriesHeader(seriesId: seriesId, model: model, series: series, episodes: episodes)
            }
            .listRowInsets(EdgeInsets())

            Section {
                ForEach(model.episodesInSelectedSeason(of: episodes)) { episode in
                    Button {
                        model.play(episode, startOverride: nil)
                    } label: {
                        DownloadedEpisodeRowContent(episode: episode)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .detailPageBackground(tint: model.heroTint)
        .ignoresSafeArea(edges: .top)
        .task(id: seriesId) {
            await model.loadHeroTint(seriesId: seriesId, series: series)
        }
        .navigationTitle("")
        .onAppear {
            if model.selectedSeason == nil { model.selectedSeason = DownloadedSeriesDetailModel.seasonNumbers(of: episodes).first }
        }
        .alert("Delete this episode?", isPresented: Binding(
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
        .alert(model.selection.count == 1 ? "Delete 1 selected episode?" : "Delete \(model.selection.count) selected episodes?",
               isPresented: $model.showBulkDeleteConfirm) {
            Button("Delete", role: .destructive) { model.deleteSelection(of: episodes, downloadManager: downloadManager) }
            Button("Cancel", role: .cancel) {}
        }
    }
}
