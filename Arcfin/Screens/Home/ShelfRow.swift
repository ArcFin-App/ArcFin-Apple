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

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .glassEffect(.regular.tint(DT.Color.accent), in: .capsule)
                }

                Spacer()

                if let onSeeAll {
                    Button("See All", action: onSeeAll)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.tint(DT.Color.accent).interactive(), in: .capsule)
#if os(tvOS)
                        .focusEffectDisabled()
#endif
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.sectionGap)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Spacing.shelfGap) {
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
