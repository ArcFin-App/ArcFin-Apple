// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The Player Features switches every platform has.
struct PlayerFeatureToggleSections: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("chapterListEnabled") private var chapterListEnabled = true
    @AppStorage("syncPlayEnabled") private var syncPlayEnabled = true
    @AppStorage("castEnabled") private var castEnabled = true
    @AppStorage("stillWatchingPromptEnabled") private var stillWatchingPromptEnabled = true
    @AppStorage("matchContentFrameRate") private var matchContentFrameRate = false
    /// The Mac leaves the display's refresh rate alone, so the switch would do nothing there.
    var showsFrameRateMatch = true
    /// Which players switch the frame rate differs: on Apple TV only Aether does.
    var frameRateDetail: LocalizedStringKey = "Switches the display to the video's frame rate so motion doesn't judder. Aether and AVFoundation only; some TVs flash black when it switches."
    /// Only the iPhone and iPad player has a Cast button.
    var showsCast = true

    var body: some View {
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

        if showsCast {
            Section {
                Toggle(isOn: $castEnabled) {
                    TVRowLabelText(title: "Chromecast", detail: "Shows the Cast button when a Chromecast is on your network.")
                }
                .tvListRow()
                .syncLocked("castEnabled", authManager)
            }
        }

        Section {
            Toggle(isOn: $stillWatchingPromptEnabled) {
                TVRowLabelText(title: "\"Are You Still Watching?\" Prompt", detail: "Pauses and asks after 3 episodes play in a row with no input.")
            }
            .tvListRow()
            .syncLocked("stillWatchingPromptEnabled", authManager)
        }

        if showsFrameRateMatch {
            Section {
            Toggle(isOn: $matchContentFrameRate) {
                TVRowLabelText(title: "Match Content Frame Rate", detail: frameRateDetail)
            }
            .tvListRow()
            .syncLocked("matchContentFrameRate", authManager)
            }
        }
    }
}
