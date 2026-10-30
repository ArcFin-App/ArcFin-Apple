// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Pressable, and the source of the zoom transition into the title's page.
struct CollectionCardButtonStyle: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content
                .buttonStyle(PressableButtonStyle())
                .zoomTransitionSource(id: id, in: namespace)
        } else {
            content.buttonStyle(PressableButtonStyle())
        }
    }
}
