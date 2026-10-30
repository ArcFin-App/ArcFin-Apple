// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UIKit

extension HapticManager {
    static func impact(_ style: HapticStyle = .medium) {
        guard UserDefaults.standard.object(forKey: "hapticsEnabled") == nil
            || UserDefaults.standard.bool(forKey: "hapticsEnabled") else { return }
        UIImpactFeedbackGenerator(style: style.uiStyle).impactOccurred()
    }
}

extension HapticManager.HapticStyle {
    var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light:  .light
        case .medium: .medium
        case .heavy:  .heavy
        }
    }
}
