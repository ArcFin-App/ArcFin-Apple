// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Reports the pointer entering and leaving: a trackpad or mouse here, nothing on Apple TV.
    func onPointerHover(_ action: @escaping (Bool) -> Void) -> some View {
        onHover(perform: action)
    }
}
