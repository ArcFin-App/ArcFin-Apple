// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Settings › Music › Streaming: the quality songs stream at, on Wi-Fi and on mobile data.
struct MusicStreamingSection: View {
    var showsMobileData = true
    @Environment(AuthManager.self) private var authManager
    @AppStorage(MusicSettings.streamQualityKey) private var quality = MusicQuality.original
    @AppStorage(MusicSettings.mobileStreamQualityKey) private var mobileQuality = ""

    var body: some View {
        Section {
            SettingsPicker("Streaming Quality", detail: "Original plays each song as it is. A lower rate has your server convert songs to MP3, using less data.",
                           selection: $quality, options: MusicQuality.allCases) { Text($0.label) }
                .syncLocked(MusicSettings.streamQualityKey, authManager)
            if showsMobileData {
                Picker(selection: $mobileQuality) {
                    Text("Same as Wi-Fi").tag("")
                    ForEach(MusicQuality.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    TVRowLabelText(title: "Quality on Mobile Data", detail: "Used instead when you're on mobile data.")
                }
                .syncLocked(MusicSettings.mobileStreamQualityKey, authManager)
            }
        } header: {
            Text("Streaming")
        }
    }
}

/// Settings › Music › Downloads: the quality songs are saved at, and whether they wait for Wi-Fi.
struct MusicDownloadSettingsSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(MusicSettings.downloadQualityKey) private var quality = MusicQuality.original
    @AppStorage(MusicSettings.downloadOnMobileDataKey) private var onMobileData = false

    var body: some View {
        Section {
            SettingsPicker("Download Quality", detail: "Original saves each song as it is where this device plays it. A lower rate saves MP3s that take less space.",
                           selection: $quality, options: MusicQuality.allCases) { Text($0.label) }
                .syncLocked(MusicSettings.downloadQualityKey, authManager)
            Toggle(isOn: $onMobileData) {
                TVRowLabelText(title: "Download on Mobile Data", detail: "Off, music downloads wait for Wi-Fi. Charges may apply.")
            }
            .syncLocked(MusicSettings.downloadOnMobileDataKey, authManager)
        } header: {
            Text("Downloads")
        }
    }
}

/// Settings › Music › Appearance.
struct MusicAppearanceSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(MusicSettings.visualizerKey) private var visualizer = true

    var body: some View {
        Section {
            Toggle(isOn: $visualizer) {
                TVRowLabelText(title: "Visualizer", detail: "Glass bars that move with the music along the bottom of the cover in Now Playing. Hidden when Reduce Motion is on.")
            }
            .tvListRow()
            .syncLocked(MusicSettings.visualizerKey, authManager)
        } header: {
            Text("Appearance")
        }
    }
}
