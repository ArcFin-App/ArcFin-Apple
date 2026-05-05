import SwiftUI

extension View {
    @ViewBuilder
    func arcfinListStyle() -> some View {
#if os(tvOS)
        self.listStyle(.plain)
#else
        self.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
#endif
    }

    @ViewBuilder
    func arcfinNavTitleLarge(_ title: String) -> some View {
#if os(tvOS)
        self.navigationTitle(title)
#else
        self.navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
#endif
    }

    @ViewBuilder
    func arcfinRowSeparatorHidden() -> some View {
#if os(tvOS)
        self
#else
        self.listRowSeparator(.hidden)
#endif
    }

    // Replaces ultraThinMaterial + white overlay — tvOS material renders light/white
    @ViewBuilder
    func arcfinFieldBackground() -> some View {
#if os(tvOS)
        self.background(DT.Color.backgroundSecondary)
#else
        self
            .background(.white.opacity(0.06))
            .background(.ultraThinMaterial)
#endif
    }

    // Replaces the tvOS default white focus highlight with an accent ring.
    // Use on standalone buttons/cards outside of a List.
    func tvFocusRing(cornerRadius: CGFloat = DT.Radius.md) -> some View {
#if os(tvOS)
        self.modifier(TVFocusRingModifier(cornerRadius: cornerRadius))
#else
        self
#endif
    }

    // Use on List rows (NavigationLink, Button, Link).
    // Disables the system white pill and substitutes an accent-tinted background.
    func tvListRow() -> some View {
#if os(tvOS)
        self
            .listRowBackground(TVFocusBackground())
            .focusEffectDisabled()
#else
        self
#endif
    }
}

#if os(tvOS)
private struct TVFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 2)
            )
            .shadow(color: isFocused ? DT.Color.accent.opacity(0.35) : .clear, radius: 8)
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }
}

// Background view used by tvListRow() — reads focus state from the list row context.
struct TVFocusBackground: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        RoundedRectangle(cornerRadius: DT.Radius.md)
            .fill(isFocused ? DT.Color.accent.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.md)
                    .stroke(isFocused ? DT.Color.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }
}
#endif
