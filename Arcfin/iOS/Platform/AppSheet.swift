// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// The PIN pad, in a sheet. Apple TV shows it full screen.
    func pinPadSheet<Item: Identifiable, Content: View>(item: Binding<Item?>,
                                                        @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        appSheet(item: item, content: content)
    }

    /// A sheet. Apple TV draws its own panel instead, in two columns when there's a title
    /// (see its AppSheet); here `title` and `systemImage` aren't used.
    func appSheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                 title: LocalizedStringKey? = nil, systemImage: String? = nil,
                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }

    func appSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                     title: LocalizedStringKey? = nil, systemImage: String? = nil,
                                                     @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss, content: content)
    }

    /// A sheet page's title. On Apple TV a two-column sheet shows it in its left column instead.
    func sheetTitle(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
    }
}
