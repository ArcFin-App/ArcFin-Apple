// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence

struct DownloadedItemDetailView: View {
    let item: DownloadedItem

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var model = DownloadedItemDetailModel()

    var body: some View {
        DownloadedItemDetailPage(item: item, model: model)
            .task(id: item.itemId) { await model.load(item, downloadManager: downloadManager) }
            // fullScreenCover is unavailable on macOS — OfflinePlayerView has its own in-window
            // fullscreen (F key) now that it has a real macOS video surface, so a sheet is enough.
            .sheet(item: $model.playingItem) { item in
                OfflinePlayerView(downloadedItem: item, startPositionOverride: model.startOverride)
                    .frame(minWidth: 900, minHeight: 560)
            }
            .alert("Delete this download?", isPresented: $model.showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    downloadManager.deleteDownload(item)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}
