// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Advanced/power-user override of what the client tells Jellyfin it can play directly —
/// read by JellyfinPlaybackClient's deviceProfile via plain UserDefaults (it's a struct,
/// not a View, so no @AppStorage there), same keys as declared here.
struct CodecProfileSettingsView: View {
    @AppStorage("codecAllowHEVCDirectPlay") private var allowHEVC = true
    @AppStorage("codecAllowSurroundAudioDirectPlay") private var allowSurroundAudio = false
    @AppStorage("codecForceHDRTranscode") private var forceHDR = false
    @AppStorage("codecForceDolbyVisionTranscode") private var forceDolbyVision = false
    @AppStorage("codecCompatibilityMode") private var compatibilityMode = false

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

            Section {
                Toggle(isOn: $forceHDR) {
                    TVRowLabelText(title: "Force HDR to Transcode", detail: "The server converts HDR10, HDR10+, HLG and Dolby Vision videos to SDR. Turn on if HDR looks dim, washed out or off-colour on this screen. Needs tone mapping turned on in the server's playback settings.")
                }
                .tvListRow()
                Toggle(isOn: $forceDolbyVision) {
                    TVRowLabelText(title: "Force Dolby Vision to Transcode", detail: "The server sends Dolby Vision videos as HDR10 or SDR instead. Turn on if they show purple or green colours.")
                }
                .tvListRow()
                .disabled(forceHDR)
            }

            Section {
                Toggle(isOn: $compatibilityMode) {
                    TVRowLabelText(title: "Compatibility Mode", detail: "For videos that won't play at all. The server converts anything that isn't H.264 and AAC, in SDR with stereo sound. Uses more of the server's power, so turn it off once the video plays.")
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
