// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

struct ShelfSeeAllView: View {
    let title: String
    let items: [MediaItem]
    var isLandscape: Bool = false

    @State private var selectedItem: MediaItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isWide: Bool { horizontalSizeClass == .regular }

    private var columns: [GridItem] {
        if isWide {
            return [GridItem(.adaptive(minimum: isLandscape ? 260 : 150), spacing: 12)]
        }
        let count = isLandscape ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        ShelfSeeAllGrid(items: items, isLandscape: isLandscape, columns: columns) { selectedItem = $0 }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // Self-contained rather than relying on an ancestor's navigationDestination(for:) —
            // a NavigationLink pushed from a view that itself was pushed via
            // navigationDestination(item:) could silently fail to navigate until popping back.
            .navigationDestination(item: $selectedItem) { item in
                MediaDetailView(item: item)
            }
    }
}
