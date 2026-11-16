// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    func loginFieldInput(_ kind: LoginFieldKind) -> some View {
        self
    }

    func loginBackButtonPadding() -> some View {
        self
    }

    /// The Quick Connect code can be selected and copied.
    func quickConnectCodeSelection() -> some View {
        textSelection(.enabled)
    }

    /// Room inside a link-style button for the Apple TV's focus ring; none needed here.
    func loginLinkPadding() -> some View {
        self
    }

    /// A column the remote moves into as a whole; Apple TV only.
    func loginFocusSection() -> some View {
        self
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
