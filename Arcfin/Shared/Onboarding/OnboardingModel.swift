// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Which page of the tour is showing, and which way it last moved, shared by every platform's
/// `OnboardingView`.
@MainActor @Observable
final class OnboardingModel {
    private(set) var index = 0
    private(set) var movingForward = true

    func isLast(of count: Int) -> Bool { index == count - 1 }

    var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    func next(of count: Int, finish: () -> Void) {
        guard !isLast(of: count) else { return finish() }
        movingForward = true
        index += 1
    }

    func back() {
        guard index > 0 else { return }
        movingForward = false
        index -= 1
    }
}
