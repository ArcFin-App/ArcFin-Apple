// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Per-feature on/off switches for everything added to the player beyond the original
/// core playback controls — each reads back via plain UserDefaults from PlayerView itself
/// (a struct, not a View, so no @AppStorage there), same keys as declared here.
struct PlayerFeaturesSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("doubleTapToSkip") private var doubleTapToSkip = true

    var body: some View {
        List {
            PlayerFeatureToggleSections()

            Section {
                Toggle(isOn: $doubleTapToSkip) {
                    TVRowLabelText(title: "Double-Click to Skip", detail: "Double-click a side of the video to skip back or forward.")
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
