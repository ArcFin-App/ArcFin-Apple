// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One play read from another service's data export.
public struct ImportedPlay: Sendable, Equatable, Hashable {
    public var track: String
    public var artist: String
    public var album: String?
    public var playedAt: Date
    /// How long it played, when the export says.
    public var playedMS: Int?

    public init(track: String, artist: String, album: String? = nil, playedAt: Date, playedMS: Int? = nil) {
        self.track = track; self.artist = artist; self.album = album; self.playedAt = playedAt; self.playedMS = playedMS
    }

    /// The same song across plays, whatever its case or spacing.
    public var songKey: String {
        "\(artist.lowercased().trimmingCharacters(in: .whitespaces))\u{1F}\(track.lowercased().trimmingCharacters(in: .whitespaces))"
    }
}

/// Reads listening history from the files Spotify, Apple and Google give out on request:
/// Spotify's streaming history JSON (extended or the short account one), Apple Media
/// Services' Apple Music play activity CSV, and Google Takeout's YouTube watch history JSON.
public enum ListeningHistoryImport {
    public enum Source: String, Sendable { case spotify, appleMusic, youTubeMusic }

    public enum ImportError: Error, Equatable {
        /// Not one of the exports this reads.
        case unrecognized
    }

    /// Plays shorter than this are skips, as ListenBrainz counts them.
    public static let minimumPlayMS = 30_000

    public static func read(_ data: Data) throws -> (source: Source, plays: [ImportedPlay]) {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            if json.contains(where: { $0["ts"] != nil || $0["endTime"] != nil }) {
                return (.spotify, json.compactMap(spotifyPlay).filter(isListen))
            }
            if json.contains(where: { $0["header"] as? String == "YouTube Music" || $0["titleUrl"] != nil }) {
                return (.youTubeMusic, json.compactMap(youTubePlay))
            }
            throw ImportError.unrecognized
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw ImportError.unrecognized
        }
        let plays = try appleMusicPlays(csv: text)
        return (.appleMusic, plays.filter(isListen))
    }

    private static func isListen(_ play: ImportedPlay) -> Bool {
        (play.playedMS ?? minimumPlayMS) >= minimumPlayMS
    }

    // MARK: Spotify

    private static func spotifyPlay(_ entry: [String: Any]) -> ImportedPlay? {
        // Extended history: ts, ms_played, master_metadata_*. Account data: endTime, msPlayed, trackName.
        let track = entry["master_metadata_track_name"] as? String ?? entry["trackName"] as? String
        let artist = entry["master_metadata_album_artist_name"] as? String ?? entry["artistName"] as? String
        guard let track, let artist, !track.isEmpty, !artist.isEmpty else { return nil }
        let ms = (entry["ms_played"] ?? entry["msPlayed"]) as? Int
        let date: Date?
        if let ts = entry["ts"] as? String {
            date = isoDate(ts)
        } else if let end = entry["endTime"] as? String, let ended = shortDate(end) {
            // When it ended: back by how long it played.
            date = ended.addingTimeInterval(-Double(ms ?? 0) / 1000)
        } else {
            date = nil
        }
        guard let date else { return nil }
        return ImportedPlay(track: track, artist: artist, album: entry["master_metadata_album_album_name"] as? String,
                            playedAt: date, playedMS: ms)
    }

    // MARK: YouTube Music

    private static func youTubePlay(_ entry: [String: Any]) -> ImportedPlay? {
        guard entry["header"] as? String == "YouTube Music", var title = entry["title"] as? String,
              let time = entry["time"] as? String, let date = isoDate(time) else { return nil }
        for prefix in ["Watched ", "Angesehen: ", "Has visto ", "Vous avez regardé ", "Hai guardato "] where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
        }
        var artist = ((entry["subtitles"] as? [[String: Any]])?.first?["name"] as? String) ?? ""
        if artist.hasSuffix(" - Topic") { artist.removeLast(" - Topic".count) }
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return ImportedPlay(track: title, artist: artist, playedAt: date)
    }

    // MARK: Apple Music

    /// Play Activity has a row per play; Play History Daily Tracks a row per song and day.
    static func appleMusicPlays(csv text: String) throws -> [ImportedPlay] {
        let rows = parseCSV(text)
        guard let header = rows.first else { throw ImportError.unrecognized }
        func column(_ names: String...) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        func value(_ row: [String], _ index: Int?) -> String? {
            guard let index, index < row.count else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        if let songColumn = column("Song Name", "Title") {
            let artistColumn = column("Artist Name", "Container Artist Name")
            let albumColumn = column("Album Name", "Container Album Name")
            let timeColumn = column("Event Start Timestamp", "Event Timestamp", "Event End Timestamp")
            let msColumn = column("Play Duration Milliseconds")
            return rows.dropFirst().compactMap { row in
                guard let track = value(row, songColumn), let artist = value(row, artistColumn),
                      let date = value(row, timeColumn).flatMap(isoDate) else { return nil }
                return ImportedPlay(track: track, artist: artist, album: value(row, albumColumn), playedAt: date,
                                    playedMS: value(row, msColumn).flatMap(Int.init))
            }
        }
        if let descriptionColumn = column("Track Description"), let dayColumn = column("Date Played") {
            let hoursColumn = column("Hours")
            let countColumn = column("Play Count")
            let msColumn = column("Play Duration Milliseconds")
            return rows.dropFirst().flatMap { row -> [ImportedPlay] in
                // "Artist - Title", split at the first dash.
                guard let description = value(row, descriptionColumn), let dash = description.range(of: " - "),
                      let day = value(row, dayColumn).flatMap(dayDate) else { return [] }
                let artist = String(description[..<dash.lowerBound]), track = String(description[dash.upperBound...])
                let count = max(value(row, countColumn).flatMap(Int.init) ?? 1, 1)
                let hour = value(row, hoursColumn)?.split(separator: ",").first.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 12
                let ms = value(row, msColumn).flatMap(Int.init).map { $0 / count }
                return (0..<count).map { index in
                    ImportedPlay(track: track, artist: artist, playedAt: day.addingTimeInterval(Double(hour * 3600 + index * 240)),
                                 playedMS: ms)
                }
            }
        }
        throw ImportError.unrecognized
    }

    /// Quoted fields may hold commas, quotes ("") and line breaks.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        while let scalar = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if scalar == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\r": continue
            case "\n": row.append(field); rows.append(row); row = []; field = ""
            case "\u{FEFF}": continue
            default: field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    // MARK: Dates

    private static func isoDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Spotify's account data: "2023-01-31 18:04", in UTC.
    private static func shortDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)
    }

    /// Apple's daily tracks: "20230131".
    private static func dayDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: text)
    }
}
