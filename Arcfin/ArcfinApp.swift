// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
#if os(macOS)
import UserNotifications
#endif
import Persistence

@main
struct ArcfinApp: App {
    #if canImport(UIKit) && !os(tvOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    init() {
        // Taps on a notification open the title, Discover or Downloads, as on iOS.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        BackgroundRefresh.register()
    }
    #endif

    var sharedModelContainer: ModelContainer = Persistence.makeContainerRecoveringFromFailure()

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
        #endif
    }
}

#if os(macOS)
/// The open player's actions, for the Playback menu.
struct PlayerCommands {
    let isPlaying: Bool
    let togglePlay: () -> Void
    let skip: (Int) -> Void
    let volume: (Double) -> Void
    let toggleFullScreen: () -> Void
    let close: () -> Void
    let isMuted: Bool
    let toggleMute: () -> Void
    let hasSubtitles: Bool
    let subtitlesOn: Bool
    let toggleSubtitles: () -> Void
    let showTracks: () -> Void
    let showInfo: () -> Void
    let stepSpeed: (Int) -> Void
    let resetSpeed: () -> Void
    let skipSegmentLabel: String?
    let skipSegment: () -> Void
    let next: (() -> Void)?
    let previous: (() -> Void)?
}

extension FocusedValues {
    @Entry var playerCommands: PlayerCommands?
}

/// Every player control from the menu bar, each with the key the player already answers to.
private struct PlaybackCommands: Commands {
    @FocusedValue(\.playerCommands) private var player

    var body: some Commands {
        CommandMenu("Playback") {
            Group {
                Button(player?.isPlaying == true ? "Pause" : "Play") { player?.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Divider()
                Button("Skip Forward") { player?.skip(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Skip Back") { player?.skip(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Divider()
                Button("Volume Up") { player?.volume(0.05) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("Volume Down") { player?.volume(-0.05) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button(player?.isMuted == true ? "Unmute" : "Mute") { player?.toggleMute() }
                    .keyboardShortcut("m", modifiers: [])
                Divider()
                Button(player?.skipSegmentLabel ?? "Skip Intro") { player?.skipSegment() }
                    .keyboardShortcut("s", modifiers: [])
                    .disabled(player?.skipSegmentLabel == nil)
                Button("Next") { player?.next?() }
                    .keyboardShortcut(.rightArrow, modifiers: [.shift, .command])
                    .disabled(player?.next == nil)
                Button("Previous") { player?.previous?() }
                    .keyboardShortcut(.leftArrow, modifiers: [.shift, .command])
                    .disabled(player?.previous == nil)
                Divider()
                Button(player?.subtitlesOn == true ? "Turn Subtitles Off" : "Turn Subtitles On") { player?.toggleSubtitles() }
                    .keyboardShortcut("c", modifiers: [])
                    .disabled(player?.hasSubtitles != true)
                Button("Audio & Subtitles…") { player?.showTracks() }
                    .keyboardShortcut("t", modifiers: [])
                Divider()
                Button("Faster") { player?.stepSpeed(1) }
                    .keyboardShortcut("]", modifiers: [])
                Button("Slower") { player?.stepSpeed(-1) }
                    .keyboardShortcut("[", modifiers: [])
                Button("Normal Speed") { player?.resetSpeed() }
                    .keyboardShortcut("0", modifiers: [])
                Divider()
                Button("Media Info") { player?.showInfo() }
                    .keyboardShortcut("i", modifiers: .command)
                Divider()
                Button("Toggle Full Screen") { player?.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [])
                Button("Close Player") { player?.close() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .disabled(player == nil)
        }
    }
}
#endif
