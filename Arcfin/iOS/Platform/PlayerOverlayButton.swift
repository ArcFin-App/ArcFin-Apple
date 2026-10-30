// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// A button on the player's own overlays (suggestions, X-Ray): plain where it's pointed or
    /// tapped at, a focus ring on tvOS where the remote moves between them.
    func playerOverlayButton(cornerRadius: CGFloat) -> some View {
        buttonStyle(.plain)
    }
}
