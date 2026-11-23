// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// A song this profile has played, as Jellyfin records it: when it was last played and how
/// many times in all.
public struct ListenedTrack: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let artist: String?
    public let album: String?
    public let albumId: String?
    public let albumImageTag: String?
    public let genres: [String]
    public let runtimeSeconds: Double
    public let playCount: Int
    public let lastPlayed: Date?

    public init(id: String, name: String, artist: String? = nil, album: String? = nil, albumId: String? = nil,
                albumImageTag: String? = nil, genres: [String] = [], runtimeSeconds: Double = 0,
                playCount: Int = 1, lastPlayed: Date? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.albumImageTag = albumImageTag
        self.genres = genres
        self.runtimeSeconds = runtimeSeconds
        self.playCount = max(playCount, 1)
        self.lastPlayed = lastPlayed
    }
}

/// Everything the Stats page shows about music for one period.
///
/// From ListenBrainz when the profile sends its listens there and the period is one it works
/// stats out for (this or last week, month or year, or all time): it counts every listen.
/// Otherwise from Jellyfin, which like the watch stats only knows each song's last play, so
/// inside a period a song counts once, on its last play, and All Time counts every play.
public struct MusicStats: Sendable {
    public enum Source: Sendable { case jellyfin, listenBrainz }

    public struct Entry: Sendable, Identifiable, Hashable {
        public let name: String
        public let detail: String?
        public let plays: Int
        /// The album whose cover stands for it, when Jellyfin knows it.
        public let albumId: String?
        public let albumImageTag: String?
        public var id: String { name + "\u{1F}" + (detail ?? "") }
    }

    public let source: Source
    public let period: StatsPeriod
    public let offset: Int
    public let heading: String
    public let name: String
    public let hasEarlier: Bool
    /// Listens (ListenBrainz) or plays as Jellyfin counts them.
    public let plays: Int
    /// Listening time, from each song's length; Jellyfin only.
    public let seconds: Double?
    public let songCount: Int
    public let artistCount: Int
    public let albumCount: Int
    /// Plays per day, month or year.
    public let buckets: [WatchStats.Bucket]
    public let bucketUnit: WatchStats.BucketUnit
    public let topSongs: [Entry]
    public let topArtists: [Entry]
    public let topAlbums: [Entry]
    /// Plays per genre; Jellyfin only.
    public let genres: [Entry]
    public let firstPlayed: Date?

    public var isEmpty: Bool { plays == 0 && topSongs.isEmpty }

