// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UIKit

extension SwiftUI.Color {
    /// One colour for the light appearance and one for the dark, switching with the system.
    init(light: String, dark: String) {
        let light = SwiftUI.Color(hex: light), dark = SwiftUI.Color(hex: dark)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}
