// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Subtitle appearance shared by both players — read back via the same @AppStorage keys from
/// PlayerView+Controls.swift and OfflinePlayerView.swift.
struct SubtitleStyleSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("subtitleTextSize") private var size = SubtitleTextSize.medium
    @AppStorage("subtitleTextColor") private var color = SubtitleTextColorOption.white
    @AppStorage("subtitleBackgroundStyle") private var background = SubtitleBackgroundStyle.outline

    var body: some View {
        SettingsForm {
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
                SettingsPicker("Size", selection: $size,
                               options: SubtitleTextSize.allCases) { option in
                    Text(option.label)
                }
                .syncLocked("subtitleTextSize", authManager)
                SettingsPicker("Colour", selection: $color,
                               options: SubtitleTextColorOption.allCases) { option in
                    Text(option.label)
                }
                .syncLocked("subtitleTextColor", authManager)
                SettingsPicker("Background", selection: $background,
                               options: SubtitleBackgroundStyle.allCases) { option in
                    Text(option.label)
                }
                .syncLocked("subtitleBackgroundStyle", authManager)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Subtitle Style")
    }
}

#Preview {
    NavigationStack { SubtitleStyleSettingsView() }
        .environment(AuthManager())
}
