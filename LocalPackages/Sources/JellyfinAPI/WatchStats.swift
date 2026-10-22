// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, allTime

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .allTime: "All Time"
        }
    }

    /// For headings: "This Week", "All Time".
    public var heading: String {
        self == .allTime ? "All Time" : "This \(title)"
    }

    /// The calendar week, month or year `now` is in; nil for All Time.
    public func interval(now: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .week: calendar.dateInterval(of: .weekOfYear, for: now)
        case .month: calendar.dateInterval(of: .month, for: now)
        case .year: calendar.dateInterval(of: .year, for: now)
        case .allTime: nil
        }
    }

    /// Which week, month or year it is: "18–24 Oct", "October 2026", "2026".
    public func name(now: Date, calendar: Calendar, firstPlayed: Date?) -> String {
        switch self {
        case .week:
            guard let week = interval(now: now, calendar: calendar),
                  let last = calendar.date(byAdding: .day, value: -1, to: week.end) else { return "" }
            return (week.start..<last).formatted(.interval.day().month(.abbreviated))
        case .month:
            return now.formatted(.dateTime.month(.wide).year())
        case .year:
            return now.formatted(.dateTime.year())
        case .allTime:
            return firstPlayed.map { "Since \($0.formatted(.dateTime.month(.wide).year()))" } ?? ""
        }
    }
}

/// Everything the Stats page shows for one period, worked out from the watched list.
///
/// Jellyfin records only when a title was last played and how many times, not each viewing.
/// So inside a period a title counts once, on its last play; All Time counts every play.
public struct WatchStats: Sendable {
    public struct Bucket: Sendable, Identifiable, Hashable {
        public let start: Date
        public let seconds: Double
        public var id: Date { start }
    }

    public enum BucketUnit: Sendable { case day, month, year }

    public struct Ranked: Sendable, Identifiable, Hashable {
        public let name: String
        public let seconds: Double
        public let count: Int
        public var id: String { name }
    }

    public struct Show: Sendable, Identifiable, Hashable {
        public let item: MediaItem
        public let episodes: Int
        public let seconds: Double
        public let lastPlayed: Date?
        /// Episodes watched of all the show has, when the server says how many are left.
        public let watchedOfTotal: (watched: Int, total: Int)?
        public var id: String { item.id }

        public static func == (a: Show, b: Show) -> Bool { a.item == b.item && a.episodes == b.episodes && a.seconds == b.seconds }
        public func hash(into hasher: inout Hasher) { hasher.combine(item.id) }
    }

    public struct Person: Sendable, Identifiable, Hashable {
        public let person: MediaPerson
        public let titles: Int
        public var id: String { person.id }
    }

    public struct Decade: Sendable, Identifiable, Hashable {
        public let decade: Int
        public let count: Int
        public var id: Int { decade }
    }

    public let period: StatsPeriod
    public let titles: [WatchedTitle]
    public let seconds: Double
    public let movies: Int
    public let episodes: Int
    public let shows: Int

    public let buckets: [Bucket]
    public let bucketUnit: BucketUnit
    public let busiestDay: Bucket?
    /// Seconds by weekday, Sunday first.
    public let weekdays: [Double]
    /// Seconds by hour of the day.
    public let hours: [Double]
    public let activeDays: Int
    public let currentStreak: Int
    public let longestStreak: Int

    public let genres: [Ranked]
    public let studios: [Ranked]
    public let ratings: [Ranked]
    public let decades: [Decade]
    public let topShows: [Show]
    public let topMovies: [WatchedTitle]
    public let rewatched: [WatchedTitle]
    public let actors: [Person]
    public let directors: [Person]

    public let averageMovieRating: Double?
    public let highestRated: WatchedTitle?
    public let longestMovie: WatchedTitle?
    public let oldestTitle: WatchedTitle?
    public let firstPlayed: Date?

    public var isEmpty: Bool { titles.isEmpty }
    public var averagePerActiveDay: Double { activeDays > 0 ? seconds / Double(activeDays) : 0 }
    public var busiestWeekday: Int? {
        guard let peak = weekdays.max(), peak > 0 else { return nil }
        return weekdays.firstIndex(of: peak)
    }
    public var busiestHour: Int? {
        guard let peak = hours.max(), peak > 0 else { return nil }
        return hours.firstIndex(of: peak)
    }

