// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence

struct StorageManagementView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Query(sort: [SortDescriptor(\DownloadedItem.downloadedAt, order: .reverse)]) private var allItems: [DownloadedItem]
    private var items: [DownloadedItem] { downloadManager.ownDownloads(allItems) }

    var body: some View {
        StorageManagementContent(items: items)
            .arcfinNavTitleLarge("Manage Storage")
    }
}

#Preview {
    NavigationStack { StorageManagementView() }
}
