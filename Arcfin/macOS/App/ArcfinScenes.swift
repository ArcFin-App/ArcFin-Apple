// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import UserNotifications
import Telemetry

/// The Mac has no app delegate; this starts what one would, as the app starts.
@propertyWrapper
struct PlatformAppDelegate {
    var wrappedValue: PlatformAppDelegate { self }

    init() {
        // Taps on a notification open the title, Discover or Downloads, as on iOS.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        BackgroundRefresh.register()
        Diagnostics.shared.start()
    }
}

extension ArcfinApp {
    @SceneBuilder
    func platformScenes(main: some Scene) -> some Scene {
        main
            // MainTabView's .tabViewStyle(.sidebarAdaptable) already renders as a real macOS
            // sidebar — no separate NavigationSplitView shell needed. This just gives the
            // window itself sane native sizing instead of whatever SwiftUI's bare default is.
            .defaultSize(width: 1280, height: 800)
            .windowResizability(.contentSize)
            .commands {
                SidebarCommands()
                // Edit › Find… (⌘F) searches the library, the app's one search field.
                CommandGroup(replacing: .textEditing) {
                    Button("Find…") {
                        UserDefaults.standard.set(true, forKey: "arcfin.pendingFindFocus")
                        NotificationCenter.default.post(name: .arcfinSearch, object: nil)
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }
                CommandGroup(after: .newItem) {
                    Button("Open Video File…") {
                        NotificationCenter.default.post(name: .arcfinOpenFile, object: nil)
                    }
                    .keyboardShortcut("o", modifiers: .command)
                }
                CommandGroup(before: .sidebar) {
                    Button("Refresh") {
                        NotificationCenter.default.post(name: .arcfinRefresh, object: nil)
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    Divider()
                }
                PlaybackCommands()
                CommandMenu("Go") {
                    ForEach(Array(BottomNavItem.allCases.enumerated()), id: \.element) { index, tab in
                        Button(tab.title) {
                            NotificationCenter.default.post(name: .arcfinSelectTab, object: nil, userInfo: ["tab": tab.rawValue])
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    }
                    Divider()
                    Button("Downloads") {
                        UserDefaults.standard.set(true, forKey: "arcfin.pendingShowDownloads")
                        NotificationCenter.default.post(name: .arcfinShowDownloads, object: nil)
                    }
                    .keyboardShortcut("d", modifiers: [.option, .command])
                }
            }

        Settings {
            MacSettingsWindow()
                .modelContainer(sharedModelContainer)
        }

        WindowGroup("Player", id: "player", for: PlayerWindowRequest.self) { $request in
            if let request {
                PlayerWindow(request: request)
                    .modelContainer(sharedModelContainer)
            }
        }
        .defaultSize(width: 1280, height: 720)
    }
}
