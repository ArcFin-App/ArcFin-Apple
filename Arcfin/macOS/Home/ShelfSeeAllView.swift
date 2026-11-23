// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

struct ShelfSeeAllView: View {
    let title: String
    let items: [MediaItem]
    var isLandscape: Bool = false
    var query: ShelfQuery? = nil

    @State private var selectedItem: MediaItem?

    // Fixed 2/3-up columns leave a resizable Mac window either cramped or with cards
    // stretched absurdly wide — adaptive reflows the grid as the window resizes instead.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: isLandscape ? 280 : 150), spacing: 16)]
    }

    var body: some View {
        ShelfSeeAllGrid(items: items, isLandscape: isLandscape, columns: columns, query: query) { selectedItem = $0 }
            .navigationTitle(title)
            // Self-contained rather than relying on an ancestor's navigationDestination(for:) —
            // a NavigationLink pushed from a view that itself was pushed via
            // navigationDestination(item:) could silently fail to navigate until popping back.
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
    }
}
