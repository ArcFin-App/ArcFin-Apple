import SwiftUI
import MediaEngine

struct PlaybackSettingsView: View {
    @AppStorage("videoQuality")    private var videoQuality    = VideoQuality.max
    @AppStorage("playbackEngine")  private var playbackEngine  = PlaybackEngineKind.auto
    @AppStorage("autoPlayNext")    private var autoPlayNext    = true
    @AppStorage("skipIntro")       private var skipIntro       = false
    @AppStorage("skipCredits")     private var skipCredits     = false
    @AppStorage("skipRecap")       private var skipRecap       = false
    @AppStorage("subtitleDefault") private var subtitleDefault = false
    @AppStorage("trailersEnabled") private var trailersEnabled = true
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
        List {
            Section {
                Picker("Video Quality", selection: $videoQuality) {
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Playback Engine", selection: $playbackEngine) {
                        ForEach(PlaybackEngineKind.allCases, id: \.self) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    Text("Auto is recommended. If a video won't play, switch to VLC — then back to Auto once it's fixed.")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }

            Section {
                Toggle("Auto-play Next Episode", isOn: $autoPlayNext)
                Toggle("Skip Recap Automatically", isOn: $skipRecap)
                Toggle("Skip Intro Automatically", isOn: $skipIntro)
                Toggle("Skip Credits Automatically", isOn: $skipCredits)
                Toggle("Show Subtitles by Default", isOn: $subtitleDefault)
            }

            Section {
                Toggle("Trailers", isOn: $trailersEnabled)
            } footer: {
                Text("Shows a Trailers row on the detail screen when the server has a local trailer indexed, or a YouTube trailer as a fallback.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Picker("Preferred Audio Language", selection: $preferredAudioLanguage) {
                    ForEach(Self.audioLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                Picker("Preferred Subtitle Language", selection: $preferredSubtitleLanguage) {
                    ForEach(Self.subtitleLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
            } footer: {
                Text("Used to pick a starting audio/subtitle track when a title has a matching language available — otherwise falls back to the server's default.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                NavigationLink {
                    CodecProfileSettingsView()
                } label: {
                    Text("Codec Compatibility")
                }
                NavigationLink {
                    PlayerFeaturesSettingsView()
                } label: {
                    Text("Player Features")
                }
                NavigationLink {
                    SubtitleStyleSettingsView()
                } label: {
                    Text("Subtitle Style")
                }
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Playback")
    }
}

#Preview {
    NavigationStack { PlaybackSettingsView() }
}
