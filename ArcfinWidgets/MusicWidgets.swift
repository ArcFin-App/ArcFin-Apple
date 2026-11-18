// SPDX-License-Identifier: AGPL-3.0-or-later

import AppIntents
import ImageIO
import LiveActivityKit
import SwiftUI
import WidgetKit

// The music widgets: Now Playing in every size (Home Screen, Lock Screen, StandBy, CarPlay,
// the Mac), Recently Played, and a play/pause toggle for Control Center. The app writes what
// they show (MusicWidgetStore); their buttons run audio intents the app performs.

struct MusicEntry: TimelineEntry {
    let date: Date
    let snapshot: MusicWidgetSnapshot?
}

struct MusicProvider: TimelineProvider {
    func placeholder(in context: Context) -> MusicEntry { MusicEntry(date: .now, snapshot: Self.sample) }

    func getSnapshot(in context: Context, completion: @escaping (MusicEntry) -> Void) {
        completion(MusicEntry(date: .now, snapshot: context.isPreview ? MusicWidgetStore.load() ?? Self.sample : MusicWidgetStore.load()))
    }

    /// The app reloads the widgets whenever the music changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<MusicEntry>) -> Void) {
        completion(Timeline(entries: [MusicEntry(date: .now, snapshot: MusicWidgetStore.load())], policy: .never))
    }

    static let sample = MusicWidgetSnapshot(
        nowPlaying: .init(id: "sample", title: "Song Title", artist: "Artist", album: "Album", coverFileName: nil),
        isPlaying: true, position: 60, duration: 210, upNext: [],
        recentlyPlayed: (1...8).map { .init(id: "r\($0)", title: "Song \($0)", artist: "Artist", album: nil, coverFileName: nil) })
}

private let coral = Color(red: 1, green: 0.416, blue: 0.302)

/// A saved cover, or a plain square with a note in it.
private struct Cover: View {
    let fileName: String?
    var cornerRadius: CGFloat = 8

    // The square sets the size and the picture fills it: a filled picture on its own reports
    // its full size and pushes the layout out of the widget.
    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = Self.image(fileName) {
                    image.resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.fill.tertiary)
                        Image(systemName: "music.note").font(.title2).foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    static func image(_ fileName: String?) -> Image? {
        guard let fileName, let url = MusicWidgetStore.coverURL(fileName: fileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1)
    }
}

/// Previous, play or pause, and next.
private struct Transport: View {
    let isPlaying: Bool
    var size: Font = .title2

    var body: some View {
        HStack(spacing: 22) {
            Button(intent: PreviousSongIntent()) { Image(systemName: "backward.fill") }
                .accessibilityLabel("Previous")
            Button(intent: ToggleMusicPlaybackIntent()) { Image(systemName: isPlaying ? "pause.fill" : "play.fill") }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .contentTransition(.symbolEffect(.replace))
            Button(intent: NextSongIntent()) { Image(systemName: "forward.fill") }
                .accessibilityLabel("Next")
        }
        .font(size)
        .buttonStyle(.plain)
    }
}

/// How far into the song: running on by itself while it plays.
private struct SongProgress: View {
    let snapshot: MusicWidgetSnapshot

    var body: some View {
        Group {
            if snapshot.isPlaying, snapshot.duration > 0, snapshot.startDate.addingTimeInterval(snapshot.duration) > .now {
                ProgressView(timerInterval: snapshot.startDate...snapshot.startDate.addingTimeInterval(snapshot.duration),
                             countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: min(snapshot.position, max(snapshot.duration, 1)), total: max(snapshot.duration, 1))
            }
        }
        .progressViewStyle(.linear)
        .tint(coral)
    }
}

