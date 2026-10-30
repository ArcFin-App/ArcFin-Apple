// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

enum StatsMetrics {
    static let scale: CGFloat = 1.8
    static let showsRowChevron = false
}

extension View {
    @ViewBuilder
    func statsCardFocus(_ isFocusTarget: Bool) -> some View {
        if isFocusTarget {
            focusable()
                .tvFocusRing(cornerRadius: DT.Radius.xl)
        } else {
            self
        }
    }

    func statsHeroFocus() -> some View {
        focusable()
            .tvFocusRing(cornerRadius: DT.Radius.xl)
    }

    func statsGenreRowFocus() -> some View {
        padding(10)
            .focusable()
            .tvFocusRing(cornerRadius: DT.Radius.md)
    }

    func statsFactLinkPadding() -> some View {
        padding(8)
    }
}
