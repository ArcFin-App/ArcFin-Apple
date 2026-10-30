// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The focus card style.
struct CollectionCardButtonStyle: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        content
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
    }
}
