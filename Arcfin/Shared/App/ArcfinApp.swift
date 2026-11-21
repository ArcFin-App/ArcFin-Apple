// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence
import AuthCore

@main
struct ArcfinApp: App {
    let sharedModelContainer = AppServices.modelContainer
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
    /// Static so the app delegate can reach it on a background relaunch, before any window.
    static let modelContainer: ModelContainer = Persistence.makeContainerRecoveringFromFailure()
    static let authManager = AuthManager()
    static let mediaRepo = MediaRepository()
    static let seerrRepo = SeerrRepository()
    static let downloadManager = DownloadManager()
    static let syncPlayManager = SyncPlayManager()
    static let sharePlayManager = SharePlayManager()
    static let liveUpdates = LiveUpdates(mediaRepo: mediaRepo)
    /// Offers to set up a signed-out Apple TV on the network (#481), by itself or from Settings.
    static let nearbySetup = NearbySetupGuide()
    /// The other devices this profile can control, for the iPhone remote (#457).
    static let remoteSessions = RemoteSessions()
    /// Music, playing behind every screen (#386).
    static let music = MusicPlayback(authManager: authManager)
    static let introduction = AppIntroduction()
    static let scenes = ScenePresence()
    /// Past the app lock (or there's none) this launch. A player window brought back on
    /// relaunch closes rather than play ahead of the lock.
    static var hasPassedLock = false {
        didSet {
            if hasPassedLock, !oldValue { NotificationCenter.default.post(name: .arcfinPassedLock, object: nil) }
        }
    }

    /// The profile in use has a PIN that hasn't been entered this launch. Started by Siri or a
    /// widget with no window yet, `hasPassedLock` alone would hold back a profile without one.
    static func isLocked() async -> Bool {
        guard !hasPassedLock, let id = authManager.state.credential?.id else { return false }
        return await authManager.storedPIN(for: id) != .none
    }
}

/// Whether any of the app's windows is in front. A window's own scene phase can't say that:
/// on iPad and Mac one going to the background while another stays open mustn't stop what
/// they share (#626).
@MainActor
@Observable
final class ScenePresence {
    private var phases: [UUID: ScenePhase] = [:]

    var anyActive: Bool { phases.values.contains(.active) }
    var anyForeground: Bool { phases.values.contains { $0 != .background } }

    func set(_ phase: ScenePhase, for scene: UUID) {
        if phases[scene] != phase { phases[scene] = phase }
    }

    func remove(_ scene: UUID) {
        phases[scene] = nil
    }
}
