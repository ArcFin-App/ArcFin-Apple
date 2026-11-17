// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite struct LRCLIBTests {
    @Test func timedLinesInOrder() throws {
        let lyrics = try #require(LRCLIBClient.parseLRC("""
        [ar: Someone]
        [00:12.50] First line
        [01:02.00]Second line
        [00:30.25][02:10.00] Chorus
        [00:45.00]
        """))
        #expect(lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["First line", "Chorus", "", "Second line", "Chorus"])
        #expect(lyrics.lines.map(\.start) == [12.5, 30.25, 45, 62, 130])
    }

    @Test func colonHundredths() throws {
        let lyrics = try #require(LRCLIBClient.parseLRC("[01:02:50]Line"))
        #expect(lyrics.lines.first?.start == 62.5)
    }

    @Test func untimedTextIsNotLRC() {
        #expect(LRCLIBClient.parseLRC("Just words\nMore words") == nil)
        #expect(LRCLIBClient.parseLRC("") == nil)
    }

    @Test func syncedLyricsComeFirst() throws {
        let json = #"{"instrumental":false,"plainLyrics":"Plain one\nPlain two","syncedLyrics":"[00:01.00]Timed"}"#
        #expect(try LRCLIBClient.decode(Data(json.utf8)) == .found(Lyrics(lines: [.init(start: 1, text: "Timed")])))
    }

    @Test func plainLyricsWithoutTimes() throws {
        let json = #"{"instrumental":false,"plainLyrics":"Plain one\nPlain two","syncedLyrics":null}"#
        let result = try LRCLIBClient.decode(Data(json.utf8))
        #expect(result == .found(Lyrics(lines: [.init(start: nil, text: "Plain one"), .init(start: nil, text: "Plain two")])))
    }

    @Test func instrumentalHasNone() throws {
        let json = #"{"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#
        #expect(try LRCLIBClient.decode(Data(json.utf8)) == .notFound)
    }

    @Test func searchPicksSyncedThenNearestLength() throws {
        let json = #"""
        [{"duration":198,"instrumental":false,"plainLyrics":"Near plain","syncedLyrics":null},
         {"duration":201,"instrumental":false,"plainLyrics":"x","syncedLyrics":"[00:01.00]Far synced"},
         {"duration":209,"instrumental":false,"plainLyrics":"x","syncedLyrics":"[00:01.00]Near synced"},
         {"duration":300,"instrumental":false,"plainLyrics":"x","syncedLyrics":"[00:01.00]Too long"}]
        """#
        let result = try LRCLIBClient.closest(Data(json.utf8), duration: 210)
        #expect(result == .found(Lyrics(lines: [.init(start: 1, text: "Near synced")])))
    }

    @Test func searchWithNothingCloseFindsNone() throws {
        let json = #"[{"duration":100,"instrumental":false,"plainLyrics":"x","syncedLyrics":null}]"#
        #expect(try LRCLIBClient.closest(Data(json.utf8), duration: 210) == .notFound)
    }
}
