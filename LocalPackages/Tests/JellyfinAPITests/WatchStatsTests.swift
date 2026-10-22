// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("WatchStats")
struct WatchStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = ISO8601DateFormatter().date(from: "2026-10-22T20:00:00Z")!

    private func daysAgo(_ days: Int, hour: Int = 21) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        return calendar.date(byAdding: .hour, value: hour, to: day)!
    }

    private func movie(_ id: String, minutes: Int, playedDaysAgo: Int?, plays: Int = 1, year: Int = 2020, genres: [String] = ["Drama"]) -> WatchedTitle {
        WatchedTitle(
            item: MediaItem(id: id, name: id, type: .movie,
                            userData: UserData(playCount: plays, played: true, lastPlayedDate: playedDaysAgo.map { daysAgo($0) }),
                            productionYear: year),
            runTimeTicks: Int64(minutes) * 60 * 10_000_000, genres: genres)
    }

    private func episode(_ id: String, series: String, minutes: Int, playedDaysAgo: Int) -> WatchedTitle {
        WatchedTitle(
            item: MediaItem(id: id, name: id, type: .episode,
                            userData: UserData(playCount: 1, played: true, lastPlayedDate: daysAgo(playedDaysAgo)),
                            seriesName: series, seriesId: series),
            runTimeTicks: Int64(minutes) * 60 * 10_000_000)
    }

    @Test("Periods are the calendar week, month and year, with their names")
    func periodNames() {
        #expect(StatsPeriod.month.name(now: now, calendar: calendar, firstPlayed: nil).contains("2026"))
        #expect(StatsPeriod.year.name(now: now, calendar: calendar, firstPlayed: nil) == "2026")
        #expect(StatsPeriod.month.interval(now: now, calendar: calendar)?.start == ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z"))
        #expect(StatsPeriod.allTime.name(now: now, calendar: calendar, firstPlayed: nil).isEmpty)
    }

    @Test("A period counts only titles last played inside it, once each")
    func periodFiltering() {
        let all = [
            movie("a", minutes: 120, playedDaysAgo: 1, plays: 3),
            movie("b", minutes: 90, playedDaysAgo: 20),
            movie("c", minutes: 100, playedDaysAgo: 200),
        ]
        let week = WatchStats(all: all, details: [:], period: .week, now: now, calendar: calendar)
        #expect(week.movies == 1)
        #expect(week.seconds == 120 * 60)

        let month = WatchStats(all: all, details: [:], period: .month, now: now, calendar: calendar)
        #expect(month.movies == 2)
        #expect(month.buckets.count == 31)

        let allTime = WatchStats(all: all, details: [:], period: .allTime, now: now, calendar: calendar)
        #expect(allTime.movies == 3)
        #expect(allTime.seconds == Double(120 * 3 + 90 + 100) * 60)
    }

    @Test("Titles marked watched without a play date count only in All Time")
    func undatedTitles() {
        let all = [movie("a", minutes: 60, playedDaysAgo: nil)]
        #expect(WatchStats(all: all, details: [:], period: .year, now: now, calendar: calendar).isEmpty)
        #expect(WatchStats(all: all, details: [:], period: .allTime, now: now, calendar: calendar).movies == 1)
    }

    @Test("Streaks count consecutive days, ending today or yesterday")
    func streaks() {
        let all = [0, 1, 2, 5, 6, 7, 8].map { movie("m\($0)", minutes: 60, playedDaysAgo: $0) }
        let stats = WatchStats(all: all, details: [:], period: .month, now: now, calendar: calendar)
        #expect(stats.currentStreak == 3)
        #expect(stats.longestStreak == 4)
        #expect(stats.activeDays == 7)

        let lapsed = WatchStats(all: [movie("x", minutes: 60, playedDaysAgo: 3)], details: [:], period: .month, now: now, calendar: calendar)
        #expect(lapsed.currentStreak == 0)
    }

    @Test("Episodes group into shows, with progress from the server's unwatched count")
    func shows() {
        let all = [
            episode("e1", series: "s1", minutes: 45, playedDaysAgo: 1),
            episode("e2", series: "s1", minutes: 45, playedDaysAgo: 2),
            episode("e3", series: "s2", minutes: 30, playedDaysAgo: 3),
        ]
        let details = ["s1": StatsTitleDetails(item: MediaItem(id: "s1", name: "Show One", type: .series), genres: ["Comedy"], unplayedCount: 8)]
        let stats = WatchStats(all: all, details: details, period: .week, now: now, calendar: calendar)
        #expect(stats.shows == 2)
        #expect(stats.topShows.first?.item.name == "Show One")
        #expect(stats.topShows.first?.episodes == 2)
        #expect(stats.topShows.first?.watchedOfTotal?.total == 10)
        #expect(stats.genres.first?.name == "Comedy")
    }

    @Test("Genres rank by time watched, and people by how many titles they're in")
    func genresAndPeople() {
        let all = [
            movie("a", minutes: 200, playedDaysAgo: 1, genres: ["Sci-Fi"]),
            movie("b", minutes: 90, playedDaysAgo: 1, genres: ["Drama"]),
            movie("c", minutes: 90, playedDaysAgo: 2, genres: ["Drama"]),
        ]
        let actor = MediaPerson(id: "p1", name: "Actor One")
        let details = [
            "a": StatsTitleDetails(item: all[0].item, people: [actor]),
            "b": StatsTitleDetails(item: all[1].item, people: [actor, MediaPerson(id: "d1", name: "Director", type: "Director")]),
        ]
        let stats = WatchStats(all: all, details: details, period: .week, now: now, calendar: calendar)
        #expect(stats.genres.map(\.name) == ["Sci-Fi", "Drama"])
        #expect(stats.genres.last?.count == 2)
        #expect(stats.actors.first?.person.id == "p1")
        #expect(stats.actors.first?.titles == 2)
        #expect(stats.directors.first?.titles == 1)
    }

    @Test("Busiest weekday and hour, and decades")
    func habits() {
        let all = [movie("a", minutes: 60, playedDaysAgo: 0, year: 1994), movie("b", minutes: 30, playedDaysAgo: 1, year: 2001)]
        let stats = WatchStats(all: all, details: [:], period: .week, now: now, calendar: calendar)
        #expect(stats.busiestWeekday == calendar.component(.weekday, from: now) - 1)
        #expect(stats.busiestHour == 21)
        #expect(stats.decades.map(\.decade) == [1990, 2000])
        #expect(stats.oldestTitle?.id == "a")
    }
}
