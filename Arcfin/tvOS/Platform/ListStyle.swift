// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// A web address field: the URL keyboard, no capitals.
    func urlFieldKeyboard() -> some View { self.keyboardType(.URL).textInputAutocapitalization(.never) }

    func arcfinListStyle() -> some View {
        self.listStyle(.plain)
    }

    /// On tvOS a row has to take focus for the remote to reach it, and a page with nothing
    /// focusable sent focus to the tab bar, where Back leaves the app. The rows stay read-only.
    func tvReadOnlyRow() -> some View {
        // Dark text on the focused row's white, wherever the row's shown, even over a screen
        // that sets white text, as Now Playing does.
        Button {} label: { self }
            .modifier(TVListRowFocusTextModifier())
    }

    /// For a page opened from Settings on Apple TV. With the tab bar showing, Up from the top
    /// row moved focus onto it, and Back from there left the app instead of going back.
    func tvSettingsPage() -> some View {
        toolbar(.hidden, for: .tabBar)
    }

    func tvListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .modifier(TVListRowFocusTextModifier())
    }
}

// Native Toggle/Picker labels don't automatically invert to a readable color against the
// system's own focus platter the way a NavigationLink/Button row's custom styling does —
// they kept rendering in the app's plain white/primary text color even while focused,
// unreadable against the light platter. Every tvListRow() row gets this for free.
// The row's own focus comes from @FocusState: \.isFocused read here, on the focusable row
// itself, stayed false and kept the text white on the platter (see TVFocusRingModifier).
private struct TVListRowFocusTextModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .foregroundStyle(isFocused ? Color.black : DT.Color.textPrimary)
            .animation(DT.Animation.fast, value: isFocused)
    }
}

/// A settings page. A grouped form on the Mac.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        List { content }
    }
}
