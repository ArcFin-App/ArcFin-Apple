// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine

struct PlaybackSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("videoQuality")    private var videoQuality    = VideoQuality.max
    @AppStorage("playbackEngine")  private var playbackEngine  = PlaybackEngineKind.auto
    @AppStorage("trailersEnabled") private var trailersEnabled = true

    var body: some View {
        List {
            Section {
                SettingsPicker("Video Quality", detail: "Auto picks from your connection; a fixed choice caps every stream.", selection: $videoQuality,
                               options: VideoQuality.allCases) { q in
                    Text(q.label)
                }
                .syncLocked("videoQuality", authManager)
                SettingsPicker("Playback Engine", detail: "Auto prefers Aether, which plays the most formats, HDR and surround. If a video won't play, try AVFoundation or VLC.", selection: $playbackEngine,
                               options: PlaybackEngineKind.allCases) { engine in
                    Text(engine == .auto ? String(localized: "Auto") : engine.rawValue)
                }
                .syncLocked("playbackEngine", authManager)
            }

            PlaybackSkipIntervalSection()

            PlaybackAutomationSection()

            PlaybackResumeSection()

            Section {
                Toggle(isOn: $trailersEnabled) {
                    TVRowLabelText(title: "Trailers", detail: "Shows Play Trailer when the server has a trailer.")
                }
                .tvListRow()
                .syncLocked("trailersEnabled", authManager)
                // No YouTube fallback: YouTubeTrailerPlayerView (YouTubePlayerKit, needs WebKit)
                // isn't available on tvOS at all — only a local trailer indexed on the server plays there.
            }

            PlaybackLanguageSection()

            PlaybackTrackMemorySection()
            PlaybackEnhancementsSection()

            PlaybackMoreSettingsSection()
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Playback")
    }
}

#Preview {
    NavigationStack { PlaybackSettingsView() }
        .environment(AuthManager())
}
