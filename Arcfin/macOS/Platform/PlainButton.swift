// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// A button with no chrome of its own: plain (or pressable) for touch and pointer, and on
    /// tvOS, where the app turns off the system focus effect, a focus ring so it shows focus.
    @ViewBuilder
    /// `ring: false` leaves the ring to the label (`tvLabelFocusRing`); `prominent: false`
    /// keeps wide rows from growing past their column when focused.
    func arcfinPlainButton(cornerRadius: CGFloat = DT.Radius.md, pressable: Bool = false,
                           ring: Bool = true, prominent: Bool = true) -> some View {
        if pressable {
            buttonStyle(PressableButtonStyle())
        } else {
            buttonStyle(.plain)
        }
    }
}
