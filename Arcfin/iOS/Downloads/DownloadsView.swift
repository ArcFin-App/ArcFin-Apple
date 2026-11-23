// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence
import AuthCore

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
        DownloadsContent(items: items, model: model, isOnline: isOnline, play: { model.playingItem = $0 }) {
            NavigationLink {
                StorageManagementView()
            } label: {
                Text("Manage")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(.glass)
        }
        .screenBackground()
        .onAppear {
            downloadManager.removeExpiredDownloads()
            downloadManager.purgeWatchedDownloads()
        }
        .task(id: items.count) { model.refreshFreeBytes() }
        .task { if isOnline { await downloadManager.saveMissingDetails() } }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let goBackOnline {
                ToolbarItem(placement: .primaryAction) {
                    Button("Go Back Online", action: goBackOnline)
                }
            }
            DownloadsSelectionToolbar(isOffline: goBackOnline != nil, hasItems: !items.isEmpty, model: model)
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
        .fullScreenCover(item: $model.playingItem) { item in
            PlayerView(download: item) { next in
                PlayerView.keepOrientationOnNextDisappear = true
                model.playingItem = next
            }
            .id(item.itemId)
        }
        .modifier(DownloadsAlerts(items: items, model: model))
    }
}
