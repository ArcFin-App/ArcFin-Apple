// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct ShelfRow<Content: View>: View {
    var title: String
    var badge: String? = nil
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.2)
                    .accessibilityAddTraits(.isHeader)

                if let badge {
                    Text(badge)
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
#if os(tvOS)
                        .background(Capsule().fill(DT.Color.accent.opacity(0.3)))
                        .overlay(Capsule().stroke(DT.Color.accent.opacity(0.5), lineWidth: 1))
#else
                        // A count, not a control: no glass in the content layer.
                        .background(Capsule().fill(DT.Color.accent.opacity(0.3)))
#endif
                }

                Spacer()

                if let onSeeAll {
#if os(tvOS)
                    Button(action: onSeeAll) {
                        TVFocusButtonLabel(title: "See All")
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
#else
                    Button("See All", action: onSeeAll)
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        // Untinted: tint is kept for the page's main action, not every shelf's.
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
#endif
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.sectionGap)

            ScrollView(.horizontal, showsIndicators: false) {
                // Lazy: a plain HStack built every cell (and fired every cell's AsyncImage
                // request) the instant the shelf appeared, regardless of scroll position —
                // on a title/shelf with many items this saturated AsyncImage's shared
                // URLSession all at once and caused the whole burst to fail together under
                // any network degradation.
                LazyHStack(spacing: DT.Spacing.shelfGap) {
                    content()
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#if os(tvOS)
                .focusSection()
#endif
            }
        }
        .padding(.bottom, DT.Spacing.lg)
#if os(tvOS)
        .focusSection()
#endif
    }
}

#Preview {
    ZStack {
        DT.Color.backgroundPrimary.ignoresSafeArea()
        ShelfRow(title: "Continue Watching", badge: "5", onSeeAll: {}) {
            ForEach(0..<4) { _ in
                PosterCard(title: "Severance", subtitle: "S2 E7", progress: 0.6)
            }
        }
    }
}
