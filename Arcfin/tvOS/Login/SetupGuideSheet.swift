// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SetupGuideContent()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(size: 36)
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(DT.Spacing.lg)
            }
            .accessibilityLabel("Close")
            .arcfinPlainButton(cornerRadius: DT.Radius.pill, prominent: false)
        }
        .background(DT.Color.backgroundPrimary.ignoresSafeArea())
    }
}

#Preview {
    SetupGuideSheet()
}
