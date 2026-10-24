// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Per-feature on/off switches for everything added to the player beyond the original
/// core playback controls — each reads back via plain UserDefaults from PlayerView itself
/// (a struct, not a View, so no @AppStorage there), same keys as declared here.
struct PlayerFeaturesSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("chapterListEnabled") private var chapterListEnabled = true
    @AppStorage("syncPlayEnabled") private var syncPlayEnabled = true
    @AppStorage("castEnabled") private var castEnabled = true
    @AppStorage("stillWatchingPromptEnabled") private var stillWatchingPromptEnabled = true
    @AppStorage("matchContentFrameRate") private var matchContentFrameRate = false
    @AppStorage("autoPictureInPicture") private var autoPictureInPicture = false
    @AppStorage("swipeGesturesEnabled") private var swipeGesturesEnabled = true
    @AppStorage("doubleTapToSkip") private var doubleTapToSkip = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $chapterListEnabled) {
                    TVRowLabelText(title: "Chapter List", detail: "A button in the player to jump between chapters, when the title has them.")
                }
                .tvListRow()
                .syncLocked("chapterListEnabled", authManager)
            }

            Section {
                Toggle(isOn: $syncPlayEnabled) {
                    TVRowLabelText(title: "SyncPlay", detail: "Create or join a group that keeps playback in sync with others.")
                }
                .tvListRow()
                .syncLocked("syncPlayEnabled", authManager)
            }

            Section {
                Toggle(isOn: $castEnabled) {
                    TVRowLabelText(title: "Chromecast", detail: "Shows the Cast button when a Chromecast is on your network.")
                }
                .tvListRow()
                .syncLocked("castEnabled", authManager)
            }

            Section {
                Toggle(isOn: $stillWatchingPromptEnabled) {
                    TVRowLabelText(title: "\"Are You Still Watching?\" Prompt", detail: "Pauses and asks after 3 episodes play in a row with no input.")
                }
                .tvListRow()
                .syncLocked("stillWatchingPromptEnabled", authManager)
            }

            Section {
                Toggle(isOn: $matchContentFrameRate) {
                    TVRowLabelText(title: "Match Content Frame Rate", detail: "Switches the display to the video's frame rate so motion doesn't judder. AVFoundation only; some TVs flash black when it switches.")
                }
                .tvListRow()
                .syncLocked("matchContentFrameRate", authManager)
            }

            #if os(iOS)
            Section {
                Toggle(isOn: $autoPictureInPicture) {
                    TVRowLabelText(title: "Picture in Picture When Leaving", detail: "Keeps the video playing in a small window when you go Home. Not offered when Aether decodes in software.")
                }
                .syncLocked("autoPictureInPicture", authManager)
                Toggle(isOn: $swipeGesturesEnabled) {
                    TVRowLabelText(title: "Swipe Gestures", detail: "Up or down on the left for brightness, the right for volume; sideways to move through the video.")
                }
                .syncLocked("swipeGesturesEnabled", authManager)
                Toggle(isOn: $doubleTapToSkip) {
                    TVRowLabelText(title: "Double-Tap to Skip", detail: "Double-tap a side of the video to skip back or forward.")
                }
                .syncLocked("doubleTapToSkip", authManager)
            }
            #elseif os(macOS)
            Section {
                Toggle(isOn: $doubleTapToSkip) {
                    TVRowLabelText(title: "Double-Click to Skip", detail: "Double-click a side of the video to skip back or forward.")
                }
                .syncLocked("doubleTapToSkip", authManager)
            }
            #endif
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Player Features")
    }
}

#Preview {
    NavigationStack { PlayerFeaturesSettingsView() }
        .environment(AuthManager())
}
