// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension PINPadView {
    static let keySize: CGFloat = 76
}

extension View {
    func pinPadCancelStyle() -> some View {
        self
    }

    func pinPadKeyStyle() -> some View {
        buttonStyle(.plain)
    }
}
