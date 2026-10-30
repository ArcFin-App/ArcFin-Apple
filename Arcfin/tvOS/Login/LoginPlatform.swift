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

    func seerrPromptNotNowButton(_ action: @escaping () -> Void) -> some View {
        self
    }

    // .roundedBorder is unavailable on tvOS — its SecureField already renders
    // with the system's own default appearance there, no style needed.
    func seerrPasswordFieldStyle(onSubmit: @escaping () -> Void) -> some View {
        self
    }
}
