// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Device profiles", .serialized)
struct DeviceProfileTests {
    static let server = URL(string: "http://jf.example.com:8096")!

    private func directPlay(_ profile: [String: Any]) -> [[String: Any]] {
        profile["DirectPlayProfiles"] as? [[String: Any]] ?? []
    }

    private func transcoding(_ profile: [String: Any]) -> [String: Any] {
        (profile["TranscodingProfiles"] as? [[String: Any]])?.first ?? [:]
    }

    private func subtitleMethod(_ profile: [String: Any], format: String) -> String? {
        (profile["SubtitleProfiles"] as? [[String: Any]])?
            .first { $0["Format"] as? String == format }?["Method"] as? String
    }

    @Test("AVFoundation never direct-plays mkv")
    func avFoundationNoMKV() {
        let containers = directPlay(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: Self.server))
            .compactMap { $0["Container"] as? String }
            .joined(separator: ",")
        #expect(!containers.split(separator: ",").contains("mkv"))
    }

    @Test("AVFoundation's HLS output carries HEVC in fMP4, so HEVC is repackaged rather than re-encoded")
    func avFoundationHEVCPassthrough() {
        UserDefaults.standard.removeObject(forKey: "codecAllowHEVCDirectPlay")
        let output = transcoding(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: Self.server))
        #expect(output["Container"] as? String == "mp4")
        #expect(output["Protocol"] as? String == "hls")
        #expect((output["VideoCodec"] as? String)?.split(separator: ",").contains("hevc") == true)
    }

    @Test("Turning HEVC off drops it from the output too")
    func hevcToggleOff() {
        UserDefaults.standard.set(false, forKey: "codecAllowHEVCDirectPlay")
        defer { UserDefaults.standard.removeObject(forKey: "codecAllowHEVCDirectPlay") }
        let output = transcoding(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: Self.server))
        #expect((output["VideoCodec"] as? String)?.split(separator: ",").filter { $0 != "av1" } == ["h264"])
    }

    @Test("Chromecast keeps h264 in ts")
    func castOutput() {
        let output = transcoding(JellyfinMediaClient.deviceProfile(forCast: true, baseURL: Self.server))
        #expect(output["Container"] as? String == "ts")
        #expect(output["VideoCodec"] as? String == "h264")
    }

    @Test("Native engines direct-play mkv with no codec limits")
    func nativeDirectPlaysEverything() throws {
        let profiles = directPlay(JellyfinMediaClient.nativeDecoderProfile(baseURL: Self.server))
        let profile = try #require(profiles.first)
        #expect((profile["Container"] as? String)?.split(separator: ",").contains("mkv") == true)
        #expect(profile["VideoCodec"] == nil)
        #expect(profile["AudioCodec"] == nil)
    }

    @Test("Native engines keep image subtitles in the file instead of burning them in")
    func nativeEmbedsImageSubtitles() {
        let profile = JellyfinMediaClient.nativeDecoderProfile(baseURL: Self.server)
        for format in ["pgssub", "dvdsub", "dvbsub"] {
            #expect(subtitleMethod(profile, format: format) == "Embed")
        }
        #expect(subtitleMethod(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: Self.server), format: "pgssub") == "Encode")
    }
}

@Suite("Sessions decoding")
struct SessionDecodingTests {

    @Test("A session decodes with Jellyfin's fractional-second dates")
    func decodesSession() throws {
        let json = """
        [{"Id":"s1","UserName":"alex","DeviceName":"iPhone","Client":"Arcfin",
          "NowPlayingItem":{"Name":"Obsession","RunTimeTicks":72000000000},
          "PlayState":{"IsPaused":true,"PositionTicks":6000000000},
          "LastActivityDate":"2026-10-23T14:13:11.1234567Z"}]
        """
        let session = try #require(JSONDecoder().decode([SessionResponse].self, from: Data(json.utf8)).first?.toSession())
        #expect(session.userName == "alex")
        #expect(session.nowPlayingItemName == "Obsession")
        #expect(session.isPaused)
        #expect(session.positionTicks == 6_000_000_000)
        #expect(session.lastActivityDate != nil)
    }

    @Test("An idle session without optional fields still decodes")
    func decodesIdleSession() throws {
        let json = #"[{"Id":"s2"}]"#
        let session = try #require(JSONDecoder().decode([SessionResponse].self, from: Data(json.utf8)).first?.toSession())
        #expect(session.deviceName == "Unknown Device")
        #expect(session.nowPlayingItemName == nil)
        #expect(!session.isPaused)
    }
}

extension DeviceProfileTests {
    private func allowedRanges(_ profile: [String: Any]) -> String? {
        (profile["CodecProfiles"] as? [[String: Any]])?
            .compactMap { ($0["Conditions"] as? [[String: Any]])?.first { $0["Property"] as? String == "VideoRangeType" } }
            .first?["Value"] as? String
    }

