// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Apple TV's own sheet is a fixed card about a third of the screen wide, whatever the
    /// content asks for: lists ran to its edges and longer content was cut off. This shows the
    /// content in a wide panel over the dimmed screen instead. Menu closes it, as with a sheet.
    func appSheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            TVSheetPanel(content: content())
        }
    }

    func appSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                     @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { item in
            TVSheetPanel(content: content(item))
        }
    }
}

private struct TVSheetPanel<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
            .frame(maxWidth: 1120, maxHeight: .infinity)
            // The same colour as the pages shown in it, so their own background doesn't read
            // as a second box inside the panel.
            .background(DT.Color.backgroundPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 44))
            .overlay(RoundedRectangle(cornerRadius: 44).stroke(Color.white.opacity(0.12), lineWidth: 2))
            .padding(.vertical, 90)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusSection()
            .presentationBackground(Color.black.opacity(0.7))
    }
}
