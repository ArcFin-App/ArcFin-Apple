// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit

/// The system accessibility settings `DT` follows.
enum PlatformAccessibility {
    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
