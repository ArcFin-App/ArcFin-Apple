// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension TitleInsights {
    static let logoSize: CGFloat = 96
    // A TV can't open web pages.
    static let showsLinks = false
}

extension View {
    /// A review score the remote can reach.
    func scoreChipAction(label: String, value: String, url: URL?, open: @escaping (URL) -> Void) -> some View {
        // Focusable so the remote can reach (and scroll to) the scores; there's no page to open.
        self
            .focusable()
            .tvFocusRing(cornerRadius: 12)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label) \(value)")
    }
}
