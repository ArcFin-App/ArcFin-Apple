// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Matches a poster tap's source geometry with its MediaDetailView destination for the
    /// `.zoom` navigation transition. `namespace` is optional because MediaDetailView can be
    /// reached from places that don't own a matching namespace (e.g. the Home hero banner) —
    /// those fall back to a plain push instead of failing to compile.
    @ViewBuilder
    func zoomTransitionSource(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// The destination half of the zoom; macOS has no zoom navigation transition.
    func zoomNavigationTransition(id: String, in namespace: Namespace.ID) -> some View {
        navigationTransition(.zoom(sourceID: id, in: namespace))
    }
}