    @Test("HDR passes through untouched unless forced")
    func hdrDefault() {
        UserDefaults.standard.removeObject(forKey: "codecForceHDRTranscode")
        UserDefaults.standard.removeObject(forKey: "codecForceDolbyVisionTranscode")
        #expect(allowedRanges(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: Self.server)) == nil)
        #expect(allowedRanges(JellyfinMediaClient.nativeDecoderProfile(baseURL: Self.server)) == nil)
    }

    @Test("Force HDR to Transcode allows only SDR, on every engine")
    func forceHDR() {
        UserDefaults.standard.set(true, forKey: "codecForceHDRTranscode")
        defer { UserDefaults.standard.removeObject(forKey: "codecForceHDRTranscode") }
        #expect(allowedRanges(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: Self.server)) == "SDR")
        #expect(allowedRanges(JellyfinMediaClient.nativeDecoderProfile(baseURL: Self.server)) == "SDR")
    }

    @Test("Force Dolby Vision to Transcode keeps HDR10 and HLG but not Dolby Vision")
    func forceDolbyVision() {
        UserDefaults.standard.set(true, forKey: "codecForceDolbyVisionTranscode")
        defer { UserDefaults.standard.removeObject(forKey: "codecForceDolbyVisionTranscode") }
        let ranges = allowedRanges(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: Self.server))?.split(separator: "|") ?? []
        #expect(ranges.contains("HDR10") && ranges.contains("HLG"))
        #expect(!ranges.contains { $0.hasPrefix("DOVI") })
    }

    @Test("Compatibility Mode sends H.264 and AAC in SDR on every engine, but leaves casting alone")
    func compatibilityMode() {
        UserDefaults.standard.set(true, forKey: "codecCompatibilityMode")
        defer { UserDefaults.standard.removeObject(forKey: "codecCompatibilityMode") }
        for profile in [JellyfinMediaClient.deviceProfile(forCast: false, baseURL: Self.server), JellyfinMediaClient.nativeDecoderProfile(baseURL: Self.server)] {
            #expect(directPlay(profile).map { $0["VideoCodec"] as? String } == ["h264"])
            #expect(transcoding(profile)["VideoCodec"] as? String == "h264")
            #expect(transcoding(profile)["AudioCodec"] as? String == "aac")
            #expect(allowedRanges(profile) == "SDR")
        }
        #expect(transcoding(JellyfinMediaClient.deviceProfile(forCast: true, baseURL: Self.server))["Container"] as? String == "ts")
    }

    @Test("AV1 leads the conversion only when turned on, where the device decodes it, and never after the server failed at it")
    func av1Conversion() {
        let server = URL(string: "http://av1-test.example.com")!
        AV1Encoding.forgetFailures()
        UserDefaults.standard.removeObject(forKey: AV1Encoding.settingKey)
        defer {
            AV1Encoding.forgetFailures()
            UserDefaults.standard.removeObject(forKey: AV1Encoding.settingKey)
        }
        let codecs = { (transcoding(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: server))["VideoCodec"] as? String) ?? "" }
        #expect(!codecs().contains("av1"))
        UserDefaults.standard.set(true, forKey: AV1Encoding.settingKey)
        #expect(codecs().hasPrefix("av1") == JellyfinMediaClient.decodesAV1InHardware)
        AV1Encoding.markFailed(on: server)
        #expect(!codecs().contains("av1"))
        #expect(transcoding(JellyfinMediaClient.deviceProfile(forCast: true, baseURL: server))["VideoCodec"] as? String == "h264")
    }

    @Test("The plugin's encoder check decides AV1: unavailable stops it, available lifts an old failure")
    func av1FromPlugin() {
        let server = URL(string: "http://av1-plugin.example.com")!
        AV1Encoding.forgetFailures()
        UserDefaults.standard.set(true, forKey: AV1Encoding.settingKey)
        defer {
            AV1Encoding.forgetFailures()
            UserDefaults.standard.removeObject(forKey: AV1Encoding.settingKey)
        }
        let codecs = { (transcoding(JellyfinMediaClient.deviceProfile(forCast: false, baseURL: server))["VideoCodec"] as? String) ?? "" }
        AV1Encoding.apply(serverEncodesAV1: false, on: server)
        #expect(!codecs().contains("av1"))
        AV1Encoding.apply(serverEncodesAV1: true, on: server)
        #expect(codecs().hasPrefix("av1") == JellyfinMediaClient.decodesAV1InHardware)
    }

    @Test("Without an AV1 decoder, native engines keep AV1 to 1080p")
    func av1SoftwareLimit() {
        let limited = (JellyfinMediaClient.nativeDecoderProfile(baseURL: Self.server)["CodecProfiles"] as? [[String: Any]] ?? [])
            .contains { $0["Codec"] as? String == "av1" }
        #expect(limited == !JellyfinMediaClient.decodesAV1InHardware)
    }
}
