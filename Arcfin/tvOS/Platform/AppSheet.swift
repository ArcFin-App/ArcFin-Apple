// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Apple TV's own sheet is a fixed card about a third of the screen wide, whatever the
    /// content asks for: lists ran to its edges and longer content was cut off. This shows the
    /// content in a panel across the dimmed screen instead, and as TVs are landscape, in two
    /// columns when there's a `title`: the title and an icon on the left, the content on the
    /// right. Menu closes it, as with a sheet.
    func appSheet<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                 title: LocalizedStringKey? = nil, systemImage: String? = nil,
                                 @ViewBuilder content: @escaping () -> Content) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            TVSheetPanel(title: title, systemImage: systemImage, content: content())
        }
    }

    func appSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                     title: LocalizedStringKey? = nil, systemImage: String? = nil,
                                                     @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { item in
            TVSheetPanel(title: title, systemImage: systemImage, content: content(item))
        }
    }

    /// A sheet page's title, or, in a two-column sheet, which shows it in its left column, no
    /// navigation bar so it isn't shown twice.
    func sheetTitle(_ title: LocalizedStringKey) -> some View {
        modifier(SheetTitle(title: title))
    }
}

private struct InTitledSheetKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var inTitledSheet: Bool {
        get { self[InTitledSheetKey.self] }
        set { self[InTitledSheetKey.self] = newValue }
    }
}

private struct SheetTitle: ViewModifier {
    let title: LocalizedStringKey
    @Environment(\.inTitledSheet) private var inTitledSheet

    func body(content: Content) -> some View {
        if inTitledSheet {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content.navigationTitle(title)
        }
    }
}

private struct TVSheetPanel<Content: View>: View {
    let title: LocalizedStringKey?
    let systemImage: String?
    let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 64) {
            if let title {
                VStack(alignment: .leading, spacing: 18) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 56))
                            .foregroundStyle(DT.Color.accent)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(DT.Color.textPrimary)
                }
                .frame(width: 520, alignment: .leading)
                .padding(.top, 40)
            }
            // A list or scroll view clips at its own edges, so a row that grows when focused
            // was cut there. The margin puts room inside the scroll view, and scroll views in
            // a sheet don't clip: the panel's own edge does.
            content
                .contentMargins(.horizontal, 40, for: .scrollContent)
                .scrollClipDisabled()
                .environment(\.inTitledSheet, title != nil)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusSection()
        }
        .padding(.horizontal, 64)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The same colour as the pages shown in it, so their own background doesn't read as a
        // second box inside the panel.
        .background(DT.Color.backgroundPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 44))
        .overlay(RoundedRectangle(cornerRadius: 44).stroke(Color.white.opacity(0.12), lineWidth: 2))
        .padding(.horizontal, 60)
        .padding(.vertical, 50)
        .presentationBackground(Color.black.opacity(0.7))
    }
}
