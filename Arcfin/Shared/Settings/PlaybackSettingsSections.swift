// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Settings › Playback › Skip Forward and Skip Backward.
struct PlaybackSkipIntervalSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("skipForwardSeconds")  private var skipForwardSeconds  = 10
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 10

    var body: some View {
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
    }
}

/// Settings › Playback: auto-play, the automatic skips, subtitles and speed.
struct PlaybackAutomationSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("autoPlayNext")    private var autoPlayNext    = true
    @AppStorage("skipIntro")       private var skipIntro       = false
    @AppStorage("skipCredits")     private var skipCredits     = false
    @AppStorage("skipRecap")       private var skipRecap       = false
    @AppStorage("skipCommercials") private var skipCommercials = false
    @AppStorage("subtitleDefault") private var subtitleDefault = false
    @AppStorage("subtitlesWhenMuted") private var subtitlesWhenMuted = true
    @AppStorage("rememberPlaybackSpeed") private var rememberPlaybackSpeed = false
    @AppStorage("upNextCountdownSeconds") private var upNextCountdownSeconds = 5
    @AppStorage("defaultPlaybackSpeed") private var defaultPlaybackSpeed = 1.0
    @AppStorage(PlayerModel.holdSpeedKey) private var holdSpeed = 2.0

    var body: some View {
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
            Toggle(isOn: $skipCommercials) {
                TVRowLabelText(title: "Skip Ads Automatically", detail: "Skips ad breaks in recordings when the server knows where they are.")
            }
            .tvListRow()
            .syncLocked("skipCommercials", authManager)
            if autoPlayNext || skipRecap || skipIntro || skipCredits || skipCommercials {
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
            if PlatformMetrics.detectsMutedSound {
                Toggle(isOn: $subtitlesWhenMuted) {
                    TVRowLabelText(title: "Show Subtitles When Muted", detail: "Turns subtitles on while the sound is all the way down, and off again when it comes back.")
                }
                .tvListRow()
                .syncLocked("subtitlesWhenMuted", authManager)
            }
            SettingsPicker("Hold Speed", detail: PlatformMetrics.holdSpeedHint, selection: $holdSpeed,
                           options: PlayerModel.holdSpeedOptions.map(Double.init)) { rate in
                Text("\(rate.formatted())×")
            }
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
    }
}

/// Settings › Playback › When Resuming and Mark as Watched.
struct PlaybackResumeSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(ResumeBehavior.key) private var resumeBehavior = ResumeBehavior.resume
    @AppStorage(WatchedThreshold.key) private var watchedThreshold = WatchedThreshold.server

    var body: some View {
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
    }
}

/// Settings › Playback › Preferred Audio Language and Preferred Subtitle Language.
struct PlaybackLanguageSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("preferredAudioLanguage")    private var preferredAudioLanguage    = ""
    @AppStorage("preferredSubtitleLanguage") private var preferredSubtitleLanguage = ""

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
    }
}

/// Settings › Playback › Remember Tracks Per Show.
struct PlaybackTrackMemorySection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(ShowTrackMemory.enabledKey) private var rememberTracksPerShow = true
    @State private var rememberedShowCount = ShowTrackMemory.rememberedShowCount
    @State private var confirmingForget = false

    var body: some View {
        Section {
            Toggle(isOn: $rememberTracksPerShow) {
                TVRowLabelText(title: "Remember Tracks Per Show", detail: "Change audio or subtitles once and the rest of that show starts the same way.")
            }
            .tvListRow()
            .syncLocked(ShowTrackMemory.enabledKey, authManager)
            if rememberTracksPerShow, rememberedShowCount > 0 {
                Button(role: .destructive) {
                    confirmingForget = true
                } label: {
                    Text("Forget Remembered Shows (\(rememberedShowCount))")
                }
                .confirmationDialog("Forget Remembered Shows?", isPresented: $confirmingForget, titleVisibility: .visible) {
                    Button("Forget", role: .destructive) {
                        ShowTrackMemory.clear()
                        rememberedShowCount = 0
                    }
                } message: {
                    Text("Each show starts with your default audio and subtitles again.")
                }
            }
        }
    }
}

/// Aether's sound and picture enhancements: quiet audio, animation upscaling, and how far
/// Subtitle Timing reaches for picture subtitles.
struct PlaybackEnhancementsSection: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(PlayerModel.raiseQuietAudioKey) private var raiseQuietAudio = false
    @AppStorage(PlayerModel.animationUpscalingKey) private var animationUpscaling = false
    @AppStorage(PlayerModel.subtitleReachLaterKey) private var reachLater = 60
    @AppStorage(PlayerModel.subtitleReachEarlierKey) private var reachEarlier = 60

    var body: some View {
        Section {
            Toggle(isOn: $raiseQuietAudio) {
                TVRowLabelText(title: "Raise Quiet Audio", detail: "Brings a quiet film up to an everyday volume, without making loud ones louder. Also in the player's Subtitles & Audio menu.")
            }
            .tvListRow()
            .syncLocked(PlayerModel.raiseQuietAudioKey, authManager)
            Toggle(isOn: $animationUpscaling) {
                TVRowLabelText(title: "Animation Upscaling", detail: "Sharpens anime and cartoons on a larger screen, for titles in an Anime or Animation genre; you can turn it off for one in the player. It's heavy on the graphics chip: if playback stutters or drops frames, turn it off.")
            }
            .tvListRow()
            .syncLocked(PlayerModel.animationUpscalingKey, authManager)
            SettingsPicker("Subtitle Timing: Later", detail: "How far Subtitle Timing can move picture subtitles later.", selection: $reachLater,
                           options: PlayerModel.subtitleReachOptions) { Text(Self.reachLabel($0)) }
            .syncLocked(PlayerModel.subtitleReachLaterKey, authManager)
            SettingsPicker("Subtitle Timing: Earlier", detail: "How far it can move them earlier. A longer reach reads further ahead over the network.", selection: $reachEarlier,
                           options: PlayerModel.subtitleReachOptions) { Text(Self.reachLabel($0)) }
            .syncLocked(PlayerModel.subtitleReachEarlierKey, authManager)
        } header: {
            Text("Aether")
        } footer: {
            Text("These need the Aether player engine, which Auto uses for most videos.")
        }
    }

    private static func reachLabel(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes], width: .wide))
    }
}

/// Settings › Playback's links to Codec Compatibility, Player Features and Subtitle Style.
struct PlaybackMoreSettingsSection: View {
    var body: some View {
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
}

/// Settings › Playback › Default Player, on iPhone, iPad and Mac: Play opens a movie or
/// episode in another installed app instead.
struct PlaybackDefaultPlayerSection: View {
    @AppStorage(ExternalPlayer.defaultPlayerKey) private var defaultPlayer = ""
    @State private var installed: [ExternalPlayer] = []

    var body: some View {
        Section {
            if !installed.isEmpty {
                Picker(selection: $defaultPlayer) {
                    Text(verbatim: "Arcfin").tag("")
                    ForEach(installed) { player in
                        Text(verbatim: player.name).tag(player.id)
                    }
                } label: {
                    TVRowLabelText(title: "Default Player", detail: "Play opens movies and episodes in this app.")
                }
            }
        } footer: {
            if !installed.isEmpty, !defaultPlayer.isEmpty {
                Text("Titles start from the beginning there, and what you watch isn't saved to your server.")
            }
        }
        .task { installed = ExternalPlayer.installed }
    }
}
