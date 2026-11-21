// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence
import AuthCore

/// What's downloaded on this device, shown when offline mode stands in for the whole app.
/// Apple TV can't download or play a download; a title opens its page.
struct DownloadsView: View {
    /// Non-nil only when this is standing in for the whole app (offline mode) — shows a
    /// "Go Back Online" affordance and skips the normal nav chrome.
    var goBackOnline: (() -> Void)? = nil

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(AuthManager.self) private var authManager
    @Query(sort: [SortDescriptor(\DownloadedItem.downloadedAt, order: .reverse)]) private var allItems: [DownloadedItem]
    private var items: [DownloadedItem] { downloadManager.ownDownloads(allItems) }

    @State private var model = DownloadsModel()

    /// With a connection, a download opens the title's full page; offline, the saved one.
    private var isOnline: Bool { goBackOnline == nil && authManager.state.credential != nil }

    var body: some View {
        DownloadsContent(items: items, model: model, isOnline: isOnline,
                         play: { model.open($0, isOnline: isOnline, downloadManager: downloadManager) }) {
            EmptyView()
        }
        .screenBackground()
        .onAppear {
            downloadManager.removeExpiredDownloads()
            downloadManager.purgeWatchedDownloads()
        }
        .task(id: items.count) { model.refreshFreeBytes() }
        .task { if isOnline { await downloadManager.saveMissingDetails() } }
        .navigationTitle("Downloads")
        .toolbar {
            if let goBackOnline {
                ToolbarItem(placement: .primaryAction) {
                    Button("Go Back Online", action: goBackOnline)
                }
            }
        }
        .navigationDestination(item: $model.selectedItem) { item in
            DownloadedItemDetailView(item: item)
        }
        .navigationDestination(item: $model.selectedSeriesRef) { ref in
            DownloadedSeriesDetailView(seriesId: ref.seriesId)
        }
        .navigationDestination(item: $model.selectedMedia) { item in
            MediaDetailView(item: item)
        }
        .modifier(DownloadsAlerts(items: items, model: model))
    }
}
