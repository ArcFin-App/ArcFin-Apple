// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

enum StatsFormat {
    static var palette: [Color] { ["FF6A4D", "60A5FA", "10b981", "EAB308", "EC4899", "14B8A6", "F97316", "94A3B8"].map { DT.Color.palette($0) } }

    static func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(seconds, 60)) ?? ""
    }

    /// The big number: hours, or minutes under an hour.
    static func headline(_ seconds: Double) -> (value: String, unit: String) {
        if seconds >= 3600 {
            let hours = seconds / 3600
            return (hours.formatted(.number.precision(.fractionLength(hours < 10 ? 1 : 0))), hours < 1.05 ? "hour" : "hours")
        }
        let minutes = Int(seconds / 60)
        return ("\(minutes)", minutes == 1 ? "minute" : "minutes")
    }

    static func equivalent(_ seconds: Double) -> String {
        let days = seconds / 86_400
        if days >= 2 { return "\(days.formatted(.number.precision(.fractionLength(1)))) days back to back" }
        let films = seconds / (110 * 60)
        if films >= 1.5 { return "\(Int(films.rounded())) feature films" }
        return "\(Int((seconds / (22 * 60)).rounded())) sitcom episodes"
    }

    static func series(of episode: MediaItem) -> MediaItem {
        MediaItem(id: episode.seriesId ?? episode.id, name: episode.seriesName ?? episode.name,
                  type: episode.seriesId == nil ? episode.type : .series,
                  primaryImageTag: episode.seriesPrimaryImageTag ?? episode.primaryImageTag)
    }

    static func episodeName(_ item: MediaItem) -> String {
        guard let season = item.parentIndexNumber, let number = item.indexNumber else { return item.name }
        return "S\(season) E\(number) · \(item.name)"
    }
}

enum DayPart: CaseIterable {
    case morning, afternoon, evening, night

    init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .night
        }
    }

    var title: String {
        switch self {
        case .morning: String(localized: "Morning")
        case .afternoon: String(localized: "Afternoon")
        case .evening: String(localized: "Evening")
        case .night: String(localized: "Late night")
        }
    }

    var phrase: String {
        switch self {
        case .morning: "usually in the morning"
        case .afternoon: "usually in the afternoon"
        case .evening: "usually in the evening"
        case .night: "usually late at night"
        }
    }

    var icon: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    var hex: String {
        switch self {
        case .morning: "EAB308"
        case .afternoon: "F97316"
        case .evening: "60A5FA"
        case .night: "3B82F6"
        }
    }
}

struct StatsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    /// The whole card is one focus stop on tvOS, so the remote can scroll to it. Off for a
    /// card with links or focusable rows inside, which take focus themselves; a focusable
    /// card around them showed two rings and hid the rows from the remote.
    var isFocusTarget = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(.subheadline))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous)
                .fill(DT.Color.backgroundSecondary)
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous)
                    .stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
        )
        .statsCardFocus(isFocusTarget)
    }
}

