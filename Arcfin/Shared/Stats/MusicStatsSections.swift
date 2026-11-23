// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Charts
import JellyfinAPI

extension MusicStats {
    var periodHeading: String { period.heading(at: offset) }

    var periodName: String {
        guard period == .allTime else { return name }
        return firstPlayed.map { String(localized: "Since \($0.formatted(.dateTime.month(.wide).year()))") } ?? ""
    }

    /// "1,240 minutes listened" from Jellyfin, "830 listens" from ListenBrainz.
    var headline: AttributedString {
        if let seconds { return StatsFormat.headline(seconds) }
        var count = AttributedString(plays.formatted())
        count.measurement = .value
        return count
    }
}

/// The music side of Stats: the period's hero and cards, in one column or two.
struct MusicStatsSections: View {
    let stats: MusicStats
    let isWide: Bool
    var showsHero = true
    var compactHero = false

    var body: some View {
        if showsHero { MusicStatsHero(stats: stats, compact: compactHero) }
        if isWide {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 28) {
                    activityCard
                    if !stats.topArtists.isEmpty { artistsCard }
                    if !stats.genres.isEmpty { genresCard }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 28) {
                    if !stats.topSongs.isEmpty { songsCard }
                    if !stats.topAlbums.isEmpty { albumsCard }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            activityCard
            if !stats.topSongs.isEmpty { songsCard }
            if !stats.topArtists.isEmpty { artistsCard }
            if !stats.topAlbums.isEmpty { albumsCard }
            if !stats.genres.isEmpty { genresCard }
        }
        footnote
    }

    private var footnote: some View {
        Text(stats.source == .listenBrainz
             ? "From your ListenBrainz listens, which count every play. ListenBrainz updates its stats once a day."
             : "Worked out from what's marked played on your Jellyfin server. Inside a period, a song counts once, on the last day you played it; All Time counts every play. Add your ListenBrainz token in Settings › Integrations to count every listen.")
            .font(.caption)
            .foregroundStyle(DT.Color.textSecondary)
    }

    private var activityCard: some View {
        StatsCard(title: String(localized: "Listening"), subtitle: activitySubtitle) {
            Chart(stats.buckets) { bucket in
                BarMark(
                    x: .value("Date", bucket.start, unit: chartUnit),
                    y: .value("Plays", bucket.seconds)
                )
                .foregroundStyle(DT.Color.palette("60A5FA").gradient)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(DT.Color.textPrimary.opacity(0.08))
                    AxisValueLabel { if let plays = value.as(Double.self) { Text(plays, format: .number.precision(.fractionLength(0))) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: stats.bucketUnit == .day && stats.buckets.count > 7 ? 5 : stats.buckets.count)) { _ in
                    AxisValueLabel(format: axisFormat)
                }
            }
            .frame(height: 170 * StatsMetrics.scale)
            .accessibilityLabel("Plays, \(stats.periodName)")
            .accessibilityValue(activitySubtitle)
        }
    }

    private var activitySubtitle: String {
        guard let busiest = stats.busiestBucket else { return "" }
        let when = switch stats.bucketUnit {
        case .day: busiest.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .month: busiest.start.formatted(.dateTime.month(.wide))
        case .year: busiest.start.formatted(.dateTime.year())
        }
        return String(localized: "Busiest: \(when), \(Int(busiest.seconds)) plays")
    }

    private var chartUnit: Calendar.Component {
        switch stats.bucketUnit {
        case .day: .day
        case .month: .month
        case .year: .year
        }
    }

