// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// The remote's Back button.
    func tvExitCommand(perform action: @escaping () -> Void) -> some View {
        onExitCommand(perform: action)
    }
}
