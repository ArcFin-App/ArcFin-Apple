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

extension View {
    /// The Mac types the PIN on its keyboard; here the keys are the pad.
    func pinPadKeyboard(digit: @escaping (Int) -> Void, delete: @escaping () -> Void,
                        submit: @escaping () -> Void, cancel: (() -> Void)?) -> some View {
        self
    }
}
