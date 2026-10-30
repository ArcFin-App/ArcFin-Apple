// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SetupGuideContent()
                .background(DT.Color.backgroundPrimary.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundStyle(DT.Color.accent)
                            .fontWeight(.semibold)
                    }
                }
        }
    }
}

#Preview {
    SetupGuideSheet()
}
