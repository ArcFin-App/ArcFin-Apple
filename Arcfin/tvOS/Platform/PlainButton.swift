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
        if ring {
            buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: cornerRadius, prominent: prominent)
        } else {
            buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
        }
    }
}

// For shelf NavigationLinks — passes label through with no system transforms.
struct TVCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension View {
    /// An announcement's X: a round button sized for the remote, its ring inside the banner.
    func noticeDismissButtonStyle() -> some View {
        frame(width: 56, height: 56)
            .background(DT.Color.textPrimary.opacity(0.08), in: Circle())
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .tvFocusRing(cornerRadius: 28)
    }

    /// A form row's action. The list row is already the button here.
    func formRowButton() -> some View { self }
}
