// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
@testable import JellyfinAPI

@Suite("Download conversion")
struct DownloadEncodingTests {
    @Test func hevcWhenTheServerAllowsIt() {
        let encoding = DownloadEncoding.choose(allowsHEVC: true, allowsAV1: false, encodesAV1: nil)
        #expect(encoding.videoCodecs == "hevc,h264")
        #expect(encoding.codec == "hevc")
        #expect(encoding.videoBitrate(forTier: 8_000_000, sourceBitrate: 20_000_000, sourceCodec: "h264") == 4_800_000)
    }

    @Test func h264OnlyWhenHEVCIsOff() {
        let encoding = DownloadEncoding.choose(allowsHEVC: false, allowsAV1: true, encodesAV1: false)
        #expect(encoding.videoCodecs == "h264")
        #expect(encoding.videoBitrate(forTier: 8_000_000, sourceBitrate: 20_000_000, sourceCodec: "h264") == 8_000_000)
    }

    @Test func unknownSettingsKeepTodaysBitrate() {
        let encoding = DownloadEncoding.choose(allowsHEVC: nil, allowsAV1: nil, encodesAV1: nil)
        #expect(encoding == .unknown)
        #expect(encoding.videoBitrate(forTier: 8_000_000, sourceBitrate: 5_000_000, sourceCodec: "hevc") == 5_000_000)
    }

    @Test func av1OnlyWhenAllowedAndTested() {
        let untested = DownloadEncoding.choose(allowsHEVC: true, allowsAV1: true, encodesAV1: nil)
        #expect(untested.codec == "hevc")
        let tested = DownloadEncoding.choose(allowsHEVC: true, allowsAV1: true, encodesAV1: true)
        #expect(tested.codec == (JellyfinMediaClient.decodesAV1InHardware ? "av1" : "hevc"))
    }

    @Test func neverAboveTheSourcesOwnPicture() {
        let hevc = DownloadEncoding.choose(allowsHEVC: true, allowsAV1: false, encodesAV1: nil)
        // An HEVC source at 3 Mb/s is already smaller than the 8 Mb/s tier would be.
        #expect(hevc.videoBitrate(forTier: 8_000_000, sourceBitrate: 3_000_000, sourceCodec: "hevc") == 3_000_000)
        #expect(hevc.keepsOriginal(forTier: 8_000_000, sourceBitrate: 3_000_000, sourceCodec: "hevc"))
        #expect(!hevc.keepsOriginal(forTier: 1_000_000, sourceBitrate: 3_000_000, sourceCodec: "hevc"))
    }

    @Test func noSourceBitrateUsesTheTier() {
        let hevc = DownloadEncoding.choose(allowsHEVC: true, allowsAV1: false, encodesAV1: nil)
        #expect(hevc.videoBitrate(forTier: 4_000_000, sourceBitrate: nil, sourceCodec: nil) == 2_400_000)
        #expect(!hevc.keepsOriginal(forTier: 4_000_000, sourceBitrate: nil, sourceCodec: nil))
    }
}
