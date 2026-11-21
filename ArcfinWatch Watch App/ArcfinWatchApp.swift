// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Arcfin on Apple Watch, signed in by the iPhone: a remote for Arcfin playing on another
/// device (#458), and music played on the watch itself, with playlists kept on it (#518).
@main
struct ArcfinWatchApp: App {
    @State private var remote = WatchRemote()
    @State private var music = WatchMusicPlayer()

    init() {
        WatchSignIn.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                NavigationStack { WatchMusicView() }
            }
            .tabViewStyle(.verticalPage)
            .environment(remote)
            .environment(music)
        }
    }
}
