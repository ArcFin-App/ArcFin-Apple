// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// A small title in a bar with no background, over a page's artwork.
    func transparentInlineNavigationBar() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// Where Seerr is set up, for the messages that send someone there.
enum SeerrSettingsHint {
    static var signInFailed: Text {
        Text("Seerr didn't accept the sign-in. Try again, or check Settings › Integrations › Seerr.")
    }
}