/// Rows of covers; each plays the Recently Played list from that song. The covers are sized
/// to the room there is, across and down, so the grid never runs out of the widget.
private struct RecentGrid: View {
    let songs: [MusicWidgetSnapshot.Song]
    let columns: Int
    let rows: Int
    private let spacing: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let across = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let down = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)
            let side = max(min(across, down), 0)
            let shown = Array(songs.prefix(columns * rows))
            Grid(alignment: .topLeading, horizontalSpacing: spacing, verticalSpacing: spacing) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < shown.count {
                                Button(intent: PlayRecentSongIntent(songID: shown[index].id)) {
                                    Cover(fileName: shown[index].coverFileName, cornerRadius: 6)
                                }
                                .buttonStyle(.plain)
                                .frame(width: side, height: side)
                                .accessibilityLabel(Text(verbatim: shown[index].title))
                            } else {
                                Color.clear.frame(width: side, height: side)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Now Playing

struct MusicNowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MusicEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemSmall: small
        case .systemMedium: medium.containerBackground(.fill.tertiary, for: .widget)
        default: large.containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private var snapshot: MusicWidgetSnapshot? { entry.snapshot }
    private var song: MusicWidgetSnapshot.Song? { snapshot?.nowPlaying }
    private var isPlaying: Bool { snapshot?.isPlaying ?? false }

    private var inline: some View {
        Group {
            if let song {
                Label { Text(verbatim: [song.title, song.artist].compactMap { $0 }.joined(separator: " · ")) } icon: {
                    Image(systemName: isPlaying ? "music.note" : "pause")
                }
            } else {
                Label("Arcfin Music", systemImage: "music.note")
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var circular: some View {
        Button(intent: ToggleMusicPlaybackIntent()) {
            ZStack {
                AccessoryWidgetBackground()
                if let snapshot, snapshot.duration > 0 {
                    Gauge(value: min(snapshot.position, snapshot.duration), in: 0...snapshot.duration) { EmptyView() }
                        .gaugeStyle(.accessoryCircularCapacity)
                }
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .containerBackground(.clear, for: .widget)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: song?.title ?? String(localized: "Nothing Playing")).font(.headline).lineLimit(1)
                Text(verbatim: song?.artist ?? String(localized: "Arcfin Music")).font(.caption).lineLimit(1).opacity(0.8)
            }
            Spacer(minLength: 0)
            Button(intent: ToggleMusicPlaybackIntent()) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        .containerBackground(.clear, for: .widget)
    }

    /// The cover fills it, with the song and a play button over it. Also the CarPlay size.
    private var small: some View {
        let shown = song ?? snapshot?.recentlyPlayed.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "music.note").font(.caption.weight(.bold)).opacity(0.8)
                Spacer()
                Button(intent: ToggleMusicPlaybackIntent()) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
            }
            Spacer(minLength: 0)
            Text(verbatim: shown?.title ?? String(localized: "Nothing Playing")).font(.footnote.weight(.semibold)).lineLimit(2)
            if let artist = shown?.artist { Text(verbatim: artist).font(.caption2).lineLimit(1).opacity(0.8) }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            ZStack {
                if let image = Cover.image(shown?.coverFileName) {
                    image.resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                } else {
                    coral.opacity(0.8)
                }
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
        }
    }

    /// The cover, the song with its progress, and the transport.
    private var medium: some View {
        HStack(spacing: 14) {
            Cover(fileName: song?.coverFileName ?? snapshot?.recentlyPlayed.first?.coverFileName, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: song?.title ?? String(localized: "Nothing Playing")).font(.headline).lineLimit(1)
                    Text(verbatim: song?.artist ?? String(localized: "Play something from your library")).font(.subheadline)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                if let snapshot, song != nil { SongProgress(snapshot: snapshot) }
                Spacer(minLength: 0)
                Transport(isPlaying: isPlaying)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Now playing on top; below it, Up Next (extra large) and Recently Played to start.
    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            medium.frame(height: family == .systemExtraLarge ? 130 : 110)
            HStack(alignment: .top, spacing: 16) {
                if family == .systemExtraLarge, let next = snapshot?.upNext, !next.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Up Next").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(next.prefix(3)) { song in
                            HStack(spacing: 8) {
                                Cover(fileName: song.coverFileName, cornerRadius: 4).frame(width: 36)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: song.title).font(.caption.weight(.semibold)).lineLimit(1)
                                    if let artist = song.artist { Text(verbatim: artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 260, alignment: .leading)
                }
                if let recent = snapshot?.recentlyPlayed, !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recently Played").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        RecentGrid(songs: recent, columns: 4, rows: 2)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct MusicNowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MusicWidgetStore.nowPlayingKind, provider: MusicProvider()) { entry in
            MusicNowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("What's playing in Arcfin, with play, pause and skip.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        #endif
    }
}

// MARK: - Recently Played

struct MusicRecentlyPlayedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MusicEntry

    private var songs: [MusicWidgetSnapshot.Song] { entry.snapshot?.recentlyPlayed ?? [] }

    var body: some View {
        Group {
            if songs.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "music.note.list").font(.largeTitle)
                    Text("Nothing played yet").font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            } else {
                switch family {
                case .systemSmall: small
                case .systemMedium: grid(columns: 4, rows: 1)
                case .systemExtraLarge: grid(columns: 6, rows: 3)
                default: grid(columns: 4, rows: 3)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// The last song played, and a button to play from it.
    private var small: some View {
        let song = songs[0]
        return VStack(alignment: .leading, spacing: 6) {
            Button(intent: PlayRecentSongIntent(songID: song.id)) {
                Cover(fileName: song.coverFileName)
            }
            .buttonStyle(.plain)
            Text(verbatim: song.title).font(.caption.weight(.semibold)).lineLimit(1)
        }
    }

    private func grid(columns: Int, rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently Played").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            RecentGrid(songs: songs, columns: columns, rows: rows)
        }
    }
}

struct MusicRecentlyPlayedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MusicWidgetStore.recentlyPlayedKind, provider: MusicProvider()) { entry in
            MusicRecentlyPlayedWidgetView(entry: entry)
        }
        .configurationDisplayName("Recently Played")
        .description("Songs you played lately in Arcfin; tap one to play from there.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Control Center

struct MusicPlayingValueProvider: ControlValueProvider {
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool { MusicWidgetStore.load()?.isPlaying ?? false }
}

struct MusicPlaybackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: MusicWidgetStore.controlKind, provider: MusicPlayingValueProvider()) { isPlaying in
            ControlWidgetToggle(isOn: isPlaying, action: SetMusicPlayingIntent()) {
                Label("Music", systemImage: "music.note")
            } valueLabel: { isOn in
                Label(isOn ? "Playing" : "Paused", systemImage: isOn ? "pause.fill" : "play.fill")
            }
            .tint(coral)
        }
        .displayName("Music")
        .description("Play or pause music in Arcfin.")
    }
}

extension WidgetConfiguration {
    /// Video widgets are no use while driving: CarPlay lists them as not made for the car.
    func notForCarPlay() -> some WidgetConfiguration {
        #if os(iOS)
        disfavoredLocations([.carPlay], for: [.systemSmall])
        #else
        self
        #endif
    }
}
