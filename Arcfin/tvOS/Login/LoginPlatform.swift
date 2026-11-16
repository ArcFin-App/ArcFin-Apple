// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    func loginFieldInput(_ kind: LoginFieldKind) -> some View {
        self
    }

    func loginBackButtonPadding() -> some View {
        padding(.horizontal, 16)
    }

    func quickConnectCodeSelection() -> some View {
        self
    }

    /// Room inside a link-style button, so the Apple TV's focus ring clears its text.
    func loginLinkPadding() -> some View {
        padding(.horizontal, 28)
            .padding(.vertical, 14)
    }

    /// A column the remote moves into as a whole, from any height.
    func loginFocusSection() -> some View {
        focusSection()
    }

    func seerrPromptNotNowButton(_ action: @escaping () -> Void) -> some View {
        self
    }

    // .roundedBorder is unavailable on tvOS — its SecureField already renders
    // with the system's own default appearance there, no style needed.
    func seerrPasswordFieldStyle(onSubmit: @escaping () -> Void) -> some View {
        self
    }
}
