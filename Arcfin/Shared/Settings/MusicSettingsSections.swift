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
    @AppStorage(MusicSettings.keepFavoritesDownloadedKey) private var keepFavorites = false

    var body: some View {
        Section {
            SettingsPicker("Download Quality", detail: "Original saves each song as it is where this device plays it. A lower rate saves MP3s that take less space.",
                           selection: $quality, options: MusicQuality.allCases) { Text($0.label) }
                .syncLocked(MusicSettings.downloadQualityKey, authManager)
            Toggle(isOn: $onMobileData) {
                TVRowLabelText(title: "Download on Mobile Data", detail: "Off, music downloads wait for Wi-Fi. Charges may apply.")
            }
            .syncLocked(MusicSettings.downloadOnMobileDataKey, authManager)
            Toggle(isOn: $keepFavorites) {
                TVRowLabelText(title: "Keep Favorites Downloaded", detail: "Songs and albums you favorite download by themselves. Turning this on downloads the favorites you already have.")
            }
            .syncLocked(MusicSettings.keepFavoritesDownloadedKey, authManager)
        } header: {
            Text("Downloads")
        }
        .onChange(of: keepFavorites) { _, on in
            if on { Task { await MusicDownloads.shared.downloadAllFavorites() } }
        }
    }
}

/// Settings › Music › Appearance.
struct MusicAppearanceSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(MusicSettings.visualizerKey) private var visualizer = true
    @AppStorage(MusicSettings.visualizerTintKey) private var tint = true

    var body: some View {
        Section {
            Toggle(isOn: $visualizer) {
                TVRowLabelText(title: "Visualizer", detail: "Glass bars that move with the music along the bottom of the cover in Now Playing. Hidden when Reduce Motion is on.")
            }
            .tvListRow()
            .syncLocked(MusicSettings.visualizerKey, authManager)
            if visualizer {
                Toggle(isOn: $tint) {
                    TVRowLabelText(title: "Colour from Cover", detail: "Tints the bars with a colour from the cover, dark over light covers and light over dark ones, so they stand out. Off, they're white glass.")
                }
                .tvListRow()
                .syncLocked(MusicSettings.visualizerTintKey, authManager)
            }
        } header: {
            Text("Appearance")
        }
    }
}

/// Settings › Music › Lyrics: looking up the lyrics the server doesn't have.
struct MusicLyricsSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(MusicSettings.findsLyricsOnlineKey) private var findsOnline = false

    var body: some View {
        Section {
            Toggle(isOn: $findsOnline) {
                TVRowLabelText(title: "Find Missing Lyrics", detail: "Looks up lyrics your server doesn't have on LRCLIB, a free lyrics library, sending it the song's title, artist, album and length.")
            }
            .tvListRow()
            .syncLocked(MusicSettings.findsLyricsOnlineKey, authManager)
        } header: {
            Text("Lyrics")
        }
    }
}

/// Settings › Music › Notifications.
struct MusicNotificationsSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(MusicSettings.notifyDownloadsKey) private var notifyDownloads = true

    var body: some View {
        Section {
            Toggle(isOn: $notifyDownloads) {
                TVRowLabelText(title: "Music Downloads", detail: "Tells you when songs you're downloading are ready to play offline.")
            }
            .syncLocked(MusicSettings.notifyDownloadsKey, authManager)
        } header: {
            Text("Notifications")
        }
    }
}
