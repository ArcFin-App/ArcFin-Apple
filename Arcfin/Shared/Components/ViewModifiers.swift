// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Shows the view only when `isShown`, e.g. a control the profile isn't allowed to use.
    @ViewBuilder
    func shown(_ isShown: Bool) -> some View {
        if isShown { self }
    }

    /// A screen's background, always filling the whole screen. Applied straight to content
    /// that sizes itself (a spinner, an empty state, a short stack while results load), the
    /// colour only covered that content's narrow frame and the rest showed the system black
    /// until the full results arrived.
    func screenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { DT.Color.backgroundPrimary.ignoresSafeArea() }
    }
}
