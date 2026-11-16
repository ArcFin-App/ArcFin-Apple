// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine

/// Settings › Music › Playback: how songs sound and run into each other.
struct MusicPlaybackSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(MusicSettings.soundCheckKey) private var soundCheck = false
    @AppStorage(MusicSettings.equalizerKey) private var equalizer = MusicEqualizer.off
    @AppStorage(MusicSettings.crossfadeKey) private var crossfade = 0
    @AppStorage(MusicSettings.autoplayKey) private var autoplay = true
    @AppStorage(MusicSettings.rememberQueueKey) private var rememberQueue = true

    var body: some View {
        Section {
            SettingsPicker("Crossfade", detail: "Fades each song into the next. Off, songs run into each other with no gap, as albums are made to play. Not on a Chromecast.",
                           selection: $crossfade, options: MusicSettings.crossfadeOptions) { seconds in
                seconds == 0 ? Text("Off") : Text(Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide)))
            }
            .syncLocked(MusicSettings.crossfadeKey, authManager)
            Toggle(isOn: $soundCheck) {
                TVRowLabelText(title: "Sound Check", detail: "Plays songs at about the same volume, using the loudness your server measured for each. Needs Jellyfin 10.9 or later.")
            }
            .tvListRow()
            .syncLocked(MusicSettings.soundCheckKey, authManager)
            SettingsPicker("Equalizer", detail: "Shapes the sound of everything that plays here, including on AirPlay. Not on a Chromecast.",
                           selection: $equalizer, options: MusicEqualizer.allCases) { Text($0.label) }
                .syncLocked(MusicSettings.equalizerKey, authManager)
            Toggle(isOn: $autoplay) {
                TVRowLabelText(title: "Autoplay", detail: "When the last song in Playing Next starts, similar music is added after it, so it keeps playing.")
            }
            .tvListRow()
            .syncLocked(MusicSettings.autoplayKey, authManager)
            Toggle(isOn: $rememberQueue) {
                TVRowLabelText(title: "Remember What's Playing", detail: "Opening Arcfin again brings back the song and Playing Next, paused where you left them.")
            }
            .tvListRow()
            .syncLocked(MusicSettings.rememberQueueKey, authManager)
        } header: {
            Text("Playback")
        }
    }
}

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
