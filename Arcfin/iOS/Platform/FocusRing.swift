// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    // Accent ring + glow on focus, on Apple TV only. No scale by default — cards manage their own scale.
    // `prominent` adds its own scale bump plus a thicker/brighter ring, for small controls
    // (player buttons) that have no other focus feedback of their own and sit over a busy,
    // low-contrast video background where the plain ring alone is easy to miss.
    // Apply it to the focusable view itself: a button or a `.focusable()` view.
    func tvFocusRing(cornerRadius: CGFloat = DT.Radius.md, prominent: Bool = false) -> some View {
        self
    }

    /// The same ring for part of a button's label, e.g. just the artwork of a tile whose
    /// title sits underneath, so the ring hugs the picture instead of the whole label.
    func tvLabelFocusRing(cornerRadius: CGFloat = DT.Radius.md, prominent: Bool = false) -> some View {
        self
    }

    /// On Apple TV, focusable with the ring, so the remote can reach and scroll to a view that
    /// isn't a button.
    func tvFocusable(cornerRadius: CGFloat) -> some View {
        self
    }

    /// A focus section on Apple TV.
    func tvFocusSection() -> some View {
        self
    }
}
