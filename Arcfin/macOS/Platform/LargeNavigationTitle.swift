// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// A literal is looked up in the String Catalog, as `Text` does.
    func arcfinNavTitleLarge(_ title: LocalizedStringKey) -> some View {
        self.navigationTitle(title)
    }

    /// A name or text that's already localized, shown as it is.
    func arcfinNavTitleLarge<S: StringProtocol>(_ title: S) -> some View {
        self.navigationTitle(String(title))
    }
}
