// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Session transcode details")
struct SessionTranscodeTests {

    @Test("A transcoding session carries its method, rate, codecs and reasons")
    func decodesTranscode() throws {
        let json = """
        [{"Id":"s1","DeviceName":"Living Room","SupportsRemoteControl":true,
          "PlayState":{"IsPaused":false,"PlayMethod":"Transcode"},
          "TranscodingInfo":{"Bitrate":8200000,"VideoCodec":"h264","AudioCodec":"aac",
            "IsVideoDirect":false,"IsAudioDirect":true,"HardwareAccelerationType":"nvenc",
            "TranscodeReasons":["VideoCodecNotSupported","ContainerBitrateExceedsLimit"]}}]
        """
        let session = try #require(JSONDecoder().decode([SessionResponse].self, from: Data(json.utf8)).first?.toSession())
        let transcode = try #require(session.transcode)
        #expect(session.playMethod == "Transcode")
        #expect(session.supportsRemoteControl)
        #expect(transcode.bitrate == 8_200_000)
        #expect(!transcode.isVideoDirect && transcode.isAudioDirect)
        #expect(transcode.reasons == ["VideoCodecNotSupported", "ContainerBitrateExceedsLimit"])
        #expect(transcode.hardwareAcceleration == "nvenc")
    }

    @Test("A direct-play session has no transcode details")
    func decodesDirectPlay() throws {
        let json = #"[{"Id":"s2","PlayState":{"PlayMethod":"DirectPlay"}}]"#
        let session = try #require(JSONDecoder().decode([SessionResponse].self, from: Data(json.utf8)).first?.toSession())
        #expect(session.playMethod == "DirectPlay")
        #expect(session.transcode == nil)
        #expect(!session.supportsRemoteControl)
    }
}
