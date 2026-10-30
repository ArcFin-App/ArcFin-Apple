// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The request sheet's Cancel at the foot of the sheet, on Apple TV only; here it's in the toolbar.
struct SeerrRequestCancelButton: View {
    let action: () -> Void

    var body: some View {
        EmptyView()
    }
}

extension View {
    /// The request sheet's Cancel in the toolbar.
    func seerrRequestCancelToolbar(_ action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { action() }
            }
        }
    }
}
