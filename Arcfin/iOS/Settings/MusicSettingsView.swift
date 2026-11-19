// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Settings › Music: everything about how music plays, streams, downloads and looks.
struct MusicSettingsView: View {
    var body: some View {
        List {
            MusicPlaybackSection()
            MusicStreamingSection()
            MusicDownloadSettingsSection()
            Section {
                NavigationLink {
                    MusicDownloadsView()
                } label: {
                    TVRowLabelText(title: "Downloaded Music", detail: "What's saved, the space it takes, and removing it.")
                }
            }
            MusicAppearanceSection()
            MusicLyricsSection()
            MusicServicesSection()
            Section {
                NavigationLink {
                    MusicHistoryImportView()
                } label: {
                    TVRowLabelText(title: "Import Listening History", detail: "Bring your plays from Spotify, Apple Music or YouTube Music to ListenBrainz and Jellyfin.")
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Music")
    }
}
