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
                    TVRowLabelText(title: "Chapter List")
                }
                .tvListRow()
                .syncLocked("chapterListEnabled", authManager)
            } footer: {
                Text("Shows a jump-to-chapter list button in the player when the item has chapter markers.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $syncPlayEnabled) {
                    TVRowLabelText(title: "SyncPlay")
                }
                .tvListRow()
                .syncLocked("syncPlayEnabled", authManager)
            } footer: {
                Text("Lets you create or join a SyncPlay group to keep playback in sync with others watching the same title.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $castEnabled) {
                    TVRowLabelText(title: "Chromecast")
                }
                .tvListRow()
                .syncLocked("castEnabled", authManager)
            } footer: {
                Text("Shows the Cast button when a Chromecast device is available on your network.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $stillWatchingPromptEnabled) {
                    TVRowLabelText(title: "\"Are You Still Watching?\" Prompt")
                }
                .tvListRow()
                .syncLocked("stillWatchingPromptEnabled", authManager)
            } footer: {
                Text("Pauses and asks for confirmation after 3 episodes have auto-played in a row with no interaction.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $matchContentFrameRate) {
                    TVRowLabelText(title: "Match Content Frame Rate")
                }
                .tvListRow()
                .syncLocked("matchContentFrameRate", authManager)
            } footer: {
                Text("Switches the display's refresh rate to match the video's frame rate (e.g. 24fps film) so panning motion doesn't judder. Only applies to AVFoundation playback — off by default since some TVs/displays show a brief black flash when the refresh rate switches.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            #if os(iOS)
            Section {
                Toggle("Picture in Picture When Leaving", isOn: $autoPictureInPicture)
                    .syncLocked("autoPictureInPicture", authManager)
                Toggle("Swipe Gestures", isOn: $swipeGesturesEnabled)
                    .syncLocked("swipeGesturesEnabled", authManager)
                Toggle("Double-Tap to Skip", isOn: $doubleTapToSkip)
                    .syncLocked("doubleTapToSkip", authManager)
            } footer: {
                Text("Picture in Picture keeps the video playing in a small window when you go to the Home Screen, with every player engine except when Aether has to decode in software (Picture in Picture isn't offered then at all). Swipe up or down on the left for brightness and on the right for volume, and sideways to move through the video; double-tap a side to skip.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            #elseif os(macOS)
            Section {
                Toggle("Double-Click to Skip", isOn: $doubleTapToSkip)
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