    public init(
        all: [WatchedTitle],
        details: [String: StatsTitleDetails],
        period: StatsPeriod,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.period = period
        let interval = period.interval(now: now, calendar: calendar)
        let start = interval?.start
        let titles = all.filter { title in
            guard let start else { return true }
            return (title.lastPlayed ?? .distantPast) >= start
        }
        .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        self.titles = titles

        func watchSeconds(_ title: WatchedTitle) -> Double {
            title.runtimeSeconds * Double(period == .allTime ? title.playCount : 1)
        }

        seconds = titles.reduce(0) { $0 + watchSeconds($1) }
        movies = titles.filter { $0.item.type == .movie }.count
        episodes = titles.filter { $0.item.type == .episode }.count
        shows = Set(titles.compactMap(\.item.seriesId)).count

        // Activity over time.
        let dated = titles.compactMap { title in title.lastPlayed.map { ($0, title.runtimeSeconds) } }
        let unit: BucketUnit
        let bucketStarts: [Date]
        switch period {
        case .week, .month:
            unit = .day
            let first = interval?.start ?? calendar.startOfDay(for: now)
            let count = interval.flatMap { calendar.dateComponents([.day], from: $0.start, to: $0.end).day } ?? 1
            bucketStarts = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        case .year:
            unit = .month
            bucketStarts = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: start ?? now) }
        case .allTime:
            let earliest = dated.map(\.0).min() ?? now
            let months = calendar.dateComponents([.month], from: earliest, to: now).month ?? 0
            if months < 24 {
                unit = .month
                let first = calendar.dateInterval(of: .month, for: earliest)?.start ?? earliest
                bucketStarts = (0...months).compactMap { calendar.date(byAdding: .month, value: $0, to: first) }
            } else {
                unit = .year
                let firstYear = calendar.component(.year, from: earliest)
                let lastYear = calendar.component(.year, from: now)
                bucketStarts = (firstYear...lastYear).compactMap { calendar.date(from: DateComponents(year: $0)) }
            }
        }
        bucketUnit = unit
        let component: Calendar.Component = unit == .day ? .day : unit == .month ? .month : .year
        var byBucket: [Date: Double] = [:]
        for (date, secs) in dated {
            guard let key = calendar.dateInterval(of: component, for: date)?.start else { continue }
            byBucket[key, default: 0] += secs
        }
        buckets = bucketStarts.map { Bucket(start: $0, seconds: byBucket[$0] ?? 0) }

        var byDay: [Date: Double] = [:]
        var weekdays = Array(repeating: 0.0, count: 7)
        var hours = Array(repeating: 0.0, count: 24)
        for (date, secs) in dated {
            byDay[calendar.startOfDay(for: date), default: 0] += secs
            weekdays[calendar.component(.weekday, from: date) - 1] += secs
            hours[calendar.component(.hour, from: date)] += secs
        }
        self.weekdays = weekdays
        self.hours = hours
        activeDays = byDay.count
        busiestDay = byDay.max { $0.value < $1.value }.map { Bucket(start: $0.key, seconds: $0.value) }

        // Streaks run over every day with a play, whatever the period, ending today or yesterday.
        let allDays = Set(all.compactMap { $0.lastPlayed.map { calendar.startOfDay(for: $0) } })
        let periodDays = Set(byDay.keys)
        longestStreak = Self.longestRun(in: periodDays, calendar: calendar)
        currentStreak = Self.currentRun(in: allDays, now: now, calendar: calendar)

        // What it was.
        func seriesDetails(_ title: WatchedTitle) -> StatsTitleDetails? {
            title.item.seriesId.flatMap { details[$0] }
        }
        func rank(_ pairs: [(String, Double)], limit: Int) -> [Ranked] {
            var seconds: [String: Double] = [:]
            var counts: [String: Int] = [:]
            for (name, secs) in pairs where !name.isEmpty {
                seconds[name, default: 0] += secs
                counts[name, default: 0] += 1
            }
            return seconds.map { Ranked(name: $0.key, seconds: $0.value, count: counts[$0.key] ?? 0) }
                .sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
                .prefix(limit).map { $0 }
        }
        genres = rank(titles.flatMap { title in
            let names = title.genres.isEmpty ? (seriesDetails(title)?.genres ?? []) : title.genres
            return names.map { ($0, watchSeconds(title)) }
        }, limit: 8)
        studios = rank(titles.flatMap { title in
            let names = title.item.type == .episode ? (seriesDetails(title)?.studios ?? title.studios) : title.studios
            return names.prefix(1).map { ($0, watchSeconds(title)) }
        }, limit: 8)
        ratings = rank(titles.compactMap { title in title.officialRating.map { ($0, 1) } }, limit: 6)

        var decadeCounts: [Int: Int] = [:]
        for title in titles {
            let year = title.item.type == .episode ? (seriesDetails(title)?.item.productionYear ?? title.item.productionYear) : title.item.productionYear
            if let year { decadeCounts[year / 10 * 10, default: 0] += 1 }
        }
        decades = decadeCounts.map { Decade(decade: $0.key, count: $0.value) }.sorted { $0.decade < $1.decade }

        // Shows: every episode watched, ever, counts towards how far through a show is.
        var everWatched: [String: Int] = [:]
        for title in all { if let id = title.item.seriesId { everWatched[id, default: 0] += 1 } }
        topShows = Dictionary(grouping: titles.filter { $0.item.seriesId != nil }, by: { $0.item.seriesId! })
            .map { seriesId, eps in
                let first = eps[0].item
                let item = details[seriesId]?.item ?? MediaItem(
                    id: seriesId, name: first.seriesName ?? first.name, type: .series,
                    primaryImageTag: first.seriesPrimaryImageTag)
                let progress = details[seriesId]?.unplayedCount.map { unplayed in
                    (watched: everWatched[seriesId] ?? eps.count, total: (everWatched[seriesId] ?? eps.count) + unplayed)
                }
                return Show(item: item, episodes: eps.count, seconds: eps.reduce(0) { $0 + watchSeconds($1) },
                            lastPlayed: eps.compactMap(\.lastPlayed).max(), watchedOfTotal: progress)
            }
            .sorted { $0.seconds == $1.seconds ? $0.item.name < $1.item.name : $0.seconds > $1.seconds }
            .prefix(10).map { $0 }

        let movieTitles = titles.filter { $0.item.type == .movie }
        topMovies = movieTitles.sorted {
            $0.playCount == $1.playCount ? ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) : $0.playCount > $1.playCount
        }
        .prefix(12).map { $0 }
        rewatched = titles.filter { $0.playCount > 1 }.sorted { $0.playCount > $1.playCount }.prefix(10).map { $0 }

        // People: each title they're in counts once, a show once for all its episodes.
        var actorTitles: [String: (MediaPerson, Int)] = [:]
        var directorTitles: [String: (MediaPerson, Int)] = [:]
        let creditedIds = Set(movieTitles.map(\.item.id)).union(titles.compactMap(\.item.seriesId))
        for id in creditedIds {
            guard let people = details[id]?.people else { continue }
            for person in people {
                switch person.type {
                case "Actor", "GuestStar":
                    actorTitles[person.id, default: (person, 0)].1 += 1
                case "Director":
                    directorTitles[person.id, default: (person, 0)].1 += 1
                default:
                    break
                }
            }
        }
        func topPeople(_ table: [String: (MediaPerson, Int)], limit: Int) -> [Person] {
            table.values.filter { $0.1 > 1 || table.count <= limit }
                .sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }
                .prefix(limit).map { Person(person: $0.0, titles: $0.1) }
        }
        actors = topPeople(actorTitles, limit: 12)
        directors = topPeople(directorTitles, limit: 6)

        let rated = movieTitles.filter { ($0.item.communityRating ?? 0) > 0 }
        averageMovieRating = rated.isEmpty ? nil : rated.reduce(0) { $0 + ($1.item.communityRating ?? 0) } / Double(rated.count)
        highestRated = rated.max { ($0.item.communityRating ?? 0) < ($1.item.communityRating ?? 0) }
        longestMovie = movieTitles.max { $0.runTimeTicks < $1.runTimeTicks }
        oldestTitle = movieTitles.filter { $0.item.productionYear != nil }
            .min { ($0.item.productionYear ?? .max) < ($1.item.productionYear ?? .max) }
        firstPlayed = dated.map(\.0).min()
    }

    static func longestRun(in days: Set<Date>, calendar: Calendar) -> Int {
        var longest = 0
        for day in days {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day), !days.contains(previous) else { continue }
            var length = 1
            var next = day
            while let following = calendar.date(byAdding: .day, value: 1, to: next), days.contains(following) {
                length += 1
                next = following
            }
            longest = max(longest, length)
        }
        return longest
    }

    static func currentRun(in days: Set<Date>, now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        guard var day = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today),
              days.contains(day) else { return 0 }
        var length = 0
        while days.contains(day) {
            length += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return length
    }
}
