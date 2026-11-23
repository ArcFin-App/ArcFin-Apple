// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("MusicStats")
struct MusicStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-10-22T20:00:00Z")!

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .hour, value: 21, to: calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!)!
    }

    private func song(_ name: String, artist: String, album: String, plays: Int, playedDaysAgo: Int, minutes: Double = 3) -> ListenedTrack {
        ListenedTrack(id: name, name: name, artist: artist, album: album, albumId: album, genres: ["Pop"],
                      runtimeSeconds: minutes * 60, playCount: plays, lastPlayed: daysAgo(playedDaysAgo))
    }

    private var library: [ListenedTrack] {
        [song("A", artist: "One", album: "First", plays: 5, playedDaysAgo: 0),
         song("B", artist: "One", album: "First", plays: 2, playedDaysAgo: 1),
         song("C", artist: "Two", album: "Second", plays: 9, playedDaysAgo: 40)]
    }

    @Test("Inside a period a song counts once, on its last play")
    func periodCountsEachSongOnce() {
        let month = MusicStats(all: library, period: .month, now: now, calendar: calendar)
        #expect(month.source == .jellyfin)
        #expect(month.plays == 2)
        #expect(month.songCount == 2)
        #expect(month.artistCount == 1)
        #expect(month.seconds == 360.0)
        #expect(month.topArtists.first?.name == "One")
        #expect(month.buckets.count == 31)
        #expect(month.buckets.reduce(0) { $0 + $1.seconds } == 2)
        #expect(month.hasEarlier)
    }

    @Test("All Time counts every play")
    func allTimeCountsEveryPlay() {
        let all = MusicStats(all: library, period: .allTime, now: now, calendar: calendar)
        #expect(all.plays == 16)
        #expect(all.topSongs.first?.name == "C")
        #expect(all.topArtists.map(\.name) == ["Two", "One"])
        #expect(!all.hasEarlier)
    }

    @Test("An earlier month with nothing played is empty")
    func earlierPeriod() {
        let twoBack = MusicStats(all: library, period: .month, offset: -2, now: now, calendar: calendar)
        #expect(twoBack.isEmpty)
        #expect(!twoBack.hasEarlier)
    }

    @Test("ListenBrainz covers this and last week, month and year, and all time")
    func listenBrainzRanges() {
        #expect(MusicStats.listenBrainzRange(period: .week, offset: 0) == .thisWeek)
        #expect(MusicStats.listenBrainzRange(period: .month, offset: -1) == .lastMonth)
        #expect(MusicStats.listenBrainzRange(period: .year, offset: -2) == nil)
        #expect(MusicStats.listenBrainzRange(period: .allTime, offset: -3) == .allTime)
    }

    @Test("ListenBrainz listens go in the chart and take Jellyfin's covers")
    func fromListenBrainz() {
        var year = ListenBrainzYear()
        year.songs = [.init(name: "a", artist: "one", listens: 12)]
        year.albums = [.init(name: "First", artist: "One", listens: 12)]
        year.months = [.init(start: daysAgo(0), listens: 7), .init(start: daysAgo(1), listens: 5)]
        let week = MusicStats(listenBrainz: year, jellyfin: library, period: .month, now: now, calendar: calendar)
        #expect(week.source == .listenBrainz)
        #expect(week.plays == 12)
        #expect(week.seconds == nil)
        #expect(week.buckets.reduce(0) { $0 + $1.seconds } == 12)
        #expect(week.topSongs.first?.albumId == "First")
        #expect(week.topAlbums.first?.albumId == "First")
        #expect(week.hasEarlier)
    }
}
