import SwiftUI

/// Subtitle appearance shared by both players — read back via the same @AppStorage keys from
/// PlayerView+Controls.swift and OfflinePlayerView.swift.
struct SubtitleStyleSettingsView: View {
    @AppStorage("subtitleTextSize") private var size = SubtitleTextSize.medium
    @AppStorage("subtitleTextColor") private var color = SubtitleTextColorOption.white
    @AppStorage("subtitleBackgroundStyle") private var background = SubtitleBackgroundStyle.box

    var body: some View {
        List {
            Section {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.black)
                    SubtitleText(text: "Like this.", size: size, color: color, background: background)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 90)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("Size", selection: $size) {
                    ForEach(SubtitleTextSize.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Picker("Color", selection: $color) {
                    ForEach(SubtitleTextColorOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                Picker("Background", selection: $background) {
                    ForEach(SubtitleBackgroundStyle.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Subtitle Style")
    }
}

#Preview {
    NavigationStack { SubtitleStyleSettingsView() }
}
