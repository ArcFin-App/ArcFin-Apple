// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence

@main
struct ArcfinApp: App {
    var sharedModelContainer: ModelContainer = Persistence.makeContainerRecoveringFromFailure()
    @PlatformAppDelegate private var appDelegate

    var body: some Scene {
        platformScenes(main: WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer))
    }
}

/// One set of app state for every window: the main one, another on iPad, and a player in a
/// window of its own.
@MainActor
enum AppServices {
    static let authManager = AuthManager()
    static let mediaRepo = MediaRepository()
    static let seerrRepo = SeerrRepository()
    static let downloadManager = DownloadManager()
    static let syncPlayManager = SyncPlayManager()
    static let sharePlayManager = SharePlayManager()
    static let liveUpdates = LiveUpdates(mediaRepo: mediaRepo)
    /// Offers to set up a signed-out Apple TV on the network (#481), by itself or from Settings.
    static let appleTVSetup = AppleTVSetupGuide()
    static let introduction = AppIntroduction()
    /// Past the app lock (or there's none) this launch. A player window brought back on
    /// relaunch closes rather than play ahead of the lock.
    static var hasPassedLock = false
}
