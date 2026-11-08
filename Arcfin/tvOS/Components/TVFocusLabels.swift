// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

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
    let text: LocalizedStringKey
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
