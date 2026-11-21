// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct ShelfRow<Content: View>: View {
    let title: Text
    var badge: Text? = nil
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    /// A literal title is looked up in the String Catalog, as `Text` does.
    init(title: LocalizedStringKey, badge: LocalizedStringKey? = nil, onSeeAll: (() -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = Text(title)
        self.badge = badge.map { Text($0) }
        self.onSeeAll = onSeeAll
        self.content = content
    }

    /// A name, or text that's already localized, shown as it is.
    init<S: StringProtocol>(title: S, onSeeAll: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = Text(title)
        self.onSeeAll = onSeeAll
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                title
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.2)
                    .accessibilityAddTraits(.isHeader)

                if let badge {
                    badge
                        .contentFont(.caption2, design: .default, weight: .bold)
                        .tracking(0.5)
                        .foregroundStyle(DT.Color.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .shelfBadgeBackground()
                }

                Spacer()

                if let onSeeAll {
                    ShelfSeeAllButton(action: onSeeAll)
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
                .tvFocusSection()
            }
            .shelfScrollButtons()
        }
        .padding(.bottom, DT.Spacing.lg)
        .tvFocusSection()
    }
}

#Preview {
    ZStack {
        DT.Color.backgroundPrimary.ignoresSafeArea()
        ShelfRow(title: "Continue Watching", badge: "NEW", onSeeAll: {}) {
            ForEach(0..<4) { _ in
                PosterCard(title: "Severance", subtitle: "S2 E7", progress: 0.6)
            }
        }
    }
}
