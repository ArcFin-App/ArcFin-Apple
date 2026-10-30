// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension PINPadView {
    static let keySize: CGFloat = 110
}

extension View {
    func pinPadCancelStyle() -> some View {
        buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .tvFocusRing(cornerRadius: DT.Radius.md)
    }

    func pinPadKeyStyle() -> some View {
        buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
    }
}
