// SPDX-License-Identifier: AGPL-3.0-or-later

import UIKit

/// The system accessibility settings `DT` follows.
enum PlatformAccessibility {
    static var increaseContrast: Bool {
        UIAccessibility.isDarkerSystemColorsEnabled
    }

    static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}
