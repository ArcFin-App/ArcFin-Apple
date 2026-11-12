// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence

struct StorageManagementView: View {
    @Query(sort: [SortDescriptor(\DownloadedItem.downloadedAt, order: .reverse)]) private var items: [DownloadedItem]

    var body: some View {
        StorageManagementContent(items: items)
            .arcfinNavTitleLarge("Manage Storage")
    }
}

#Preview {
    NavigationStack { StorageManagementView() }
}
