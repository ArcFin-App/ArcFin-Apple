// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The request sheet's Cancel at the foot of the sheet, where the remote reaches it.
struct SeerrRequestCancelButton: View {
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
            Text("Cancel")
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.md)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.lg)
    }
}

extension View {
    /// No toolbar on Apple TV; the sheet has its own Cancel button.
    func seerrRequestCancelToolbar(_ action: @escaping () -> Void) -> some View {
        self
    }
}
