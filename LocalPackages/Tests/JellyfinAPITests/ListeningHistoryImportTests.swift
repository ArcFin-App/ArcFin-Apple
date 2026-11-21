// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("Listening history import")
struct ListeningHistoryImportTests {
    @Test("Spotify's extended history keeps listens and drops skips")
    func spotifyExtended() throws {
        let json = #"[{"ts":"2024-03-01T10:00:00Z","ms_played":200000,"master_metadata_track_name":"Song","master_metadata_album_artist_name":"Band","master_metadata_album_album_name":"Record"},{"ts":"2024-03-01T10:05:00Z","ms_played":5000,"master_metadata_track_name":"Skipped","master_metadata_album_artist_name":"Band"},{"ts":"2024-03-01T10:06:00Z","ms_played":90000,"master_metadata_track_name":null,"episode_name":"Podcast"}]"#
        let result = try ListeningHistoryImport.read(Data(json.utf8))
        #expect(result.source == .spotify)
        #expect(result.plays.map(\.track) == ["Song"])
        #expect(result.plays.first?.album == "Record")
        #expect(result.plays.first?.playedAt == ISO8601DateFormatter().date(from: "2024-03-01T10:00:00Z"))
    }

    @Test("Spotify's account history starts each play back from when it ended")
    func spotifyAccount() throws {
        let json = #"[{"endTime":"2023-01-31 18:04","artistName":"Band","trackName":"Song","msPlayed":60000}]"#
        let play = try #require(try ListeningHistoryImport.read(Data(json.utf8)).plays.first)
        #expect(play.playedAt == ISO8601DateFormatter().date(from: "2023-01-31T18:03:00Z"))
    }

    @Test("YouTube Music entries lose Watched and - Topic, and other YouTube is left out")
    func youTubeMusic() throws {
        let json = #"[{"header":"YouTube Music","title":"Watched Song","subtitles":[{"name":"Band - Topic"}],"time":"2024-05-02T08:00:00.123Z"},{"header":"YouTube","title":"Watched A Video","subtitles":[{"name":"Someone"}],"time":"2024-05-02T09:00:00Z"}]"#
        let result = try ListeningHistoryImport.read(Data(json.utf8))
        #expect(result.source == .youTubeMusic)
        #expect(result.plays.map { "\($0.artist)|\($0.track)" } == ["Band|Song"])
    }

    @Test("Apple Music's play activity reads quoted fields")
    func appleActivity() throws {
        let csv = "Song Name,Artist Name,Album Name,Event Start Timestamp,Play Duration Milliseconds\n\"Song, Part 2\",Band,\"The \"\"Record\"\"\",2022-07-04T20:00:00Z,180000\nShort,Band,Rec,2022-07-04T20:05:00Z,1000\n"
        let result = try ListeningHistoryImport.read(Data(csv.utf8))
        #expect(result.source == .appleMusic)
        #expect(result.plays.map(\.track) == ["Song, Part 2"])
        #expect(result.plays.first?.album == "The \"Record\"")
    }

    @Test("Apple Music's daily tracks make one play per count")
    func appleDaily() throws {
        let csv = "Country,Track Identifier,Date Played,Hours,Play Duration Milliseconds,Play Count,Track Description\nGB,1,20230131,\"13, 14\",400000,2,Band - Song - Live\n"
        let plays = try ListeningHistoryImport.read(Data(csv.utf8)).plays
        #expect(plays.count == 2)
        #expect(plays.first?.artist == "Band")
        #expect(plays.first?.track == "Song - Live")
        #expect(plays.first?.playedAt == ISO8601DateFormatter().date(from: "2023-01-31T13:00:00Z"))
    }

    @Test("Anything else isn't read")
    func unrecognized() {
        #expect(throws: ListeningHistoryImport.ImportError.unrecognized) {
            try ListeningHistoryImport.read(Data(#"[{"foo":1}]"#.utf8))
        }
    }
}
