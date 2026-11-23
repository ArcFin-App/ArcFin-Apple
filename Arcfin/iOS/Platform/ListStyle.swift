// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// A list that's always rearranging, with its handles showing.
    func alwaysEditing() -> some View { environment(\.editMode, .constant(.active)) }

    /// The A–Z index down the side of a long list, as the system draws it.
    func sectionIndexShown() -> some View { listSectionIndexVisibility(.visible) }

    /// A web address field: the URL keyboard, no capitals.
    func urlFieldKeyboard() -> some View { self.keyboardType(.URL).textInputAutocapitalization(.never) }

    func arcfinListStyle() -> some View {
        self.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
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

    /// A music section's own search, always showing under the title so it's found without
    /// pulling the list down.
    func sectionSearchable(text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
    }
}

/// A settings page. A grouped form on the Mac.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        List { content }
    }
}
