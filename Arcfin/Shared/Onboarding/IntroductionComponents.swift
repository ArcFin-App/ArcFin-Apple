// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct WhatsNewItem {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
}

/// The app icon, "What's New in Arcfin" and the version, at the top of the card.
struct WhatsNewHeader: View {
    var body: some View {
        VStack(spacing: DT.Spacing.sm) {
            Image("ArcfinLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 64 * 0.225, style: .continuous))
                .shadow(color: DT.Color.accent.opacity(0.35), radius: 18)
                .accessibilityHidden(true)
            Text("What's New in Arcfin")
                .font(.largeTitle.bold())
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}

/// An accent-tinted symbol beside a title and a sentence, as in Apple's own What's New cards.
struct IntroductionFeatureRow: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: DT.Spacing.md) {
            Image(systemName: icon)
                .scaledFont(size: 26, weight: .medium)
                .foregroundStyle(DT.Color.accent)
                .frame(width: 44 * DT.Scale.font)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(DT.Color.textPrimary)
                Text(detail)
                    .scaledFont(size: 15)
                    .foregroundStyle(DT.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The soft cyan light the splash screen glows with, behind the tour and the card.
struct IntroductionGlow: View {
    var size: CGFloat = 560

    var body: some View {
        RadialGradient(
            colors: [DT.Color.accent.opacity(0.28), DT.Color.accentDeep.opacity(0.08), .clear],
            center: .center, startRadius: 0, endRadius: size / 2
        )
        .frame(width: size, height: size)
        .blur(radius: 30)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