    private var axisFormat: Date.FormatStyle {
        switch stats.bucketUnit {
        case .day: stats.period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated)
        case .month: .dateTime.month(.narrow)
        case .year: .dateTime.year()
        }
    }

    private var songsCard: some View {
        StatsCard(title: String(localized: "Top Songs"), subtitle: nil) {
            VStack(spacing: 10) {
                ForEach(Array(stats.topSongs.enumerated()), id: \.element.id) { index, song in
                    MusicStatsRow(rank: index + 1, entry: song)
                }
            }
        }
    }

    private var albumsCard: some View {
        StatsCard(title: String(localized: "Top Albums"), subtitle: nil) {
            VStack(spacing: 10) {
                ForEach(Array(stats.topAlbums.enumerated()), id: \.element.id) { index, album in
                    MusicStatsRow(rank: index + 1, entry: album)
                }
            }
        }
    }

    private var artistsCard: some View {
        rankedCard(String(localized: "Top Artists"), stats.topArtists)
    }

    private var genresCard: some View {
        rankedCard(String(localized: "Genres"), stats.genres)
    }

    private func rankedCard(_ title: String, _ entries: [MusicStats.Entry]) -> some View {
        let total = entries.reduce(0) { $0 + $1.plays }
        return StatsCard(title: title, subtitle: entries.first.map { String(localized: "Mostly \($0.name)") }) {
            VStack(spacing: 12) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    RankedBar(name: entry.name,
                              detail: String(localized: "\(entry.plays) plays"),
                              fraction: total > 0 ? Double(entry.plays) / Double(total) : 0,
                              color: StatsFormat.palette[index % StatsFormat.palette.count])
                }
            }
        }
    }
}

/// A ranked song or album: its place, the album cover when the library has it, and its plays.
private struct MusicStatsRow: View {
    let rank: Int
    let entry: MusicStats.Entry
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(rank)")
                .font(.system(.headline).monospacedDigit())
                .foregroundStyle(DT.Color.accent)
                .frame(width: 28 * StatsMetrics.scale, alignment: .leading)
            cover
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                if let detail = entry.detail {
                    Text(verbatim: detail)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(entry.plays) plays")
                .font(.system(.caption).monospacedDigit())
                .foregroundStyle(DT.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        let size = 40 * StatsMetrics.scale
        return Group {
            if let albumId = entry.albumId, let url = mediaRepo.primaryImageURL(itemID: albumId, tag: entry.albumImageTag, fillWidth: 120) {
                RetryingAsyncImage(url: url, logCategory: "StatsView",
                                   content: { $0.resizable().scaledToFill() },
                                   placeholder: { coverFallback })
            } else {
                coverFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
        .accessibilityHidden(true)
    }

    private var coverFallback: some View {
        ZStack {
            DT.Color.backgroundTertiary
            Image(systemName: "music.note").foregroundStyle(DT.Color.textSecondary)
        }
    }
}

/// The period's music headline over the cover of what was played most.
struct MusicStatsHero: View {
    let stats: MusicStats
    var compact = false
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        let headline = StatsFormat.styled(
            stats.headline,
            value: .system(size: (compact ? 48 : 64) * StatsMetrics.scale, weight: .heavy, design: .rounded), valueColor: .white,
            unit: .system(.title3, weight: .semibold), unitColor: .white.opacity(0.8))
        VStack(alignment: .leading, spacing: 14) {
            StatsHeroHeading(heading: stats.periodHeading, name: stats.periodName)
            Text(stats.seconds == nil ? AttributedString(localized: "\(headline) listens") : AttributedString(localized: "\(headline) listened"))
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 10) {
                HeroCount(value: stats.songCount, label: stats.songCount == 1 ? String(localized: "Song") : String(localized: "Songs"))
                HeroCount(value: stats.artistCount, label: stats.artistCount == 1 ? String(localized: "Artist") : String(localized: "Artists"))
                HeroCount(value: stats.albumCount, label: stats.albumCount == 1 ? String(localized: "Album") : String(localized: "Albums"))
            }
        }
        .modifier(StatsHeroBackground(url: coverURL, compact: compact))
    }

    private var coverURL: URL? {
        let cover = stats.topAlbums.first { $0.albumId != nil } ?? stats.topSongs.first { $0.albumId != nil }
        return cover.flatMap { mediaRepo.primaryImageURL(itemID: $0.albumId!, tag: $0.albumImageTag, fillWidth: 1000) }
    }
}

/// Everything in the period at once: time watched and listened, and the counts of both.
struct AllStatsHero: View {
    let watch: WatchStats?
    let music: MusicStats?
    var compact = false
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        let valueFont = Font.system(size: (compact ? 40 : 52) * StatsMetrics.scale, weight: .heavy, design: .rounded)
        VStack(alignment: .leading, spacing: 14) {
            StatsHeroHeading(heading: watch?.periodHeading ?? music?.periodHeading ?? "",
                             name: watch?.periodName ?? music?.periodName ?? "")
            VStack(alignment: .leading, spacing: 4) {
                if let watch, !watch.isEmpty {
                    line(AttributedString(localized: "\(styled(StatsFormat.headline(watch.seconds), valueFont)) watched"))
                }
                if let music, !music.isEmpty {
                    let value = styled(music.headline, valueFont)
                    line(music.seconds == nil ? AttributedString(localized: "\(value) listens") : AttributedString(localized: "\(value) listened"))
                }
            }
            HStack(spacing: 10) {
                if let watch, !watch.isEmpty {
                    HeroCount(value: watch.movies, label: watch.movies == 1 ? String(localized: "Movie") : String(localized: "Movies"))
                    HeroCount(value: watch.episodes, label: watch.episodes == 1 ? String(localized: "Episode") : String(localized: "Episodes"))
                }
                if let music, !music.isEmpty {
                    HeroCount(value: music.songCount, label: music.songCount == 1 ? String(localized: "Song") : String(localized: "Songs"))
                }
            }
        }
        .modifier(StatsHeroBackground(url: artworkURL, compact: compact))
    }

