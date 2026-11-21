// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// The content type, so the iPhone offers its saved password for the server.
    func loginFieldInput(_ kind: LoginFieldKind) -> some View {
        textContentType(kind.contentType)
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

private extension LoginFieldKind {
    var contentType: UITextContentType {
        switch self {
        case .url: .URL
        case .username: .username
        case .password: .password
        }
    }
}
