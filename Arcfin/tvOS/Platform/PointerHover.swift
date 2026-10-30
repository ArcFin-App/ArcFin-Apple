// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Apple TV has no pointer; focus does the highlighting.
    func onPointerHover(_ action: @escaping (Bool) -> Void) -> some View {
        self
    }
}