    private func styled(_ headline: AttributedString, _ font: Font) -> AttributedString {
        StatsFormat.styled(headline, value: font, valueColor: .white, unit: .system(.title3, weight: .semibold), unitColor: .white.opacity(0.8))
    }

    private func line(_ text: AttributedString) -> some View {
        Text(text)
            .font(.system(.title3, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .contentTransition(.numericText())
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private var artworkURL: URL? {
        guard let item = watch?.topShows.first?.item ?? watch?.topMovies.first?.item else { return nil }
        return mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1200) ?? mediaRepo.imageURL(for: item, fillWidth: 800)
    }
}

/// "THIS MONTH" over "November 2026", as every hero starts.
struct StatsHeroHeading: View {
    let heading: String
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(heading.uppercased())
                .font(.system(.caption, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(DT.Color.palette("FF6A4D"))
            if !name.isEmpty {
                Text(name)
                    .font(.system(.headline))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

/// A hero's artwork behind a dark fade, clipped, passing taps through to the controls above.
struct StatsHeroBackground: ViewModifier {
    let url: URL?
    let compact: Bool

    func body(content: Content) -> some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: (compact ? 190 : 280) * StatsMetrics.scale, alignment: .bottomLeading)
            .background {
                ZStack {
                    if let url {
                        RetryingAsyncImage(url: url, logCategory: "StatsView",
                                           content: { $0.resizable().scaledToFill() },
                                           placeholder: { fallback })
                    } else {
                        fallback
                    }
                    LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                }
                .clipped()
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous))
            .accessibilityElement(children: .combine)
            .statsHeroFocus()
    }

    private var fallback: some View {
        LinearGradient(colors: [DT.Color.accentDeep, DT.Color.backgroundTertiary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Nothing played in the chosen period.
struct MusicStatsEmptyPeriod: View {
    let period: StatsPeriod
    let stats: MusicStats?

    var body: some View {
        ContentUnavailableView {
            Label(period == .allTime ? "Nothing Played Yet" : "Nothing Played in \(stats?.periodName ?? period.label)", systemImage: "music.note")
        } description: {
            Text(period == .allTime
                 ? String(localized: "Play some music and your listening stats start here.")
                 : String(localized: "Pick a longer period, or go back to an earlier one."))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
