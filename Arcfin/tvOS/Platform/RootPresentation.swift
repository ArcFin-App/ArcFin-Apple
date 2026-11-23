// SPDX-License-Identifier: AGPL-3.0-or-later

import UIKit

@MainActor
enum RootPresentation {
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// Something is presented over the window's root, which a view in the root can't draw above.
    static var isCovered: Bool { keyWindow?.rootViewController?.presentedViewController != nil }

    /// Something other than an alert is presented on top, so an alert asked for just now
    /// couldn't show.
    static var keepsAlertAway: Bool {
        guard var top = keyWindow?.rootViewController?.presentedViewController else { return false }
        while let presented = top.presentedViewController { top = presented }
        return !(top is UIAlertController)
    }
}