    /// The busiest bar of the chart, when anything was played.
    public var busiestBucket: WatchStats.Bucket? {
        buckets.filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds }
    }

    /// The ListenBrainz range for a period, or nil for one further back than it keeps.
    public static func listenBrainzRange(period: StatsPeriod, offset: Int) -> ListenBrainzClient.StatsRange? {
        switch (period, offset) {
        case (.allTime, _): .allTime
        case (.week, 0): .thisWeek
        case (.week, -1): .lastWeek
        case (.month, 0): .thisMonth
        case (.month, -1): .lastMonth
        case (.year, 0): .thisYear
        case (.year, -1): .lastYear
        default: nil
        }
    }

    /// The calendar period `offset` steps back from `now`, and its date there.
    static func window(period: StatsPeriod, offset: Int, now: Date, calendar: Calendar) -> (Int, Date, DateInterval?) {
        let offset = period == .allTime ? 0 : min(offset, 0)
        let reference = calendar.date(byAdding: period.component, value: offset, to: now) ?? now
        return (offset, reference, period.interval(now: reference, calendar: calendar))
    }

    /// From Jellyfin's played songs.
    public init(all: [ListenedTrack], period: StatsPeriod, offset: Int = 0, now: Date = Date(), calendar: Calendar = .current) {
        let (offset, reference, interval) = Self.window(period: period, offset: offset, now: now, calendar: calendar)
        let tracks = all.filter { track in
            guard let interval else { return true }
            guard let played = track.lastPlayed else { return false }
            return played >= interval.start && played < interval.end
        }
        func plays(_ track: ListenedTrack) -> Int { period == .allTime ? track.playCount : 1 }

        source = .jellyfin
        self.period = period
        self.offset = offset
        self.plays = tracks.reduce(0) { $0 + plays($1) }
        seconds = tracks.reduce(0) { $0 + $1.runtimeSeconds * Double(plays($1)) }
        songCount = tracks.count
        artistCount = Set(tracks.compactMap(\.artist)).count
        albumCount = Set(tracks.compactMap { $0.albumId ?? $0.album }).count

        let dated = tracks.compactMap { track in track.lastPlayed.map { ($0, plays(track)) } }
        let first = all.compactMap(\.lastPlayed).min()
        let (unit, starts) = WatchStats.bucketStarts(period: period, interval: interval,
                                                     earliest: dated.map(\.0).min(), now: now, calendar: calendar)
        let component: Calendar.Component = unit == .day ? .day : unit == .month ? .month : .year
        var byBucket: [Date: Int] = [:]
        for (date, count) in dated {
            guard let key = calendar.dateInterval(of: component, for: date)?.start else { continue }
            byBucket[key, default: 0] += count
        }
        bucketUnit = unit
        buckets = starts.map { WatchStats.Bucket(start: $0, seconds: Double(byBucket[$0] ?? 0)) }

        topSongs = tracks.sorted { plays($0) == plays($1) ? ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) : plays($0) > plays($1) }
            .prefix(10)
            .map { Entry(name: $0.name, detail: $0.artist, plays: plays($0), albumId: $0.albumId, albumImageTag: $0.albumImageTag) }
        func top(_ key: (ListenedTrack) -> String?, detail: (ListenedTrack) -> String? = { _ in nil }, limit: Int) -> [Entry] {
            Dictionary(grouping: tracks.filter { key($0) != nil }) { key($0)! }
                .map { name, group in
                    let cover = group.first { $0.albumImageTag != nil } ?? group[0]
                    return Entry(name: name, detail: detail(group[0]), plays: group.reduce(0) { $0 + plays($1) },
                                 albumId: cover.albumId, albumImageTag: cover.albumImageTag)
                }
                .sorted { $0.plays == $1.plays ? $0.name < $1.name : $0.plays > $1.plays }
                .prefix(limit).map { $0 }
        }
        topArtists = top(\.artist, limit: 8)
        topAlbums = top(\.album, detail: \.artist, limit: 8)
        genres = Dictionary(grouping: tracks.flatMap { track in track.genres.map { ($0, plays(track)) } }) { $0.0 }
            .map { Entry(name: $0.key, detail: nil, plays: $0.value.reduce(0) { $0 + $1.1 }, albumId: nil, albumImageTag: nil) }
            .sorted { $0.plays == $1.plays ? $0.name < $1.name : $0.plays > $1.plays }
            .prefix(8).map { $0 }

        firstPlayed = first
        heading = period.heading(offset: offset)
        name = period.name(now: reference, calendar: calendar, firstPlayed: first)
        hasEarlier = interval.map { interval in all.contains { ($0.lastPlayed ?? .distantFuture) < interval.start } } ?? false
    }

    /// From a ListenBrainz range. Jellyfin's songs still say whether anything was played before
    /// the period, and give the covers for the songs and albums found in the library.
    public init(listenBrainz stats: ListenBrainzYear, jellyfin all: [ListenedTrack], period: StatsPeriod, offset: Int = 0,
                now: Date = Date(), calendar: Calendar = .current) {
        let (offset, reference, interval) = Self.window(period: period, offset: offset, now: now, calendar: calendar)
        source = .listenBrainz
        self.period = period
        self.offset = offset
        plays = stats.totalListens
        seconds = nil
        songCount = stats.songs.count
        artistCount = stats.artists.count
        albumCount = stats.albums.count

        let first = stats.months.first { $0.listens > 0 }?.start ?? all.compactMap(\.lastPlayed).min()
        let (unit, starts) = WatchStats.bucketStarts(period: period, interval: interval, earliest: first, now: now, calendar: calendar)
        let component: Calendar.Component = unit == .day ? .day : unit == .month ? .month : .year
        var byBucket: [Date: Int] = [:]
        for entry in stats.months {
            guard let key = calendar.dateInterval(of: component, for: entry.start)?.start else { continue }
            byBucket[key, default: 0] += entry.listens
        }
        bucketUnit = unit
        buckets = starts.map { WatchStats.Bucket(start: $0, seconds: Double(byBucket[$0] ?? 0)) }

        func lowered(_ text: String?) -> String { text?.lowercased() ?? "" }
        let withCover = { (first: ListenedTrack, other: ListenedTrack) in first.albumImageTag == nil ? other : first }
        let songCovers = Dictionary(all.map { (lowered($0.name) + "\u{1F}" + lowered($0.artist), $0) }, uniquingKeysWith: withCover)
        let albumCovers = Dictionary(all.compactMap { track in track.album.map { (lowered($0), track) } }, uniquingKeysWith: withCover)
        let artistCovers = Dictionary(all.compactMap { track in track.artist.map { (lowered($0), track) } }, uniquingKeysWith: withCover)
        topSongs = stats.songs.prefix(10).map { song in
            let match = songCovers[lowered(song.name) + "\u{1F}" + lowered(song.artist)]
            return Entry(name: song.name, detail: song.artist, plays: song.listens, albumId: match?.albumId, albumImageTag: match?.albumImageTag)
        }
        topArtists = stats.artists.prefix(8).map { artist in
            let match = artistCovers[lowered(artist.name)]
            return Entry(name: artist.name, detail: nil, plays: artist.listens, albumId: match?.albumId, albumImageTag: match?.albumImageTag)
        }
        topAlbums = stats.albums.prefix(8).map { album in
            let match = albumCovers[lowered(album.name)]
            return Entry(name: album.name, detail: album.artist, plays: album.listens, albumId: match?.albumId, albumImageTag: match?.albumImageTag)
        }
        genres = []

        firstPlayed = first
        heading = period.heading(offset: offset)
        name = period.name(now: reference, calendar: calendar, firstPlayed: first)
        hasEarlier = (offset == 0 && period != .allTime)
            || interval.map { interval in all.contains { ($0.lastPlayed ?? .distantFuture) < interval.start } } ?? false
    }
}

