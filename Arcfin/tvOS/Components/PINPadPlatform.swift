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

extension View {
    /// The Mac types the PIN on its keyboard; here the keys are the pad.
    func pinPadKeyboard(digit: @escaping (Int) -> Void, delete: @escaping () -> Void,
                        submit: @escaping () -> Void, cancel: (() -> Void)?) -> some View {
        self
    }
}
