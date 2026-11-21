// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite struct ListenBrainzTests {
    private let listen = ListenBrainzListen(listenedAt: 1_700_000_000, artist: "Artist", track: "Song",
                                            release: "Album", durationMS: 200_000)

    private func json(_ type: String, _ listens: [ListenBrainzListen]) throws -> [String: Any] {
        let data = try ListenBrainzClient.body(type: type, listens: listens, clientVersion: "0.5.1")
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Outside #expect, which can't call a mutating method.
    private func reach(_ play: inout ListenBrainzPlay, _ seconds: Double) -> Bool { play.reached(seconds) }

    @Test func singleListenCarriesItsStartAndDetails() throws {
        let body = try json("single", [listen])
        #expect(body["listen_type"] as? String == "single")
        let payload = try #require((body["payload"] as? [[String: Any]])?.first)
        #expect(payload["listened_at"] as? Int == 1_700_000_000)
        let metadata = try #require(payload["track_metadata"] as? [String: Any])
        #expect(metadata["artist_name"] as? String == "Artist")
        #expect(metadata["track_name"] as? String == "Song")
        #expect(metadata["release_name"] as? String == "Album")
        let info = try #require(metadata["additional_info"] as? [String: Any])
        #expect(info["media_player"] as? String == "Arcfin")
        #expect(info["submission_client"] as? String == "Arcfin")
        #expect(info["submission_client_version"] as? String == "0.5.1")
        #expect(info["duration_ms"] as? Int == 200_000)
    }

    @Test func playingNowHasNoTime() throws {
        let payload = try #require((try json("playing_now", [listen])["payload"] as? [[String: Any]])?.first)
        #expect(payload["listened_at"] == nil)
    }

    @Test func missingDetailsAreLeftOut() throws {
        let bare = ListenBrainzListen(listenedAt: 1_700_000_000, artist: "A", track: "B")
        let payload = try #require((try json("import", [bare, bare])["payload"] as? [[String: Any]]))
        #expect(payload.count == 2)
        let metadata = try #require(payload[0]["track_metadata"] as? [String: Any])
        #expect(metadata["release_name"] == nil)
        #expect((metadata["additional_info"] as? [String: Any])?["duration_ms"] == nil)
    }

    @Test func countsAtHalfTheSong() {
        var play = ListenBrainzPlay(songID: "s", duration: 100, at: 0)
        #expect(!reach(&play, 10))
        #expect(!reach(&play, 20))
        #expect(!reach(&play, 30))
        #expect(!reach(&play, 40))
        #expect(reach(&play, 50))
        // Only once.
        #expect(!reach(&play, 60))
    }

    @Test func countsAtFourMinutesOfALongSong() {
        var play = ListenBrainzPlay(songID: "s", duration: 1200, at: 0)
        var counted = false
        for tick in stride(from: 10.0, through: 230, by: 10) { counted = reach(&play, tick) || counted }
        #expect(!counted)
        #expect(reach(&play, 240))
    }

    @Test func aSeekDoesNotCount() {
        var play = ListenBrainzPlay(songID: "s", duration: 200, at: 0)
        #expect(!reach(&play, 10))
        #expect(!reach(&play, 190))
        #expect(!reach(&play, 200))
        #expect(play.heard == 20)
    }

    @Test func aPauseAddsNothing() {
        var play = ListenBrainzPlay(songID: "s", duration: 200, at: 0)
        _ = play.reached(10)
        _ = play.reached(10)
        _ = play.reached(10)
        #expect(play.heard == 10)
    }

    @Test func aResumeCarriesOnTheSamePlay() {
        let start = Date(timeIntervalSince1970: 1_000)
        let play = ListenBrainzPlay(songID: "s", duration: 200, at: 30, now: start)
        #expect(play.startedAt == Date(timeIntervalSince1970: 970))
        #expect(play.continues(songID: "s", at: 30))
        // From the top it's a new play; another song always is.
        #expect(!play.continues(songID: "s", at: 0))
        #expect(!play.continues(songID: "t", at: 30))
    }

    @Test func recordingIDFoundWhereverItSits() {
        #expect(ListenBrainzClient.recordingMSID(in: Data(#"{"status":"ok","recording_msid":"a"}"#.utf8)) == "a")
        #expect(ListenBrainzClient.recordingMSID(in: Data(#"{"status":"ok","payload":[{"recording_msid":"b"}]}"#.utf8)) == "b")
        #expect(ListenBrainzClient.recordingMSID(in: Data(#"{"status":"ok"}"#.utf8)) == nil)
    }
}
