// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Advanced/power-user override of what the client tells Jellyfin it can play directly —
/// read by JellyfinPlaybackClient's deviceProfile via plain UserDefaults (it's a struct,
/// not a View, so no @AppStorage there), same keys as declared here.
struct CodecProfileSettingsView: View {
    @AppStorage("codecAllowHEVCDirectPlay") private var allowHEVC = true
    @AppStorage("codecAllowSurroundAudioDirectPlay") private var allowSurroundAudio = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $allowHEVC) {
                    TVRowLabelText(title: "Direct Play HEVC (H.265)")
                }
                .tvListRow()
            } footer: {
                Text("On by default. Turn this off if HEVC sources stall or show a black screen on this device — everything falls back to an H.264 transcode instead.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $allowSurroundAudio) {
                    TVRowLabelText(title: "Direct Play Surround Audio (AC3/EAC3/DTS)")
                }
                .tvListRow()
            } footer: {
                Text("Off by default — this device's own speakers/headphones can't decode these, only pass them through to a connected receiver over AirPlay or HDMI. Turn on only if you're always routing audio to a receiver that supports them; otherwise direct-played audio will be silent.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Codec Compatibility")
    }
}

#Preview {
    NavigationStack { CodecProfileSettingsView() }
}
