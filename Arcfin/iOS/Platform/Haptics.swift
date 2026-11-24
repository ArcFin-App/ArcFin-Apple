// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UIKit

extension HapticManager {
    private static var isOn: Bool {
        UserDefaults.standard.object(forKey: "hapticsEnabled") == nil || UserDefaults.standard.bool(forKey: "hapticsEnabled")
    }

    static func impact(_ style: HapticStyle = .medium) {
        guard isOn else { return }
        UIImpactFeedbackGenerator(style: style.uiStyle).impactOccurred()
    }

    /// A small tick for picking something: a key, a segment, a choice in a list.
    static func selection() {
        guard isOn else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Something worked: a PIN accepted, a request sent, a party started.
    static func success() { notify(.success) }

    /// Something didn't: a wrong PIN, a refused request.
    static func error() { notify(.error) }

    /// Careful: a destructive step is about to happen, or a limit was reached.
    static func warning() { notify(.warning) }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isOn else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
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
