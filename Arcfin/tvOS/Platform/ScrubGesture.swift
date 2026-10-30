// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Apple TV has no drag; the remote scrubs instead.
    func onScrub(width: CGFloat, changed: @escaping (Double) -> Void, ended: @escaping () -> Void) -> some View {
        self
    }
}
