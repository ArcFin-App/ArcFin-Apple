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
            .alert("Delete this download?", isPresented: $model.showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    model.deleteOnClose = .delete
                    dismiss()
                }
                if downloadManager.smartIgnoreTarget(itemId: item.itemId) != nil {
                    Button("Delete & Ignore in Smart Downloads", role: .destructive) {
                        model.deleteOnClose = .deleteAndIgnore
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onDisappear { model.pageClosed(item, downloadManager: downloadManager) }
    }
}
