// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence

@main
struct ArcfinApp: App {
    #if canImport(UIKit) && !os(tvOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var sharedModelContainer: ModelContainer = {
        do {
            return try Persistence.makeContainer()
        } catch {
            fatalError("ModelContainer init failed: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        // MainTabView's .tabViewStyle(.sidebarAdaptable) already renders as a real macOS
        // sidebar — no separate NavigationSplitView shell needed. This just gives the
        // window itself sane native sizing instead of whatever SwiftUI's bare default is.
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
            // Standard macOS convention: Cmd+, / "Arcfin > Settings…" opens Settings.
            // There's no scene-level binding into MainTabView's private navigation state to
            // reach it directly, so this posts a notification the same way arcfinShowDownloads
            // already does for the download Live Activity's tap target — an established
            // pattern in this codebase, not a new one.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .arcfinShowSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }
}
