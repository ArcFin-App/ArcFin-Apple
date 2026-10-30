// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// A small title in a bar with no background, over a page's artwork.
    func transparentInlineNavigationBar() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}
