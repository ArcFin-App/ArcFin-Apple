// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    @ViewBuilder
    func arcfinListStyle() -> some View {
#if os(tvOS)
        self.listStyle(.plain)
#elseif os(iOS)
        self.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
#else
        // Settings Lists were stretching full window width on macOS — every row's
        // label/value pair spread edge to edge instead of reading as a compact form.
        self.scrollContentBackground(.hidden)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
#endif
    }

    @ViewBuilder
    func arcfinNavTitleLarge(_ title: String) -> some View {
#if os(iOS)
        self.navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
#else
        self.navigationTitle(title)
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

    // Accent ring + glow on focus. No scale by default — cards manage their own scale.
    // `prominent` adds its own scale bump plus a thicker/brighter ring, for small controls
    // (player buttons) that have no other focus feedback of their own and sit over a busy,
    // low-contrast video background where the plain ring alone is easy to miss.
    func tvFocusRing(cornerRadius: CGFloat = DT.Radius.md, prominent: Bool = false) -> some View {
#if os(tvOS)
        self.modifier(TVFocusRingModifier(cornerRadius: cornerRadius, prominent: prominent))
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
    var prominent: Bool = false
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .scaleEffect(prominent && isFocused ? 1.12 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: prominent ? 4 : 2)
            )
            .shadow(color: isFocused ? DT.Color.accent.opacity(prominent ? 0.6 : 0.45) : .clear, radius: prominent ? 16 : 10)
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
// Uses neutral white fill — matches tvOS system convention, avoids accent-colored rings on rows.
struct TVFocusRowLabel<Content: View>: View {
    var cornerRadius: CGFloat = DT.Radius.md
    @ViewBuilder let content: () -> Content
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        content()
            .foregroundStyle(isFocused ? Color.black : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isFocused ? Color.white.opacity(0.92) : Color.clear)
            )
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }
}

// Full-width action button for the TVMediaDetailView action column.
// Has a visible rest state (dimmed) and brightens/scales on focus.
struct TVDetailButtonLabel: View {
    let icon: String
    let text: String
    var isPrimary: Bool = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15 * DT.Scale.font))
            Text(text)
                .font(.system(size: 15 * DT.Scale.font, weight: isPrimary ? .bold : .medium))
        }
        .foregroundStyle(
            isFocused
                ? (isPrimary ? DT.Color.backgroundPrimary : .white)
                : .white.opacity(0.9)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13 * DT.Scale.font)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .fill(isFocused
                    ? (isPrimary ? AnyShapeStyle(DT.Color.accent) : AnyShapeStyle(Color.white.opacity(0.3)))
                    : AnyShapeStyle(Color.white.opacity(isPrimary ? 0.15 : 0.08)))
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)
    }
}

// Tappable description block. Shows truncated text at rest, highlights on focus,
// adds "Read more" hint when focused so the user knows it's interactive.
struct TVDescriptionLabel: View {
    let text: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 11 * DT.Scale.font))
                .foregroundStyle(isFocused ? .white : DT.Color.textSecondary)
                .lineLimit(4)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Read more")
                .font(.system(size: 10 * DT.Scale.font, weight: .semibold))
                .foregroundStyle(DT.Color.accent)
                .opacity(isFocused ? 1 : 0)
        }
        .padding(14 * DT.Scale.font)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .fill(isFocused ? Color.white.opacity(0.08) : Color.clear)
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }
}

// Scroll-target behavior that snaps to either the top (hero) or the showcase
// boundary (below-fold shelves). Pass the screen height as showcaseHeight.
struct TVFoldSnappingBehavior: ScrollTargetBehavior {
    let showcaseHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        if target.rect.minY < showcaseHeight * 0.22 {
            target.rect.origin.y = 0
        } else {
            target.rect.origin.y = showcaseHeight
        }
    }
}
#endif
