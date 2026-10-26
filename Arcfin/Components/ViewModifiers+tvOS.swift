// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

// Toggle(_:isOn:) and Picker(_:selection:) render their string label through their own
// internal Text, which on tvOS keeps the system's default color regardless of
// foregroundStyle applied from outside the control — unreadable once the row's focus
// platter goes light. Use this as the label content (Toggle(isOn:label:) /
// Picker(selection:label:)) instead of the string convenience initializer wherever a tvOS
// row needs its text to read in the app's text color while focused. A plain, unstyled Text
// on every other platform, so call sites don't need their own platform guard.
/// `detail` is the line or two under a setting that says what it does.
struct TVRowLabelText: View {
    let title: Text
    var detail: LocalizedStringKey? = nil
#if os(tvOS)
    @Environment(\.isFocused) private var isFocused
#endif

    init(title: LocalizedStringKey, detail: LocalizedStringKey? = nil) {
        self.title = Text(title)
        self.detail = detail
    }

    init(verbatim title: String, detail: LocalizedStringKey? = nil) {
        self.title = Text(verbatim: title)
        self.detail = detail
    }

    var body: some View {
#if os(tvOS)
        VStack(alignment: .leading, spacing: 4) {
            title
                .foregroundStyle(isFocused ? Color.black : DT.Color.textPrimary)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isFocused ? Color.black.opacity(0.65) : DT.Color.textSecondary)
            }
        }
        .animation(DT.Animation.fast, value: isFocused)
#else
        VStack(alignment: .leading, spacing: 2) {
            title
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
#endif
    }
}

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

    /// Shows the view only when `isShown`, e.g. a control the profile isn't allowed to use.
    @ViewBuilder
    func shown(_ isShown: Bool) -> some View {
        if isShown { self }
    }

    /// A screen's background, always filling the whole screen. Applied straight to content
    /// that sizes itself (a spinner, an empty state, a short stack while results load), the
    /// colour only covered that content's narrow frame and the rest showed the system black
    /// until the full results arrived.
    func screenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { DT.Color.backgroundPrimary.ignoresSafeArea() }
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

    /// A button with no chrome of its own: plain (or pressable) for touch and pointer, and on
    /// tvOS, where the app turns off the system focus effect, a focus ring so it shows focus.
    @ViewBuilder
    func arcfinPlainButton(cornerRadius: CGFloat = DT.Radius.md, pressable: Bool = false) -> some View {
        #if os(tvOS)
        buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .tvFocusRing(cornerRadius: cornerRadius, prominent: true)
        #else
        if pressable {
            buttonStyle(PressableButtonStyle())
        } else {
            buttonStyle(.plain)
        }
        #endif
    }

    func tvListRow() -> some View {
#if os(tvOS)
        self
            .listRowBackground(Color.clear)
            .modifier(TVListRowFocusTextModifier())
#else
        self
#endif
    }
}

#if os(tvOS)
// Native Toggle/Picker labels don't automatically invert to a readable color against the
// system's own focus platter the way a NavigationLink/Button row's custom styling does —
// they kept rendering in the app's plain white/primary text color even while focused,
// unreadable against the light platter. Every tvListRow() row gets this for free.
private struct TVListRowFocusTextModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isFocused ? Color.black : DT.Color.textPrimary)
            .animation(DT.Animation.fast, value: isFocused)
    }
}

// Accent ring + glow only. No scaleEffect — avoids "out padding" on full-width buttons.
private struct TVFocusRingModifier: ViewModifier {
    let cornerRadius: CGFloat
    var prominent: Bool = false
    /// Set when the ring sits inside a focusable view (a button's label).
    @Environment(\.isFocused) private var ancestorFocused
    /// Set when the ring is applied to the focusable view itself, a button or a
    /// `.focusable()` card: \.isFocused only reports an ancestor's focus, so on its own
    /// it stayed false there and the ring never showed.
    @FocusState private var selfFocused: Bool

    private var isFocused: Bool { ancestorFocused || selfFocused }

    func body(content: Content) -> some View {
        content
            .focused($selfFocused)
            .focusEffectDisabled()
            .scaleEffect(prominent && isFocused ? 1.12 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: prominent ? 4 : 2)
            )
            .shadow(color: isFocused ? DT.Color.accent.opacity(prominent ? 0.6 : 0.45) : .clear, radius: prominent ? 16 : 10)
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}

// For shelf NavigationLinks — passes label through with no system transforms.
struct TVCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// For player icon-only controls (close, transport buttons). A stroke-only ring proved too
// subtle to notice on a busy, bright video background regardless of stroke width — a full
// fill flip to solid accent (with the icon itself inverting to dark) is unmistakable
// wherever it sits, which a thin outline can never guarantee.
struct TVPlayerControlLabel: View {
    let systemImage: String
    var size: CGFloat = 20
    var diameter: CGFloat = 56
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * DT.Scale.font, weight: .semibold))
            .foregroundStyle(isFocused ? DT.Color.backgroundPrimary : .white)
            .frame(width: diameter * DT.Scale.font, height: diameter * DT.Scale.font)
            .background(Circle().fill(isFocused ? DT.Color.accent : Color.white.opacity(0.16)))
            .scaleEffect(isFocused ? 1.15 : 1.0)
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}

// For inline text buttons (See All, etc.).
// Shows accent fill only on focus; completely invisible at rest.
struct TVFocusButtonLabel: View {
    let title: LocalizedStringKey
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .scaledFont(size: 10, weight: .semibold)
            .foregroundStyle(isFocused ? .white : DT.Color.textSecondary)
            .padding(.horizontal, 10 * DT.Scale.font)
            .padding(.vertical, 4 * DT.Scale.font)
            .background(Capsule().fill(isFocused ? DT.Color.accent : Color.clear))
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}

// For hero action buttons (Play, More Info).
// No visible background at rest; accent or glass fill on focus.
struct TVHeroButtonLabel: View {
    let icon: String
    let text: LocalizedStringKey
    var isPrimary: Bool = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .scaledFont(size: 12)
            Text(text)
                .scaledFont(size: 14, weight: isPrimary ? .bold : .semibold)
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
        .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)
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
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
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
                .scaledFont(size: 15)
            Text(text)
                .scaledFont(size: 15, weight: isPrimary ? .bold : .medium)
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
        .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)
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
                .scaledFont(size: 11)
                .foregroundStyle(isFocused ? .white : DT.Color.textSecondary)
                .lineLimit(4)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Read More")
                .scaledFont(size: 10, weight: .semibold)
                .foregroundStyle(DT.Color.accent)
                .opacity(isFocused ? 1 : 0)
        }
        .padding(14 * DT.Scale.font)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .fill(isFocused ? Color.white.opacity(0.08) : Color.clear)
        )
        .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}

// Scroll-target behavior that snaps to either the top (hero) or the showcase
// boundary (below-fold shelves). Pass the screen height as showcaseHeight.
struct TVFoldSnappingBehavior: ScrollTargetBehavior {
    let showcaseHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        // Only snap while transitioning between the hero and the shelves. Unconditionally
        // forcing every target to 0 or showcaseHeight meant that once scrolled (or
        // focus-scrolled) down into the shelves themselves, every settle kept getting
        // yanked back to exactly showcaseHeight — the very top of the shelves — which made
        // it impossible to reach shelves further down than the first screenful.
        guard target.rect.minY < showcaseHeight * 1.05 else { return }
        if target.rect.minY < showcaseHeight * 0.22 {
            target.rect.origin.y = 0
        } else {
            target.rect.origin.y = showcaseHeight
        }
    }
}
#endif
