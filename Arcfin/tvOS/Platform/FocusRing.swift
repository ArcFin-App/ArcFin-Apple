// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    // Accent ring + glow on focus. No scale by default — cards manage their own scale.
    // `prominent` adds its own scale bump plus a thicker/brighter ring, for small controls
    // (player buttons) that have no other focus feedback of their own and sit over a busy,
    // low-contrast video background where the plain ring alone is easy to miss.
    // Apply it to the focusable view itself: a button or a `.focusable()` view.
    func tvFocusRing(cornerRadius: CGFloat = DT.Radius.md, prominent: Bool = false) -> some View {
        self.modifier(TVFocusRingModifier(cornerRadius: cornerRadius, prominent: prominent))
    }

    /// The same ring for part of a button's label, e.g. just the artwork of a tile whose
    /// title sits underneath, so the ring hugs the picture instead of the whole label.
    func tvLabelFocusRing(cornerRadius: CGFloat = DT.Radius.md, prominent: Bool = false) -> some View {
        self.modifier(TVLabelFocusRingModifier(cornerRadius: cornerRadius, prominent: prominent))
    }

    /// On Apple TV, focusable with the ring, so the remote can reach and scroll to a view that
    /// isn't a button.
    func tvFocusable(cornerRadius: CGFloat) -> some View {
        focusable()
            .tvFocusRing(cornerRadius: cornerRadius)
    }

    /// A focus section on Apple TV.
    func tvFocusSection() -> some View {
        focusSection()
    }
}

// Accent ring + glow only. No scaleEffect — avoids "out padding" on full-width buttons.
// \.isFocused only reports a focusable ancestor's focus, so applied to the focusable view
// itself it stays false (or lights up for an enclosing focusable card): the view's own
// focus comes from @FocusState instead.
private struct TVFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    var prominent: Bool = false
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .modifier(TVFocusRingDrawing(cornerRadius: cornerRadius, prominent: prominent, isFocused: isFocused))
            .focused($isFocused)
    }
}

private struct TVLabelFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    var prominent: Bool = false
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.modifier(TVFocusRingDrawing(cornerRadius: cornerRadius, prominent: prominent, isFocused: isFocused))
    }
}

// The ring and glow are drawn before the scale, so they grow with the view and stay on its edge.
private struct TVFocusRingDrawing: ViewModifier {
    let cornerRadius: CGFloat
    let prominent: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: prominent ? 4 : 2)
            )
            .shadow(color: isFocused ? DT.Color.accent.opacity(prominent ? 0.6 : 0.45) : .clear, radius: prominent ? 16 : 10)
            .scaleEffect(prominent && isFocused ? 1.12 : 1.0)
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}
