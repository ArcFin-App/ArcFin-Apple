// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A shelf's See All.
struct ShelfSeeAllButton: View {
    let action: () -> Void

    var body: some View {
        Button("See All", action: action)
            .buttonStyle(.plain)
            .contentFont(.caption2, design: .default, weight: .semibold)
            .foregroundStyle(DT.Color.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            // Untinted: tint is kept for the page's main action, not every shelf's.
            .glassEffect(.regular.interactive(), in: .capsule)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

extension View {
    /// The capsule behind a shelf's count.
    func shelfBadgeBackground() -> some View {
        // A count, not a control: no glass in the content layer.
        background(Capsule().fill(DT.Color.accent.opacity(0.3)))
    }
}
