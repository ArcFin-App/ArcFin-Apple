// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Arcfin on Apple Watch: a remote for Arcfin playing on another device (#458), signed in by
/// the iPhone.
@main
struct ArcfinWatchApp: App {
    @State private var remote = WatchRemote()

    init() {
        WatchSignIn.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(remote)
        }
    }
}
