// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// No capitals, the URL keyboard for an address, and the content type so Passwords and
    /// AutoFill can help.
    func loginFieldInput(_ kind: LoginFieldKind) -> some View {
        textInputAutocapitalization(.never)
            .keyboardType(kind == .url ? .URL : .default)
            .textContentType(kind.contentType)
    }

    func loginBackButtonPadding() -> some View {
        self
    }

    /// The Quick Connect code can be selected and copied.
    func quickConnectCodeSelection() -> some View {
        textSelection(.enabled)
    }

    func seerrPromptNotNowButton(_ action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Not Now", action: action)
            }
        }
    }

    func seerrPasswordFieldStyle(onSubmit: @escaping () -> Void) -> some View {
        textFieldStyle(.roundedBorder)
            .submitLabel(.go)
            .onSubmit(onSubmit)
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
