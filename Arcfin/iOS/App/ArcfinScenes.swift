// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData

typealias PlatformAppDelegate = UIApplicationDelegateAdaptor<AppDelegate>

extension ArcfinApp {
    @SceneBuilder
    func platformScenes(main: some Scene) -> some Scene {
        main

        WindowGroup("Player", id: "player", for: PlayerWindowRequest.self) { $request in
            if let request {
                PlayerWindow(request: request)
                    .modelContainer(sharedModelContainer)
            }
        }
    }
}
