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
    /// Typing the PIN: digits, Delete, Return to finish a new one, Esc to cancel.
    func pinPadKeyboard(digit: @escaping (Int) -> Void, delete: @escaping () -> Void,
                        submit: @escaping () -> Void, cancel: (() -> Void)?) -> some View {
        modifier(PINPadKeyboard(digit: digit, delete: delete, submit: submit, cancel: cancel))
    }
}

private struct PINPadKeyboard: ViewModifier {
    let digit: (Int) -> Void
    let delete: () -> Void
    let submit: () -> Void
    let cancel: (() -> Void)?
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .defaultFocus($focused, true)
            .onAppear { focused = true }
            .onKeyPress(phases: .down) { press in
                if press.characters.count == 1, let number = Int(press.characters) {
                    digit(number)
                    return .handled
                }
                switch press.key {
                case .delete, .deleteForward:
                    delete()
                case .return:
                    submit()
                case .escape:
                    guard let cancel else { return .ignored }
                    cancel()
                default:
                    return .ignored
                }
                return .handled
            }
    }
}
