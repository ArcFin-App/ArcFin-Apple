// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Settings › Music: how music plays, streams and looks.
struct MusicSettingsView: View {
    var body: some View {
        List {
            MusicPlaybackSection()
            MusicStreamingSection(showsMobileData: false)
            MusicAppearanceSection()
            MusicLyricsSection()
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Music")
    }
}
