// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension HapticManager {
    /// No haptics here.
    static func impact(_ style: HapticStyle = .medium) {}
    static func selection() {}
    static func success() {}
    static func error() {}
    static func warning() {}
}
