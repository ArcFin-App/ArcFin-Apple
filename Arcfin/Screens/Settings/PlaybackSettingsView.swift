// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine

struct PlaybackSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("videoQuality")    private var videoQuality    = VideoQuality.max
    @AppStorage("playbackEngine")  private var playbackEngine  = PlaybackEngineKind.auto
    @AppStorage("autoPlayNext")    private var autoPlayNext    = true
    @AppStorage("skipIntro")       private var skipIntro       = false
    @AppStorage("skipCredits")     private var skipCredits     = false
    @AppStorage("skipRecap")       private var skipRecap       = false
    @AppStorage("subtitleDefault") private var subtitleDefault = false
    @AppStorage("trailersEnabled") private var trailersEnabled = true
    @AppStorage("youtubeTrailersEnabled") private var youtubeTrailersEnabled = true
    @AppStorage("preferredAudioLanguage")    private var preferredAudioLanguage    = ""
    @AppStorage("preferredSubtitleLanguage") private var preferredSubtitleLanguage = ""
    @AppStorage("rememberPlaybackSpeed") private var rememberPlaybackSpeed = false
    @AppStorage(ShowTrackMemory.enabledKey) private var rememberTracksPerShow = true
    @State private var rememberedShowCount = ShowTrackMemory.rememberedShowCount
    @AppStorage("skipForwardSeconds")  private var skipForwardSeconds  = 10
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 10

    private static let audioLanguageOptions: [(code: String, name: String)] = [
        ("", "None"),
        ("eng", "English"),
        ("spa", "Spanish"),
        ("fre", "French"),
        ("ger", "German"),
        ("jpn", "Japanese"),
        ("kor", "Korean"),
        ("chi", "Chinese"),
        ("ita", "Italian"),
        ("por", "Portuguese"),
        ("rus", "Russian"),
    ]
    private static let subtitleLanguageOptions: [(code: String, name: String)] = [
        ("", "Off"),
        ("eng", "English"),
        ("spa", "Spanish"),
        ("fre", "French"),
        ("ger", "German"),
        ("jpn", "Japanese"),
        ("kor", "Korean"),
        ("chi", "Chinese"),
        ("ita", "Italian"),
        ("por", "Portuguese"),
        ("rus", "Russian"),
    ]

    var body: some View {
        List {
            Section {
                Picker(selection: $videoQuality) {
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                } label: {
                    TVRowLabelText(title: "Video Quality")
                }
                .tvListRow()
                .syncLocked("videoQuality", authManager)
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: $playbackEngine) {
                        ForEach(PlaybackEngineKind.allCases, id: \.self) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    } label: {
                        TVRowLabelText(title: "Playback Engine")
                    }
                    Text("Auto is recommended and prefers Aether, which handles the widest range of formats, HDR, and surround/Atmos audio. If a video won't play, switch to AVFoundation or VLC directly — then back to Auto once it's fixed.")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .tvListRow()
                .syncLocked("playbackEngine", authManager)
            }

            Section {
                Picker(selection: $skipForwardSeconds) {
                    ForEach(skipIntervalOptions, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                } label: {
                    TVRowLabelText(title: "Skip Forward")
                }
                .tvListRow()
                .syncLocked("skipForwardSeconds", authManager)
                Picker(selection: $skipBackwardSeconds) {
                    ForEach(skipIntervalOptions, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                } label: {
                    TVRowLabelText(title: "Skip Backward")
                }
                .tvListRow()
                .syncLocked("skipBackwardSeconds", authManager)
            } footer: {
                Text("Used by the on-screen skip buttons, double-tap to seek, and the left/right arrow keys.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $autoPlayNext) {
                    TVRowLabelText(title: "Auto-play Next Episode")
                }
                .tvListRow()
                .syncLocked("autoPlayNext", authManager)
                Toggle(isOn: $skipRecap) {
                    TVRowLabelText(title: "Skip Recap Automatically")
                }
                .tvListRow()
                .syncLocked("skipRecap", authManager)
                Toggle(isOn: $skipIntro) {
                    TVRowLabelText(title: "Skip Intro Automatically")
                }
                .tvListRow()
                .syncLocked("skipIntro", authManager)
                Toggle(isOn: $skipCredits) {
                    TVRowLabelText(title: "Skip Credits Automatically")
                }
                .tvListRow()
                .syncLocked("skipCredits", authManager)
                Toggle(isOn: $subtitleDefault) {
                    TVRowLabelText(title: "Show Subtitles by Default")
                }
                .tvListRow()
                .syncLocked("subtitleDefault", authManager)
                Toggle(isOn: $rememberPlaybackSpeed) {
                    TVRowLabelText(title: "Remember Playback Speed")
                }
                .tvListRow()
                .syncLocked("rememberPlaybackSpeed", authManager)
            } footer: {
                Text("Starts new videos at the speed you last picked instead of 1×.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $trailersEnabled) {
                    TVRowLabelText(title: "Trailers")
                }
                .tvListRow()
                .syncLocked("trailersEnabled", authManager)
                #if !os(tvOS)
                // YouTubeTrailerPlayerView (YouTubePlayerKit, needs WebKit) isn't available
                // on tvOS at all — only a local trailer indexed on the server plays there.
                if trailersEnabled {
                    Toggle("YouTube Fallback", isOn: $youtubeTrailersEnabled)
                        .syncLocked("youtubeTrailersEnabled", authManager)
                }
                #endif
            } footer: {
                #if os(tvOS)
                Text(trailersEnabled
                     ? "Shows a Play Trailer button when the server has a local trailer indexed."
                     : "Turns off trailer playback entirely.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                #else
                Text(trailersEnabled
                     ? "Shows a Play Trailer button when the server has a local trailer indexed. YouTube Fallback plays a YouTube trailer in-app when no local one is available."
                     : "Turns off trailer playback entirely, including the YouTube fallback.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                #endif
            }

            Section {
                Picker(selection: $preferredAudioLanguage) {
                    ForEach(Self.audioLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                } label: {
                    TVRowLabelText(title: "Preferred Audio Language")
                }
                .tvListRow()
                .syncLocked("preferredAudioLanguage", authManager)
                Picker(selection: $preferredSubtitleLanguage) {
                    ForEach(Self.subtitleLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                } label: {
                    TVRowLabelText(title: "Preferred Subtitle Language")
                }
                .tvListRow()
                .syncLocked("preferredSubtitleLanguage", authManager)
            } footer: {
                Text("Used to pick a starting audio/subtitle track when a title has a matching language available — otherwise falls back to the server's default.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $rememberTracksPerShow) {
                    TVRowLabelText(title: "Remember Tracks Per Show")
                }
                .tvListRow()
                .syncLocked(ShowTrackMemory.enabledKey, authManager)
                if rememberTracksPerShow, rememberedShowCount > 0 {
                    Button(role: .destructive) {
                        ShowTrackMemory.clear()
                        rememberedShowCount = 0
                    } label: {
                        Text("Forget \(rememberedShowCount) Remembered \(rememberedShowCount == 1 ? "Show" : "Shows")")
                    }
                }
            } footer: {
                Text("Pick Japanese audio or turn subtitles off once, and the rest of that show's episodes start the same way. Overrides the preferred languages above for shows you've adjusted.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                NavigationLink {
                    CodecProfileSettingsView()
                } label: {
                    Text("Codec Compatibility")
                }
                .tvListRow()
                NavigationLink {
                    PlayerFeaturesSettingsView()
                } label: {
                    Text("Player Features")
                }
                .tvListRow()
                NavigationLink {
                    SubtitleStyleSettingsView()
                } label: {
                    Text("Subtitle Style")
                }
                .tvListRow()
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Playback")
    }
}

#Preview {
    NavigationStack { PlaybackSettingsView() }
        .environment(AuthManager())
}
