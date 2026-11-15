// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension EnvironmentValues {
    /// Set by the Settings window, whose panes fill it as a Mac's settings do.
    @Entry var listFillsWidth = false
}

private struct ArcfinListWidth: ViewModifier {
    @Environment(\.listFillsWidth) private var fillsWidth

    func body(content: Content) -> some View {
        // In the main window a list across the full width spreads each label and its
        // value edge to edge, so it stays a compact column there.
        content
            .frame(maxWidth: fillsWidth ? .infinity : 720)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func arcfinListStyle() -> some View {
        self.scrollContentBackground(.hidden)
            .modifier(ArcfinListWidth())
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
