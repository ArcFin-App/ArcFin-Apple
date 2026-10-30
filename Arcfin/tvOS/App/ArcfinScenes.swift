// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Apple TV has no app delegate.
@propertyWrapper
struct PlatformAppDelegate {
    var wrappedValue: PlatformAppDelegate { self }
}

extension ArcfinApp {
    func platformScenes(main: some Scene) -> some Scene {
        main
    }
}
