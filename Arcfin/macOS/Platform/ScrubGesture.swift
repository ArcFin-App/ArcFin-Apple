// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Drags along a scrubber `width` wide, reporting how far along (0 to 1) it is.
    func onScrub(width: CGFloat, changed: @escaping (Double) -> Void, ended: @escaping () -> Void) -> some View {
        // A plain DragGesture works with a mouse drag on macOS same as a touch drag
        // on iOS — no UIKit dependency, so this isn't restricted to canImport(UIKit).
        gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    changed(min(max(value.location.x / width, 0), 1))
                }
                .onEnded { _ in ended() }
        )
    }
}
