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
    @AppStorage("mobileVideoQuality") private var mobileVideoQuality = ""
    @AppStorage("upNextCountdownSeconds") private var upNextCountdownSeconds = 5
    @AppStorage(ResumeBehavior.key) private var resumeBehavior = ResumeBehavior.resume
    @AppStorage(WatchedThreshold.key) private var watchedThreshold = WatchedThreshold.server
    @AppStorage("defaultPlaybackSpeed") private var defaultPlaybackSpeed = 1.0

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
                SettingsPicker("Video Quality", detail: "Auto picks from your connection; a fixed choice caps every stream.", selection: $videoQuality,
                               options: VideoQuality.allCases) { q in
                    Text(q.label)
                }
                .syncLocked("videoQuality", authManager)
                #if os(iOS)
                Picker(selection: $mobileVideoQuality) {
                    Text("Same as Wi-Fi").tag("")
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.label).tag(q.rawValue)
                    }
                } label: {
                    TVRowLabelText(title: "Quality on Mobile Data", detail: "Used instead when you're on mobile data.")
                }
                .syncLocked("mobileVideoQuality", authManager)
                #endif
                SettingsPicker("Playback Engine", detail: "Auto prefers Aether, which plays the most formats, HDR and surround. If a video won't play, try AVFoundation or VLC.", selection: $playbackEngine,
                               options: PlaybackEngineKind.allCases) { engine in
                    Text(engine == .auto ? String(localized: "Auto") : engine.rawValue)
                }
                .syncLocked("playbackEngine", authManager)
            }

            Section {
                SettingsPicker("Skip Forward", detail: "For the skip buttons, double-tap and the arrow keys.", selection: $skipForwardSeconds,
                               options: skipIntervalOptions) { seconds in
                    Text("\(seconds)s")
                }
                .syncLocked("skipForwardSeconds", authManager)
                SettingsPicker("Skip Backward", detail: "For the skip buttons, double-tap and the arrow keys.", selection: $skipBackwardSeconds,
                               options: skipIntervalOptions) { seconds in
                    Text("\(seconds)s")
                }
                .syncLocked("skipBackwardSeconds", authManager)
            }

            Section {
                Toggle(isOn: $autoPlayNext) {
                    TVRowLabelText(title: "Auto-play Next Episode", detail: "Starts the next episode when the credits roll.")
                }
                .tvListRow()
                .syncLocked("autoPlayNext", authManager)
                Toggle(isOn: $skipRecap) {
                    TVRowLabelText(title: "Skip Recap Automatically", detail: "Skips a recap when the server knows where it is.")
                }
                .tvListRow()
                .syncLocked("skipRecap", authManager)
                Toggle(isOn: $skipIntro) {
                    TVRowLabelText(title: "Skip Intro Automatically", detail: "Skips the intro when the server knows where it is.")
                }
                .tvListRow()
                .syncLocked("skipIntro", authManager)
                Toggle(isOn: $skipCredits) {
                    TVRowLabelText(title: "Skip Credits Automatically", detail: "Skips the credits, or moves on to what's next.")
                }
                .tvListRow()
                .syncLocked("skipCredits", authManager)
                if autoPlayNext || skipRecap || skipIntro || skipCredits {
                    SettingsPicker("Countdown", detail: "How long the button fills before an automatic skip or the next episode.", selection: $upNextCountdownSeconds,
                                   options: [3, 4, 5]) { seconds in
                        Text("\(seconds)s")
                    }
                    .syncLocked("upNextCountdownSeconds", authManager)
                    // Earlier versions offered up to 15 s.
                    .onAppear { upNextCountdownSeconds = min(max(upNextCountdownSeconds, 3), 5) }
                }
                Toggle(isOn: $subtitleDefault) {
                    TVRowLabelText(title: "Show Subtitles by Default", detail: "Turns on a subtitle track when a video starts.")
                }
                .tvListRow()
                .syncLocked("subtitleDefault", authManager)
                Toggle(isOn: $rememberPlaybackSpeed) {
                    TVRowLabelText(title: "Remember Playback Speed", detail: "New videos start at the speed you last picked.")
                }
                .tvListRow()
                .syncLocked("rememberPlaybackSpeed", authManager)
                if !rememberPlaybackSpeed {
                    SettingsPicker("Default Speed", detail: "The speed new videos start at.", selection: $defaultPlaybackSpeed,
                                   options: [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]) { rate in
                        Text(rate == 1 ? "Normal" : "\(rate.formatted())×")
                    }
                    .syncLocked("defaultPlaybackSpeed", authManager)
                }
            } footer: {
                Text("Skip buttons show when your server knows where a recap, intro, credits or preview is, from the Intro Skipper, Chapter Segments Provider or SkipMe.db plugins.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                SettingsPicker("When Resuming", detail: "What Play does for a title you've started.", selection: $resumeBehavior,
                               options: ResumeBehavior.allCases) { option in
                    Text(option.label)
                }
                .syncLocked(ResumeBehavior.key, authManager)
                SettingsPicker("Mark as Watched", detail: "When closing the player counts a title as watched. Server Default uses your server's setting, usually \(0.9.formatted(.percent)).", selection: $watchedThreshold,
                               options: WatchedThreshold.allCases) { option in
                    Text(option.label)
                }
                .syncLocked(WatchedThreshold.key, authManager)
            }

            Section {
                Toggle(isOn: $trailersEnabled) {
                    TVRowLabelText(title: "Trailers", detail: "Shows Play Trailer when the server has a trailer.")
                }
                .tvListRow()
                .syncLocked("trailersEnabled", authManager)
                #if !os(tvOS)
                // YouTubeTrailerPlayerView (YouTubePlayerKit, needs WebKit) isn't available
                // on tvOS at all — only a local trailer indexed on the server plays there.
                if trailersEnabled {
                    Toggle(isOn: $youtubeTrailersEnabled) {
                        TVRowLabelText(title: "YouTube Fallback", detail: "Plays a YouTube trailer when the server has none.")
                    }
                    .syncLocked("youtubeTrailersEnabled", authManager)
                }
                #endif
            }

            Section {
                SettingsPicker("Preferred Audio Language", detail: "Starts on this language when a title has it.",
                               selection: $preferredAudioLanguage, options: Self.audioLanguageOptions.map(\.code)) { code in
                    Text(Self.audioLanguageOptions.first { $0.code == code }?.name ?? code)
                }
                .syncLocked("preferredAudioLanguage", authManager)
                SettingsPicker("Preferred Subtitle Language", detail: "Starts on this language when a title has it.",
                               selection: $preferredSubtitleLanguage, options: Self.subtitleLanguageOptions.map(\.code)) { code in
                    Text(Self.subtitleLanguageOptions.first { $0.code == code }?.name ?? code)
                }
                .syncLocked("preferredSubtitleLanguage", authManager)
            }

            Section {
                Toggle(isOn: $rememberTracksPerShow) {
                    TVRowLabelText(title: "Remember Tracks Per Show", detail: "Change audio or subtitles once and the rest of that show starts the same way.")
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
            }

            Section {
                NavigationLink {
                    CodecProfileSettingsView().tvSettingsPage()
                } label: {
                    TVRowLabelText(title: "Codec Compatibility", detail: "Which formats this device is told it can play.")
                }
                .tvListRow()
                NavigationLink {
                    PlayerFeaturesSettingsView().tvSettingsPage()
                } label: {
                    TVRowLabelText(title: "Player Features", detail: "Picture in Picture, gestures, chapters and more.")
                }
                .tvListRow()
                NavigationLink {
                    SubtitleStyleSettingsView().tvSettingsPage()
                } label: {
                    TVRowLabelText(title: "Subtitle Style", detail: "Size, colour and background of subtitles.")
                }
                .tvListRow()
            }
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
