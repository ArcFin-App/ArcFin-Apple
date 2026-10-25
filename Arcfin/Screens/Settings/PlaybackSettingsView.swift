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
                Picker(selection: $videoQuality) {
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                } label: {
                    TVRowLabelText(title: "Video Quality", detail: "Auto picks from your connection; a fixed choice caps every stream.")
                }
                .tvListRow()
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
                Picker(selection: $playbackEngine) {
                    ForEach(PlaybackEngineKind.allCases, id: \.self) { engine in
                        Text(engine == .auto ? String(localized: "Auto") : engine.rawValue).tag(engine)
                    }
                } label: {
                    TVRowLabelText(title: "Playback Engine", detail: "Auto prefers Aether, which plays the most formats, HDR and surround. If a video won't play, try AVFoundation or VLC.")
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
                    TVRowLabelText(title: "Skip Forward", detail: "For the skip buttons, double-tap and the arrow keys.")
                }
                .tvListRow()
                .syncLocked("skipForwardSeconds", authManager)
                Picker(selection: $skipBackwardSeconds) {
                    ForEach(skipIntervalOptions, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                } label: {
                    TVRowLabelText(title: "Skip Backward", detail: "For the skip buttons, double-tap and the arrow keys.")
                }
                .tvListRow()
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
                    Picker(selection: $upNextCountdownSeconds) {
                        ForEach([3, 4, 5], id: \.self) { seconds in
                            Text("\(seconds)s").tag(seconds)
                        }
                    } label: {
                        TVRowLabelText(title: "Countdown", detail: "How long the button fills before an automatic skip or the next episode.")
                    }
                    .tvListRow()
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
                    Picker(selection: $defaultPlaybackSpeed) {
                        ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                            Text(rate == 1 ? "Normal" : "\(rate.formatted())×").tag(rate)
                        }
                    } label: {
                        TVRowLabelText(title: "Default Speed", detail: "The speed new videos start at.")
                    }
                    .tvListRow()
                    .syncLocked("defaultPlaybackSpeed", authManager)
                }
            } footer: {
                Text("Skip buttons show when your server knows where a recap, intro, credits or preview is, from the Intro Skipper, Chapter Segments Provider or SkipMe.db plugins.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Picker(selection: $resumeBehavior) {
                    ForEach(ResumeBehavior.allCases) { option in
                        Text(option.label).tag(option)
                    }
                } label: {
                    TVRowLabelText(title: "When Resuming", detail: "What Play does for a title you've started.")
                }
                .tvListRow()
                .syncLocked(ResumeBehavior.key, authManager)
                Picker(selection: $watchedThreshold) {
                    ForEach(WatchedThreshold.allCases) { option in
                        Text(option.label).tag(option)
                    }
                } label: {
                    TVRowLabelText(title: "Mark as Watched", detail: "When closing the player counts a title as watched. Server Default uses your server's setting, usually 90%.")
                }
                .tvListRow()
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
                Picker(selection: $preferredAudioLanguage) {
                    ForEach(Self.audioLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                } label: {
                    TVRowLabelText(title: "Preferred Audio Language", detail: "Starts on this language when a title has it.")
                }
                .tvListRow()
                .syncLocked("preferredAudioLanguage", authManager)
                Picker(selection: $preferredSubtitleLanguage) {
                    ForEach(Self.subtitleLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                } label: {
                    TVRowLabelText(title: "Preferred Subtitle Language", detail: "Starts on this language when a title has it.")
                }
                .tvListRow()
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
                    CodecProfileSettingsView()
                } label: {
                    TVRowLabelText(title: "Codec Compatibility", detail: "Which formats this device is told it can play.")
                }
                .tvListRow()
                NavigationLink {
                    PlayerFeaturesSettingsView()
                } label: {
                    TVRowLabelText(title: "Player Features", detail: "Picture in Picture, gestures, chapters and more.")
                }
                .tvListRow()
                NavigationLink {
                    SubtitleStyleSettingsView()
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

/// Settings › Playback › When Resuming: what Play does for a title that's part-watched.
enum ResumeBehavior: String, CaseIterable, Identifiable {
    case ask, resume, startOver
    static let key = "resumeBehavior"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ask: String(localized: "Ask")
        case .resume: String(localized: "Resume")
        case .startOver: String(localized: "Start Over")
        }
    }
    static var current: ResumeBehavior {
        ResumeBehavior(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .resume
    }
}

/// Settings › Playback › Mark as Watched: how far in closing the player counts as finished.
enum WatchedThreshold: String, CaseIterable, Identifiable {
    case server, credits, eighty, eightyFive
    static let key = "markWatchedAt"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .server: String(localized: "Server Default")
        case .credits: String(localized: "When Credits Start")
        case .eighty: String(localized: "At 80%")
        case .eightyFive: String(localized: "At 85%")
        }
    }
    static var current: WatchedThreshold {
        WatchedThreshold(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .server
    }

    /// Whether stopping at `seconds` of `duration` counts, given where the credits start.
    func isReached(seconds: Double, duration: Double, creditsStart: Double?) -> Bool {
        guard duration > 0 else { return false }
        switch self {
        case .server: return false
        case .credits: return seconds >= (creditsStart ?? duration * 0.95)
        case .eighty: return seconds / duration >= 0.8
        case .eightyFive: return seconds / duration >= 0.85
        }
    }
}

#Preview {
    NavigationStack { PlaybackSettingsView() }
        .environment(AuthManager())
}
