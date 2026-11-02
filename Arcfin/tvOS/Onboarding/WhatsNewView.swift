// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The card that says what changed in this version: once after an update, and from Settings.
struct WhatsNewView: View {
    let onDone: () -> Void

    @FocusState private var continueFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 120) {
            VStack(spacing: DT.Spacing.lg) {
                WhatsNewHeader()
                Button(action: onDone) {
                    TVHeroButtonLabel(icon: "checkmark", text: "Continue", isPrimary: true)
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .focused($continueFocused)
            }
            .frame(width: 560)
            .focusSection()

            // Each item takes focus so the remote can scroll a list taller than the screen.
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { _, item in
                        IntroductionFeatureRow(icon: item.icon, title: item.title, detail: item.detail)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tvFocusable(cornerRadius: DT.Radius.md)
                    }
                }
                .padding(24)
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .frame(maxWidth: 900)
            .focusSection()
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                DT.Color.backgroundPrimary
                IntroductionGlow().offset(x: -520, y: -120)
            }
            .ignoresSafeArea()
        }
        .defaultFocus($continueFocused, true)
    }
}

#Preview {
    WhatsNewView(onDone: {})
}
