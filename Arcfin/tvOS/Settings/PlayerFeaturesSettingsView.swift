// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Per-feature on/off switches for everything added to the player beyond the original
/// core playback controls — each reads back via plain UserDefaults from PlayerView itself
/// (a struct, not a View, so no @AppStorage there), same keys as declared here.
struct PlayerFeaturesSettingsView: View {
    var body: some View {
        List {
            PlayerFeatureToggleSections(
                frameRateDetail: "Switches the display to the video's frame rate so motion doesn't judder. Aether only; some TVs flash black when it switches.",
                showsCast: false
            )
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
