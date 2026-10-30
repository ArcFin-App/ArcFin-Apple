// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct OnboardingPage {
    enum Art {
        case logo
        case symbol(String)
    }

    let art: Art
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var highlights: [(icon: String, text: LocalizedStringResource)] = []
}

/// One page of the tour on iPhone, iPad and Mac: the art, the title and message, and the
/// highlights in a card underneath.
struct OnboardingPageContent: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: DT.Spacing.lg) {
            PageArt(art: page.art)
            VStack(spacing: DT.Spacing.sm) {
                Text(page.title)
                    .scaledFont(size: 30, weight: .bold)
                    .foregroundStyle(DT.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(page.message)
                    .scaledFont(size: 17)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !page.highlights.isEmpty {
                VStack(alignment: .leading, spacing: DT.Spacing.md) {
                    ForEach(Array(page.highlights.enumerated()), id: \.offset) { _, highlight in
                        HStack(alignment: .firstTextBaseline, spacing: DT.Spacing.sm) {
                            Image(systemName: highlight.icon)
                                .foregroundStyle(DT.Color.accent)
                                .frame(width: 28 * DT.Scale.font)
                                .accessibilityHidden(true)
                            Text(highlight.text)
                                .foregroundStyle(DT.Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .scaledFont(size: 16)
                    }
                }
                .padding(DT.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.Color.backgroundSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
            }
        }
    }
}

struct PageArt: View {
    let art: OnboardingPage.Art
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            IntroductionGlow(size: size * 2.2)
            switch art {
            case .logo:
                Image("ArcfinLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                    .shadow(color: DT.Color.accent.opacity(0.45), radius: 30)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: size, height: size)
                    .glassEffect(.regular.tint(DT.Color.accent.opacity(0.12)), in: .circle)
            }
        }
        .frame(height: size * 1.25)
        .accessibilityHidden(true)
    }
}

/// Where the reader is in the tour, read out as "Page 2 of 7".
struct PageDots: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 8 * DT.Scale.font) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? DT.Color.accent : DT.Color.textPrimary.opacity(0.2))
                    .frame(width: (dot == index ? 22 : 8) * DT.Scale.font, height: 8 * DT.Scale.font)
            }
        }
        .animation(DT.Animation.fast, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
    }
}
