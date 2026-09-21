// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
#if canImport(UIKit) && !os(tvOS)
import UIKit
#endif

enum HapticManager {
    static func impact(_ style: HapticStyle = .medium) {
        #if canImport(UIKit) && !os(tvOS)
        guard UserDefaults.standard.object(forKey: "hapticsEnabled") == nil
            || UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        UIImpactFeedbackGenerator(style: style.uiStyle).impactOccurred()
        #endif
    }

    enum HapticStyle {
        case light, medium, heavy

        #if canImport(UIKit) && !os(tvOS)
        var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light:  .light
            case .medium: .medium
            case .heavy:  .heavy
            }
        }
        #endif
    }
}
