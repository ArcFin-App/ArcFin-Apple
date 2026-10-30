// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A shelf's See All.
struct ShelfSeeAllButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TVFocusButtonLabel(title: "See All")
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
    }
}

extension View {
    /// The capsule behind a shelf's count.
    func shelfBadgeBackground() -> some View {
        background(Capsule().fill(DT.Color.accent.opacity(0.3)))
            .overlay(Capsule().stroke(DT.Color.accent.opacity(0.5), lineWidth: 1))
    }
}
