// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import SwiftData
import UserNotifications
import Telemetry

typealias PlatformAppDelegate = NSApplicationDelegateAdaptor<MacAppDelegate>

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// Starts at the same point the app does, as before there was a delegate.
    override init() {
        super.init()
        // Taps on a notification open the title, Discover or Downloads, as on iOS.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        BackgroundRefresh.register()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BackgroundRefresh.checkFeedOnOpen() }
        }
        Diagnostics.shared.start()
        MusicWidgetPublisher.start()
    }

    /// The Mac's downloads don't outlive the app, so quitting mid-download asks first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !AppServices.downloadManager.activeItemIds.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit While Downloading?")
        alert.informativeText = String(localized: "Arcfin is still downloading. Quitting stops the downloads in progress.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
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
            .windowResizability(.contentMinSize)
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
                CommandGroup(replacing: .appSettings) {
                    SettingsMenuButton()
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

        // A window of its own rather than a Settings scene: that one centres its toolbar for
        // tabs, which put a page's back button in the middle of the title bar.
        Window("Settings", id: MacSettingsWindow.id) {
            MacSettingsWindow()
                .modelContainer(sharedModelContainer)
        }
        .defaultSize(width: 860, height: 640)
        .windowResizability(.contentMinSize)

        WindowGroup("Player", id: "player", for: PlayerWindowRequest.self) { $request in
            if let request {
                PlayerWindow(request: request)
                    .modelContainer(sharedModelContainer)
            }
        }
        .defaultSize(width: 1280, height: 720)
    }
}
