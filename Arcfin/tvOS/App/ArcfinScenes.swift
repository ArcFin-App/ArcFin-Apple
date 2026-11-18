// SPDX-License-Identifier: AGPL-3.0-or-later

import Intents
import SwiftUI
import UIKit

typealias PlatformAppDelegate = UIApplicationDelegateAdaptor<TVAppDelegate>

/// Siri's "Play … in Arcfin" from the remote.
final class TVAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? MusicSiriHandler() : nil
    }
}

extension ArcfinApp {
    func platformScenes(main: some Scene) -> some Scene {
        main
    }
}
