// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    func arcfinListStyle() -> some View {
        // Settings Lists were stretching full window width on macOS — every row's
        // label/value pair spread edge to edge instead of reading as a compact form.
        self.scrollContentBackground(.hidden)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }

    /// On tvOS a row has to take focus for the remote to reach it, and a page with nothing
    /// focusable sent focus to the tab bar, where Back leaves the app. The rows stay read-only.
    func tvReadOnlyRow() -> some View {
        self
    }

    /// For a page opened from Settings on Apple TV. With the tab bar showing, Up from the top
    /// row moved focus onto it, and Back from there left the app instead of going back.
    func tvSettingsPage() -> some View {
        self
    }

    func tvListRow() -> some View {
        self
    }
}

/// A settings page: a grouped form, as System Settings draws one.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}
