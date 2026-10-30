// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

// Scroll-target behavior that snaps to either the top (hero) or the showcase
// boundary (below-fold shelves). Pass the screen height as showcaseHeight.
struct TVFoldSnappingBehavior: ScrollTargetBehavior {
    let showcaseHeight: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        // Only snap while transitioning between the hero and the shelves. Unconditionally
        // forcing every target to 0 or showcaseHeight meant that once scrolled (or
        // focus-scrolled) down into the shelves themselves, every settle kept getting
        // yanked back to exactly showcaseHeight — the very top of the shelves — which made
        // it impossible to reach shelves further down than the first screenful.
        guard target.rect.minY < showcaseHeight * 1.05 else { return }
        if target.rect.minY < showcaseHeight * 0.22 {
            target.rect.origin.y = 0
        } else {
            target.rect.origin.y = showcaseHeight
        }
    }
}
