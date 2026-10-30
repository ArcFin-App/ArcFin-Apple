// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The card that says what changed in this version: once after an update, and from Settings.
struct WhatsNewView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DT.Spacing.xl) {
                    WhatsNewHeader()
                    VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                        ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { _, item in
                            IntroductionFeatureRow(icon: item.icon, title: item.title, detail: item.detail)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, DT.Spacing.lg)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            LoginPrimaryButton(title: String(localized: "Continue"), action: onDone)
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal, 28)
                .padding(.vertical, DT.Spacing.md)
                .frame(maxWidth: 520)
        }
        .screenBackground()
    }
}

#Preview {
    WhatsNewView(onDone: {})
}
