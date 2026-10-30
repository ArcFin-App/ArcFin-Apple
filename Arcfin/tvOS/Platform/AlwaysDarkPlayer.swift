// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// The players, which on iPhone, iPad and Apple TV are their own full-screen presentation:
    /// that presentation is dark too, so its menus and alerts match.
    func alwaysDarkPlayer() -> some View {
        alwaysDark().preferredColorScheme(.dark)
    }
}
