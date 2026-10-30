// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AppKit

extension SwiftUI.Color {
    /// One colour for the light appearance and one for the dark, switching with the system.
    init(light: String, dark: String) {
        let light = SwiftUI.Color(hex: light), dark = SwiftUI.Color(hex: dark)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}
