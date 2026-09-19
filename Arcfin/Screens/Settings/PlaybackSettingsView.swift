import SwiftUI
import MediaEngine

struct PlaybackSettingsView: View {
    @AppStorage("videoQuality")    private var videoQuality    = VideoQuality.max
    @AppStorage("playbackEngine")  private var playbackEngine  = PlaybackEngineKind.auto
    @AppStorage("autoPlayNext")    private var autoPlayNext    = true
    @AppStorage("skipIntro")       private var skipIntro       = false
    @AppStorage("skipCredits")     private var skipCredits     = false
    @AppStorage("subtitleDefault") private var subtitleDefault = false

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
                Toggle("Skip Intro Automatically", isOn: $skipIntro)
                Toggle("Skip Credits Automatically", isOn: $skipCredits)
                Toggle("Show Subtitles by Default", isOn: $subtitleDefault)
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
