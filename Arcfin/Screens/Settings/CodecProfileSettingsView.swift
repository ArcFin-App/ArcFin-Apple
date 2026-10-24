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
                    TVRowLabelText(title: "Direct Play HEVC (H.265)", detail: "Turn off if HEVC videos stall or stay black on this device; they'll be converted to H.264 instead.")
                }
                .tvListRow()
            }

            Section {
                Toggle(isOn: $allowSurroundAudio) {
                    TVRowLabelText(title: "Direct Play Surround Audio (AC3/EAC3/DTS)", detail: "Only for audio always going to a receiver over AirPlay or HDMI. This device can't play these itself, so they'd be silent.")
                }
                .tvListRow()
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Codec Compatibility")
    }
}

#Preview {
    NavigationStack { CodecProfileSettingsView() }
}
