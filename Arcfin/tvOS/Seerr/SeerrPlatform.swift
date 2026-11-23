// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    func transparentInlineNavigationBar() -> some View {
        self
    }
}

/// Where Seerr is set up, for the messages that send someone there.
enum SeerrSettingsHint {
    static var signInFailed: Text {
        Text("Seerr didn't accept the sign-in. Try again, or check Settings › Plugins › Seerr.")
    }
}
