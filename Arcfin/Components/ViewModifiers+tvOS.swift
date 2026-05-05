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

    // Accent ring + glow on focus. No scale — cards manage their own scale.
    func tvFocusRing(cornerRadius: CGFloat = DT.Radius.md) -> some View {
#if os(tvOS)
        self.modifier(TVFocusRingModifier(cornerRadius: cornerRadius))
#else
        self
#endif
    }

    func tvListRow() -> some View {
#if os(tvOS)
        self
            .listRowBackground(Color.clear)
            .focusEffectDisabled()
#else
        self
#endif
    }
}

#if os(tvOS)
// Accent ring + glow only. No scaleEffect — avoids "out padding" on full-width buttons.
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
            .shadow(color: isFocused ? DT.Color.accent.opacity(0.45) : .clear, radius: 10)
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }
}

// For shelf NavigationLinks — passes label through with no system transforms.
struct TVCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// For inline text buttons (See All, etc.).
// Shows accent fill only on focus; completely invisible at rest.
struct TVFocusButtonLabel: View {
    let title: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .font(.system(size: 10 * DT.Scale.font, weight: .semibold))
            .foregroundStyle(isFocused ? .white : DT.Color.textSecondary)
            .padding(.horizontal, 10 * DT.Scale.font)
            .padding(.vertical, 4 * DT.Scale.font)
            .background(Capsule().fill(isFocused ? DT.Color.accent : Color.clear))
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }
}

// For hero action buttons (Play, More Info).
// No visible background at rest; accent or glass fill on focus.
struct TVHeroButtonLabel: View {
    let icon: String
    let text: String
    var isPrimary: Bool = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12 * DT.Scale.font))
            Text(text)
                .font(.system(size: 14 * DT.Scale.font, weight: isPrimary ? .bold : .semibold))
        }
        .foregroundStyle(isFocused ? .white : Color.white.opacity(0.65))
        .padding(.horizontal, (isPrimary ? 28 : 20) * DT.Scale.font)
        .padding(.vertical, 11 * DT.Scale.font)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isFocused
                    ? (isPrimary ? AnyShapeStyle(DT.Color.accent) : AnyShapeStyle(Color.white.opacity(0.2)))
                    : AnyShapeStyle(Color.clear))
        )
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)
    }
}

// Place INSIDE a NavigationLink/Button label in a List row.
struct TVFocusRowLabel<Content: View>: View {
    var cornerRadius: CGFloat = DT.Radius.md
    @ViewBuilder let content: () -> Content
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isFocused ? DT.Color.accent.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? DT.Color.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }
}
#endif
