// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Remote commands")
struct RemoteCommandTests {

    private func parse(_ type: String, _ json: String) -> JellyfinRemoteCommand? {
        JellyfinRemoteCommand.parse(messageType: type, json: Data(json.utf8))
    }

    @Test("Play Now with a start position")
    func playNow() {
        let command = parse("Play", """
            {"MessageType":"Play","MessageId":"x","Data":{"ItemIds":["a1b2"],"StartPositionTicks":600000000,\
            "PlayCommand":"PlayNow","ControllingUserId":"u1"}}
            """)
        #expect(command == .play(itemIds: ["a1b2"], startPositionTicks: 600_000_000))
    }

    @Test("Queue commands are left out")
    func playNextIgnored() {
        #expect(parse("Play", #"{"Data":{"ItemIds":["a1b2"],"PlayCommand":"PlayNext"}}"#) == nil)
        #expect(parse("Play", #"{"Data":{"ItemIds":[],"PlayCommand":"PlayNow"}}"#) == nil)
    }

    @Test("Seek carries its position")
    func seek() {
        let command = parse("Playstate", #"{"Data":{"Command":"Seek","SeekPositionTicks":1200000000,"ControllingUserId":"u1"}}"#)
        #expect(command == .playstate(.seek, seekPositionTicks: 1_200_000_000))
    }

    @Test("Pause and unknown playstates")
    func pauseAndUnknown() {
        #expect(parse("Playstate", #"{"Data":{"Command":"Pause"}}"#) == .playstate(.pause, seekPositionTicks: nil))
        #expect(parse("Playstate", #"{"Data":{"Command":"Shuffle"}}"#) == nil)
    }

    @Test("General commands keep their string arguments")
    func displayMessage() {
        let command = parse("GeneralCommand", """
            {"Data":{"Name":"DisplayMessage","ControllingUserId":"u1",\
            "Arguments":{"Header":"Hi","Text":"Dinner's ready","TimeoutMs":"5000"}}}
            """)
        #expect(command == .general(name: "DisplayMessage",
                                    arguments: ["Header": "Hi", "Text": "Dinner's ready", "TimeoutMs": "5000"]))
    }

    @Test("A general command without arguments")
    func noArguments() {
        #expect(parse("GeneralCommand", #"{"Data":{"Name":"Mute"}}"#) == .general(name: "Mute", arguments: [:]))
    }

    @Test("Other message types aren't commands")
    func otherTypes() {
        #expect(parse("UserDataChanged", #"{"Data":{}}"#) == nil)
    }
}
