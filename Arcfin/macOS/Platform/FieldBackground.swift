// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    func arcfinFieldBackground() -> some View {
        self
            .background(.white.opacity(0.06))
            .background(.ultraThinMaterial)
    }
}
