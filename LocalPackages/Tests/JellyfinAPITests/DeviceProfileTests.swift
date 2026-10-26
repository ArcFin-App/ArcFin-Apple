// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Device profiles", .serialized)
struct DeviceProfileTests {

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
        let containers = directPlay(JellyfinMediaClient.deviceProfile(forCast: false))
            .compactMap { $0["Container"] as? String }
            .joined(separator: ",")
        #expect(!containers.split(separator: ",").contains("mkv"))
    }

    @Test("AVFoundation's HLS output carries HEVC in fMP4, so HEVC is repackaged rather than re-encoded")
    func avFoundationHEVCPassthrough() {
        UserDefaults.standard.removeObject(forKey: "codecAllowHEVCDirectPlay")
        let output = transcoding(JellyfinMediaClient.deviceProfile(forCast: false))
        #expect(output["Container"] as? String == "mp4")
        #expect(output["Protocol"] as? String == "hls")
        #expect((output["VideoCodec"] as? String)?.split(separator: ",").contains("hevc") == true)
    }

    @Test("Turning HEVC off drops it from the output too")
    func hevcToggleOff() {
        UserDefaults.standard.set(false, forKey: "codecAllowHEVCDirectPlay")
        defer { UserDefaults.standard.removeObject(forKey: "codecAllowHEVCDirectPlay") }
        let output = transcoding(JellyfinMediaClient.deviceProfile(forCast: false))
        #expect(output["VideoCodec"] as? String == "h264")
    }

    @Test("Chromecast keeps h264 in ts")
    func castOutput() {
        let output = transcoding(JellyfinMediaClient.deviceProfile(forCast: true))
        #expect(output["Container"] as? String == "ts")
        #expect(output["VideoCodec"] as? String == "h264")
    }

    @Test("Native engines direct-play mkv with no codec limits")
    func nativeDirectPlaysEverything() throws {
        let profiles = directPlay(JellyfinMediaClient.nativeDecoderProfile)
        let profile = try #require(profiles.first)
        #expect((profile["Container"] as? String)?.split(separator: ",").contains("mkv") == true)
        #expect(profile["VideoCodec"] == nil)
        #expect(profile["AudioCodec"] == nil)
    }

    @Test("Native engines keep image subtitles in the file instead of burning them in")
    func nativeEmbedsImageSubtitles() {
        let profile = JellyfinMediaClient.nativeDecoderProfile
        for format in ["pgssub", "dvdsub", "dvbsub"] {
            #expect(subtitleMethod(profile, format: format) == "Embed")
        }
        #expect(subtitleMethod(JellyfinMediaClient.deviceProfile(forCast: false), format: "pgssub") == "Encode")
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
        #expect(allowedRanges(JellyfinMediaClient.deviceProfile(forCast: false)) == nil)
        #expect(allowedRanges(JellyfinMediaClient.nativeDecoderProfile) == nil)
    }

    @Test("Force HDR to Transcode allows only SDR, on every engine")
    func forceHDR() {
        UserDefaults.standard.set(true, forKey: "codecForceHDRTranscode")
        defer { UserDefaults.standard.removeObject(forKey: "codecForceHDRTranscode") }
        #expect(allowedRanges(JellyfinMediaClient.deviceProfile(forCast: false)) == "SDR")
        #expect(allowedRanges(JellyfinMediaClient.nativeDecoderProfile) == "SDR")
    }

    @Test("Force Dolby Vision to Transcode keeps HDR10 and HLG but not Dolby Vision")
    func forceDolbyVision() {
        UserDefaults.standard.set(true, forKey: "codecForceDolbyVisionTranscode")
        defer { UserDefaults.standard.removeObject(forKey: "codecForceDolbyVisionTranscode") }
        let ranges = allowedRanges(JellyfinMediaClient.deviceProfile(forCast: false))?.split(separator: "|") ?? []
        #expect(ranges.contains("HDR10") && ranges.contains("HLG"))
        #expect(!ranges.contains { $0.hasPrefix("DOVI") })
    }

    @Test("Compatibility Mode sends H.264 and AAC in SDR on every engine, but leaves casting alone")
    func compatibilityMode() {
        UserDefaults.standard.set(true, forKey: "codecCompatibilityMode")
        defer { UserDefaults.standard.removeObject(forKey: "codecCompatibilityMode") }
        for profile in [JellyfinMediaClient.deviceProfile(forCast: false), JellyfinMediaClient.nativeDecoderProfile] {
            #expect(directPlay(profile).map { $0["VideoCodec"] as? String } == ["h264"])
            #expect(transcoding(profile)["VideoCodec"] as? String == "h264")
            #expect(transcoding(profile)["AudioCodec"] as? String == "aac")
            #expect(allowedRanges(profile) == "SDR")
        }
        #expect(transcoding(JellyfinMediaClient.deviceProfile(forCast: true))["Container"] as? String == "ts")
    }
}