struct StatsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DT.Font.cardTitle)
            .foregroundStyle(DT.Color.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The period's headline over the artwork of what was watched most.
struct StatsHero: View {
    let stats: WatchStats
    var compact = false
    @Environment(MediaRepository.self) private var mediaRepo

    private var artwork: MediaItem? {
        stats.topShows.first?.item ?? stats.topMovies.first?.item
    }

    var body: some View {
        let headline = StatsFormat.headline(stats.seconds)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.heading.uppercased())
                    .font(.system(.caption, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(DT.Color.palette("FF6A4D"))
                if !stats.name.isEmpty {
                    Text(stats.name)
                        .font(.system(.headline))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline.value)
                    .font(.system(size: (compact ? 48 : 64) * StatsMetrics.scale, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text("\(headline.unit) watched")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            HStack(spacing: 10) {
                HeroCount(value: stats.movies, label: stats.movies == 1 ? "Movie" : "Movies")
                HeroCount(value: stats.episodes, label: stats.episodes == 1 ? "Episode" : "Episodes")
                HeroCount(value: stats.shows, label: stats.shows == 1 ? "Show" : "Shows")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: (compact ? 190 : 280) * StatsMetrics.scale, alignment: .bottomLeading)
        // Artwork filling the card overflows its frame, and an image takes taps across all of
        // it: drawn behind, clipped and passed through, so the period control above still works.
        .background {
            ZStack {
                if let artwork, let url = mediaRepo.imageURL(for: artwork, type: .backdrop, fillWidth: 1200) ?? mediaRepo.imageURL(for: artwork, fillWidth: 800) {
                    RetryingAsyncImage(
                        url: url, logCategory: "StatsView",
                        content: { $0.resizable().scaledToFill() },
                        placeholder: { heroFallback })
                } else {
                    heroFallback
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

    private var heroFallback: some View {
        LinearGradient(colors: [DT.Color.accentDeep, DT.Color.backgroundTertiary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct HeroCount: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(.title3, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
    }
}

struct StatTile: View {
    let value: String
    let unit: String?
    let label: String
    let icon: String
    let hex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(DT.Color.palette(hex))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(.title2, weight: .bold).monospacedDigit())
                    .foregroundStyle(DT.Color.textPrimary)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(.caption, weight: .medium))
                .foregroundStyle(DT.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DT.Color.palette(hex).opacity(0.1), in: RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct DayPartBar: View {
    let hours: [Double]

    private var parts: [(DayPart, Double)] {
        DayPart.allCases.map { part in
            (part, hours.enumerated().filter { DayPart(hour: $0.offset) == part }.reduce(0) { $0 + $1.element })
        }
    }

    var body: some View {
        let total = max(parts.reduce(0) { $0 + $1.1 }, 1)
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(parts, id: \.0) { part, seconds in
                        if seconds > 0 {
                            Rectangle()
                                .fill(DT.Color.palette(part.hex))
                                .frame(width: max(geo.size.width * seconds / total - 3, 4))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                ForEach(parts, id: \.0) { part, seconds in
                    HStack(spacing: 5) {
                        Image(systemName: part.icon)
                            .foregroundStyle(DT.Color.palette(part.hex))
                            .accessibilityHidden(true)
                        Text("\(part.title) \(Double(seconds / total), format: .percent.precision(.fractionLength(0)))")
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    .font(.system(.caption, weight: .medium))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }
}

struct ShowRow: View {
    let rank: Int
    let show: WatchStats.Show
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(rank == 1 ? DT.Color.accent : DT.Color.textSecondary)
                .frame(width: 26 * StatsMetrics.scale)
            RetryingAsyncImage(
                url: mediaRepo.imageURL(for: show.item), logCategory: "StatsView",
                content: { $0.resizable().scaledToFill() },
                placeholder: { DT.Color.backgroundTertiary })
            .frame(width: 54 * StatsMetrics.scale, height: 80 * StatsMetrics.scale)
            .clipped()
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(show.item.name)
                    .font(.system(.headline))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text("\(show.episodes) \(show.episodes == 1 ? "episode" : "episodes") · \(StatsFormat.duration(show.seconds))")
                    .font(.system(.subheadline))
                    .foregroundStyle(DT.Color.textSecondary)
                if let progress = show.watchedOfTotal, progress.total > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: Double(progress.watched), total: Double(progress.total))
                            .tint(DT.Color.accent)
                        Text("\(progress.watched) of \(progress.total)")
                            .font(.system(.caption).monospacedDigit())
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if StatsMetrics.showsRowChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct StatsPosterTile: View {
    let item: MediaItem
    let rank: Int?
    let caption: String?
    var title: String?
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RetryingAsyncImage(
                url: mediaRepo.imageURL(for: item), logCategory: "StatsView",
                content: { $0.resizable().scaledToFill() },
                placeholder: { DT.Color.backgroundTertiary })
            .frame(width: 120 * StatsMetrics.scale, height: 180 * StatsMetrics.scale)
            .clipped()
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
            .tvLabelFocusRing(cornerRadius: DT.Radius.md, prominent: true)
            .overlay(alignment: .topLeading) {
                if let rank {
                    Text("\(rank)")
                        .font(.system(.subheadline, weight: .heavy).monospacedDigit())
                        .foregroundStyle(DT.Color.onAccent)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(DT.Color.accent, in: Circle())
                        .padding(6)
                }
            }
            Text(title ?? item.name)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2, reservesSpace: true)
            Text(caption ?? "")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1, reservesSpace: true)
        }
        .frame(width: 120 * StatsMetrics.scale, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PersonTile: View {
    let entry: WatchStats.Person
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let tag = entry.person.primaryImageTag, let url = mediaRepo.personImageURL(personId: entry.person.id, tag: tag, fillWidth: 240) {
                    RetryingAsyncImage(
                        url: url, logCategory: "StatsView",
                        content: { $0.resizable().scaledToFill() },
                        placeholder: { placeholder })
                } else {
                    placeholder
                }
            }
            .frame(width: 84 * StatsMetrics.scale, height: 84 * StatsMetrics.scale)
            .clipped()
            .contentShape(Rectangle())
            .clipShape(Circle())
            .tvLabelFocusRing(cornerRadius: 42 * StatsMetrics.scale, prominent: true)
            Text(entry.person.name)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
            Text("\(entry.titles) \(entry.titles == 1 ? "title" : "titles")")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 96 * StatsMetrics.scale)
        .accessibilityElement(children: .combine)
    }

    private var placeholder: some View {
        ZStack {
            DT.Color.backgroundTertiary
            Text(entry.person.name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
        }
    }
}

struct RankedBar: View {
    let name: String
    let detail: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Text("\(detail) · \(Double(fraction), format: .percent.precision(.fractionLength(0)))")
                    .font(.system(.caption).monospacedDigit())
                    .foregroundStyle(DT.Color.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DT.Color.textPrimary.opacity(0.08))
                    Capsule().fill(color).frame(width: max(geo.size.width * fraction, 6))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CompletionRing: View {
    let label: String
    let done: Int
    let total: Int
    let hex: String

    private var fraction: Double { total > 0 ? min(Double(done) / Double(total), 1) : 0 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(DT.Color.palette(hex).opacity(0.15), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(DT.Color.palette(hex), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Double(fraction), format: .percent.precision(.fractionLength(0)))
                    .font(.system(.subheadline, weight: .bold).monospacedDigit())
                    .foregroundStyle(DT.Color.textPrimary)
            }
            .frame(width: 76 * StatsMetrics.scale, height: 76 * StatsMetrics.scale)
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Text("\(done) of \(total)")
                    .font(.system(.caption2).monospacedDigit())
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(done) of \(total)")
    }
}

struct FactRow: View {
    let icon: String
    let hex: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(DT.Color.palette(hex))
                .frame(width: 34 * StatsMetrics.scale, height: 34 * StatsMetrics.scale)
                .background(DT.Color.palette(hex).opacity(0.12), in: RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(DT.Color.textSecondary)
                Text(value)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FactLink: View {
    let item: MediaItem
    let icon: String
    let hex: String
    let title: String
    let value: String

    var body: some View {
        NavigationLink(value: item) {
            FactRow(icon: icon, hex: hex, title: title, value: value)
                .statsFactLinkPadding()
                .contentShape(Rectangle())
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
    }
}

struct RecentRow: View {
    let title: WatchedTitle
    @Environment(MediaRepository.self) private var mediaRepo

    private var poster: MediaItem {
        title.item.type == .episode ? StatsFormat.series(of: title.item) : title.item
    }

    var body: some View {
        HStack(spacing: 12) {
            RetryingAsyncImage(
                url: mediaRepo.imageURL(for: poster), logCategory: "StatsView",
                content: { $0.resizable().scaledToFill() },
                placeholder: { DT.Color.backgroundTertiary })
            .frame(width: 40 * StatsMetrics.scale, height: 60 * StatsMetrics.scale)
            .clipped()
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title.item.type == .episode ? (title.item.seriesName ?? title.item.name) : title.item.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(title.item.type == .episode ? StatsFormat.episodeName(title.item) : (title.item.productionYear.map(String.init) ?? "Movie"))
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let played = title.lastPlayed {
                Text(played, format: .relative(presentation: .named))
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct FlowChips: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(DT.Color.textPrimary.opacity(0.07), in: Capsule())
                }
            }
        }
        .shelfScrollButtons()
    }
}
