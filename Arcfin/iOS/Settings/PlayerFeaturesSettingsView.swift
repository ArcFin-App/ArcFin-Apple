// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Per-feature on/off switches for everything added to the player beyond the original
/// core playback controls — each reads back via plain UserDefaults from PlayerView itself
/// (a struct, not a View, so no @AppStorage there), same keys as declared here.
struct PlayerFeaturesSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("autoPictureInPicture") private var autoPictureInPicture = false
    @AppStorage("swipeGesturesEnabled") private var swipeGesturesEnabled = true
    @AppStorage("doubleTapToSkip") private var doubleTapToSkip = true

    var body: some View {
        List {
            PlayerFeatureToggleSections()

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
