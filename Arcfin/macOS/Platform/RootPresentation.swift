// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit

@MainActor
enum RootPresentation {
    /// A sheet is up over a window, which a view in the window can't draw above. The sheet is the
    /// key window then, so every window is checked.
    static var isCovered: Bool { NSApp.windows.contains { $0.isVisible && $0.attachedSheet != nil } }

    /// An alert shows as a sheet too, so there's no telling one from the other: an alert asked
    /// for is taken as shown.
    static var keepsAlertAway: Bool { false }
}
