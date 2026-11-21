// SPDX-License-Identifier: AGPL-3.0-or-later

import UIKit

@MainActor
enum RootPresentation {
    /// Something is presented over the window's root, which a view in the root can't draw above.
    static var isCovered: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }
}
