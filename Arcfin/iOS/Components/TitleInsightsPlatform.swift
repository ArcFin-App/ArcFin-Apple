// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension TitleInsights {
    static let logoSize: CGFloat = 52
    static let showsLinks = true
}

extension View {
    /// A review score that opens its page.
    func scoreChipAction(label: String, value: String, url: URL?, open: @escaping (URL) -> Void) -> some View {
        Button { if let url { open(url) } } label: { self }
            .buttonStyle(.plain)
            .disabled(url == nil)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label) \(value)")
    }
}