extension JellyfinMediaClient {
    /// Every song marked played, most recently played first, a page at a time like the
    /// watched list.
    public func getListenedTracks(credential: ServerCredential, authHeader: String, limit: Int = 20_000) async throws -> [ListenedTrack] {
        let pageSize = 1000
        var tracks: [ListenedTrack] = []
        while tracks.count < limit {
            var comps = URLComponents(
                url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Items"),
                resolvingAgainstBaseURL: false)!
            let take = min(pageSize, limit - tracks.count)
            comps.queryItems = [
                .init(name: "Filters", value: "IsPlayed"),
                .init(name: "IncludeItemTypes", value: "Audio"),
                .init(name: "Recursive", value: "true"),
                .init(name: "SortBy", value: "DatePlayed"),
                .init(name: "SortOrder", value: "Descending"),
                .init(name: "Fields", value: "Genres"),
                .init(name: "EnableUserData", value: "true"),
                .init(name: "EnableImageTypes", value: "Primary"),
                .init(name: "ImageTypeLimit", value: "1"),
                .init(name: "EnableTotalRecordCount", value: "false"),
                .init(name: "StartIndex", value: "\(tracks.count)"),
                .init(name: "Limit", value: "\(take)"),
            ]
            var req = URLRequest(url: comps.url!)
            req.setValue(authHeader, forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 30
            let (data, response) = try await URLSession.arcfin.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw JellyfinRequestError.status(http.statusCode)
            }
            let items = try JSONDecoder().decode(ListenedPage.self, from: data).items
            tracks += items.map(\.track)
            if items.count < take { break }
        }
        return tracks
    }
}

private struct ListenedPage: Decodable {
    struct Played: Decodable {
        let playCount: Int?
        let lastPlayedDate: String?
        enum CodingKeys: String, CodingKey { case playCount = "PlayCount", lastPlayedDate = "LastPlayedDate" }
    }
    struct Item: Decodable {
        let id: String
        let name: String?
        let album: String?
        let albumId: String?
        let albumPrimaryImageTag: String?
        let albumArtist: String?
        let artists: [String]?
        let genres: [String]?
        let runTimeTicks: Int64?
        let userData: Played?
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", album = "Album", albumId = "AlbumId"
            case albumPrimaryImageTag = "AlbumPrimaryImageTag", albumArtist = "AlbumArtist", artists = "Artists"
            case genres = "Genres", runTimeTicks = "RunTimeTicks", userData = "UserData"
        }

        var track: ListenedTrack {
            ListenedTrack(id: id, name: name ?? "", artist: artists?.first ?? albumArtist, album: album, albumId: albumId,
                          albumImageTag: albumPrimaryImageTag, genres: genres ?? [],
                          runtimeSeconds: Double(runTimeTicks ?? 0) / 10_000_000,
                          playCount: userData?.playCount ?? 1, lastPlayed: userData?.lastPlayedDate.flatMap(JellyfinDate.parse))
        }
    }
    let items: [Item]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}
