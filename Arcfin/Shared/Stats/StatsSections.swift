// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Charts
import JellyfinAPI

/// The period's hero and cards, in one column or two.
struct StatsSections: View {
    let stats: WatchStats
    let counts: StatsLibraryCounts
    /// Landscape, iPad and TV: the cards go in two columns instead of one long, stretched one.
    let isWide: Bool
    let compactHero: Bool
    /// Off under All, which has its own hero for watching and listening together.
    var showsHero = true

    var body: some View {
        // A phone on its side has little height; the full-size hero would fill it.
        if showsHero { StatsHero(stats: stats, compact: compactHero) }
        if isWide {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 28) { chartSections(stats) }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 28) { titleSections(stats) }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            activityCard(stats)
            habitsCard(stats)
            if !stats.topShows.isEmpty { showsSection(stats) }
            if !stats.topMovies.isEmpty { moviesSection(stats) }
            if !stats.genres.isEmpty { genresCard(stats) }
            if !stats.actors.isEmpty || !stats.directors.isEmpty { peopleSection(stats) }
            if !stats.decades.isEmpty || !stats.studios.isEmpty || !stats.ratings.isEmpty { tasteCard(stats) }
            if !stats.rewatched.isEmpty { rewatchedSection(stats) }
            highlightsCard(stats)
            libraryCard
            recentSection(stats)
        }
        footnote
    }

    @ViewBuilder
    private func chartSections(_ stats: WatchStats) -> some View {
        activityCard(stats)
        habitsCard(stats)
        if !stats.genres.isEmpty { genresCard(stats) }
        if !stats.decades.isEmpty || !stats.studios.isEmpty || !stats.ratings.isEmpty { tasteCard(stats) }
        highlightsCard(stats)
        libraryCard
    }

    @ViewBuilder
    private func titleSections(_ stats: WatchStats) -> some View {
        if !stats.topShows.isEmpty { showsSection(stats) }
        if !stats.topMovies.isEmpty { moviesSection(stats) }
        if !stats.actors.isEmpty || !stats.directors.isEmpty { peopleSection(stats) }
        if !stats.rewatched.isEmpty { rewatchedSection(stats) }
        recentSection(stats)
    }

    private var footnote: some View {
        Text("Worked out from what's marked watched on your Jellyfin server. Inside a period, a title counts once, on the last day you played it; All Time counts every play. Watch time uses each title's full length.")
            .font(.caption)
            .foregroundStyle(DT.Color.textSecondary)
    }

    // MARK: - Activity

    private func activityCard(_ stats: WatchStats) -> some View {
        StatsCard(title: String(localized: "Activity"), subtitle: activitySubtitle(stats)) {
            Chart(stats.buckets) { bucket in
                BarMark(
                    x: .value("Date", bucket.start, unit: chartUnit(stats.bucketUnit)),
                    y: .value("Hours", bucket.seconds / 3600)
                )
                .foregroundStyle(DT.Color.accent.gradient)
                .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(DT.Color.textPrimary.opacity(0.08))
                    AxisValueLabel { if let hours = value.as(Double.self) { Text("\(hours, format: .number.precision(.fractionLength(0)))h") } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: stats.bucketUnit == .day && stats.buckets.count > 7 ? 5 : stats.buckets.count)) { _ in
                    AxisValueLabel(format: axisFormat(stats))
                }
            }
            .frame(height: 170 * StatsMetrics.scale)
            .accessibilityLabel("Watch time, \(stats.periodName)")
            .accessibilityValue(activitySubtitle(stats))
        }
    }

    private func activitySubtitle(_ stats: WatchStats) -> String {
        guard let busiest = stats.busiestDay else { return "" }
        let day = busiest.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return String(localized: "Busiest day: \(day), \(StatsFormat.duration(busiest.seconds))")
    }

    private func chartUnit(_ unit: WatchStats.BucketUnit) -> Calendar.Component {
        switch unit {
        case .day: .day
        case .month: .month
        case .year: .year
        }
    }

    private func axisFormat(_ stats: WatchStats) -> Date.FormatStyle {
        switch stats.bucketUnit {
        case .day: stats.period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated)
        case .month: .dateTime.month(.narrow)
        case .year: .dateTime.year()
        }
    }

    // MARK: - Habits

    private func habitsCard(_ stats: WatchStats) -> some View {
        StatsCard(title: String(localized: "Habits"), subtitle: habitSummary(stats)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140 * StatsMetrics.scale), spacing: 12)], spacing: 12) {
                if stats.offset == 0 {
                    StatTile(value: String(localized: "\(stats.currentStreak) days"), unit: nil, label: String(localized: "Current streak"), icon: "flame.fill", hex: "F97316")
                }
                StatTile(value: String(localized: "\(stats.longestStreak) days"), unit: nil, label: String(localized: "Longest streak"), icon: "trophy.fill", hex: "EAB308")
                StatTile(value: String(localized: "\(stats.activeDays) days"), unit: nil, label: String(localized: "Days you watched"), icon: "calendar", hex: "FF6A4D")
                StatTile(value: StatsFormat.duration(stats.averagePerActiveDay), unit: nil, label: String(localized: "On a watching day"), icon: "clock.fill", hex: "60A5FA")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("By day of the week")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                Chart(Array(stats.weekdays.enumerated()), id: \.offset) { index, seconds in
                    BarMark(
                        x: .value("Day", Calendar.current.shortWeekdaySymbols[index]),
                        y: .value("Hours", seconds / 3600)
                    )
                    .foregroundStyle(index == stats.busiestWeekday ? DT.Color.accent : DT.Color.accent.opacity(0.35))
                    .cornerRadius(3)
                }
                .chartYAxis(.hidden)
                .frame(height: 110 * StatsMetrics.scale)
                .accessibilityLabel("Watch time by day of the week")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("By time of day")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                DayPartBar(hours: stats.hours)
            }
        }
    }

    private func habitSummary(_ stats: WatchStats) -> String {
        var parts: [String] = []
        if let day = stats.busiestWeekday { parts.append(String(localized: "Busiest weekday: \(Calendar.current.standaloneWeekdaySymbols[day])")) }
        if let hour = stats.busiestHour { parts.append(DayPart(hour: hour).phrase) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Shows and movies

    private func showsSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(title: String(localized: "Top Shows"))
            VStack(spacing: 10) {
                ForEach(Array(stats.topShows.prefix(6).enumerated()), id: \.element.id) { index, show in
                    NavigationLink(value: show.item) {
                        ShowRow(rank: index + 1, show: show)
                    }
                    .arcfinPlainButton(cornerRadius: DT.Radius.lg, prominent: false)
                }
            }
        }
    }

    private func moviesSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(title: String(localized: "Top Movies"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(stats.topMovies.enumerated()), id: \.element.id) { index, title in
                        NavigationLink(value: title.item) {
                            StatsPosterTile(item: title.item, rank: index + 1,
                                       caption: title.playCount > 1 ? String(localized: "Watched \(title.playCount) times") : title.item.productionYear.map(String.init))
                        }
                        .arcfinPlainButton(ring: false)
                    }
                }
                .padding(.vertical, 4)
            }
            .shelfScrollButtons()
            .scrollClipDisabled(!isWide)
        }
    }

    private func rewatchedSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(title: String(localized: "On Repeat"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(stats.rewatched) { title in
                        NavigationLink(value: title.item.type == .episode ? StatsFormat.series(of: title.item) : title.item) {
                            StatsPosterTile(item: title.item.type == .episode ? StatsFormat.series(of: title.item) : title.item,
                                       rank: nil, caption: String(localized: "\(title.playCount) plays"),
                                       title: title.item.type == .episode ? StatsFormat.episodeName(title.item) : nil)
                        }
                        .arcfinPlainButton(ring: false)
                    }
                }
                .padding(.vertical, 4)
            }
            .shelfScrollButtons()
            .scrollClipDisabled(!isWide)
        }
    }

    // MARK: - Taste

    private func genresCard(_ stats: WatchStats) -> some View {
        let total = stats.genres.reduce(0) { $0 + $1.seconds }
        // A long list: on tvOS each genre takes focus, so the remote can walk down it and the
        // page scrolls with it, instead of the whole card being one stop taller than the screen.
        return StatsCard(title: String(localized: "Genres"), subtitle: stats.genres.first.map { String(localized: "Mostly \($0.name)") }, isFocusTarget: false) {
            VStack(spacing: 12) {
                ForEach(Array(stats.genres.enumerated()), id: \.element.id) { index, genre in
                    RankedBar(name: genre.name,
                              detail: StatsFormat.duration(genre.seconds),
                              fraction: total > 0 ? genre.seconds / total : 0,
                              color: StatsFormat.palette[index % StatsFormat.palette.count])
                    .statsGenreRowFocus()
                }
            }
        }
    }

    private func peopleSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !stats.actors.isEmpty {
                StatsSectionHeader(title: String(localized: "Seen Most On Screen"))
                peopleRow(stats.actors)
            }
            if !stats.directors.isEmpty {
                StatsSectionHeader(title: String(localized: "Directors"))
                    .padding(.top, stats.actors.isEmpty ? 0 : 12)
                peopleRow(stats.directors)
            }
        }
    }

    private func peopleRow(_ people: [WatchStats.Person]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(people) { entry in
                    NavigationLink(value: entry.person) {
                        PersonTile(entry: entry)
                    }
                    .arcfinPlainButton(ring: false)
                }
            }
            .padding(.vertical, 4)
        }
        .shelfScrollButtons()
        .scrollClipDisabled(!isWide)
    }

    private func tasteCard(_ stats: WatchStats) -> some View {
        StatsCard(title: String(localized: "Your Taste"), subtitle: tasteSubtitle(stats)) {
            if !stats.decades.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("By decade")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    let peak = stats.decades.max { $0.count < $1.count }?.decade
                    Chart(stats.decades) { decade in
                        BarMark(x: .value("Decade", String(localized: "\(String(decade.decade))s")), y: .value("Titles", decade.count))
                            .foregroundStyle(decade.decade == peak ? DT.Color.palette("60A5FA") : DT.Color.palette("60A5FA").opacity(0.35))
                            .cornerRadius(3)
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 110 * StatsMetrics.scale)
                    .accessibilityLabel("Titles watched by decade")
                }
            }
            if !stats.studios.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Studios and networks")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    ForEach(stats.studios.prefix(5)) { studio in
                        HStack {
                            Text(studio.name)
                                .font(.system(.subheadline, weight: .medium))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(StatsFormat.duration(studio.seconds))
                                .font(.system(.subheadline).monospacedDigit())
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if !stats.ratings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Age ratings")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    FlowChips(items: stats.ratings.map { "\($0.name) · \($0.count)" })
                }
            }
        }
    }

    private func tasteSubtitle(_ stats: WatchStats) -> String? {
        guard let peak = stats.decades.max(by: { $0.count < $1.count }) else { return nil }
        return String(localized: "Most at home in the \(String(peak.decade))s")
    }

    // MARK: - Highlights and library

    private func highlightsCard(_ stats: WatchStats) -> some View {
        StatsCard(title: String(localized: "Highlights"), subtitle: nil, isFocusTarget: false) {
            VStack(spacing: 14) {
                if let rating = stats.averageMovieRating {
                    FactRow(icon: "star.fill", hex: "EAB308", title: String(localized: "Average movie rating"),
                            value: rating.formatted(.number.precision(.fractionLength(1))))
                }
                if let best = stats.highestRated, let rating = best.item.communityRating {
                    FactLink(item: best.item, icon: "rosette", hex: "10b981", title: String(localized: "Highest rated"),
                             value: "\(best.item.name) · \(rating.formatted(.number.precision(.fractionLength(1))))")
                }
                if let longest = stats.longestMovie, longest.runTimeTicks > 0 {
                    FactLink(item: longest.item, icon: "hourglass", hex: "60A5FA", title: String(localized: "Longest movie"),
                             value: "\(longest.item.name) · \(StatsFormat.duration(longest.runtimeSeconds))")
                }
                if let oldest = stats.oldestTitle, let year = oldest.item.productionYear {
                    FactLink(item: oldest.item, icon: "film.stack", hex: "F97316", title: String(localized: "Oldest movie"),
                             value: "\(oldest.item.name) · \(String(year))")
                }
                FactRow(icon: "sum", hex: "FF6A4D", title: String(localized: "That's about"),
                        value: StatsFormat.equivalent(stats.seconds))
                if stats.period == .allTime, let first = stats.firstPlayed {
                    FactRow(icon: "clock.arrow.circlepath", hex: "EC4899", title: String(localized: "Watching since"),
                            value: first.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
    }

    private var libraryCard: some View {
        StatsCard(title: String(localized: "Your Library"), subtitle: String(localized: "All time, across the server")) {
            HStack(spacing: 12) {
                CompletionRing(label: String(localized: "Movies"), done: counts.watchedMovies, total: counts.movies, hex: "60A5FA")
                CompletionRing(label: String(localized: "Episodes"), done: counts.watchedEpisodes, total: counts.episodes, hex: "FF6A4D")
                CompletionRing(label: String(localized: "Shows finished"), done: counts.finishedShows, total: counts.shows, hex: "10b981")
            }
            HStack(spacing: 12) {
                StatTile(value: "\(counts.inProgress)", unit: nil, label: String(localized: "In progress"), icon: "play.circle.fill", hex: "F97316")
                StatTile(value: "\(counts.favourites)", unit: nil, label: String(localized: "Favourites"), icon: "heart.fill", hex: "EC4899")
            }
        }
    }

    private func recentSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(title: String(localized: "Recently Watched"))
            VStack(spacing: 8) {
                ForEach(stats.titles.prefix(10)) { title in
                    NavigationLink(value: title.item) {
                        RecentRow(title: title)
                    }
                    .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
                }
            }
        }
    }
}

/// Nothing finished in the chosen period, with what to try instead.
struct StatsEmptyPeriod: View {
    let period: StatsPeriod
    let stats: WatchStats?
    let offset: Int

    var body: some View {
        ContentUnavailableView {
            Label(period == .allTime ? "Nothing Watched Yet" : "Nothing Watched in \(stats?.periodName ?? period.label)", systemImage: "popcorn")
        } description: {
            Text(period == .allTime
                 ? String(localized: "Finish a movie or an episode and your stats start here.")
                 : offset == 0
                    ? String(localized: "Pick a longer period, go back to an earlier one, or come back once you've finished something.")
                    : period.nothingThen)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

/// The stepper's name and heading for the period, from the stats the tab shows.
struct StatsStepperTitle {
    let name: String
    let heading: String

    init?(kind: StatsKind, model: StatsModel) {
        if kind != .music, let stats = model.stats {
            name = stats.periodName
            heading = stats.periodHeading
        } else if kind != .video, let music = model.music {
            name = music.periodName
            heading = music.periodHeading
        } else {
            return nil
        }
    }
}

/// What's under the pickers: watching, listening, or both with one hero over them.
struct StatsKindContent: View {
    let kind: StatsKind
    let model: StatsModel
    let period: StatsPeriod
    let isWide: Bool
    let compactHero: Bool

    var body: some View {
        switch kind {
        case .video:
            if let stats = model.stats { video(stats, showsHero: true) }
        case .music:
            if let music = model.music {
                if music.isEmpty {
                    MusicStatsEmptyPeriod(period: period, stats: music)
                } else {
                    MusicStatsSections(stats: music, isWide: isWide, compactHero: compactHero)
                }
            } else if model.musicPhase == .failed {
                ContentUnavailableView("Couldn't Load Music Stats", systemImage: "wifi.exclamationmark",
                                       description: Text("Check your connection to the server, then try again."))
            } else {
                loading
            }
        case .all:
            if let stats = model.stats {
                let music = model.music.flatMap { $0.isEmpty ? nil : $0 }
                if stats.isEmpty && music == nil {
                    if model.musicPhase == .loading { loading } else {
                        StatsEmptyPeriod(period: period, stats: stats, offset: model.offset)
                    }
                } else {
                    AllStatsHero(watch: stats, music: music, compact: compactHero)
                    if !stats.isEmpty {
                        groupHeader(StatsKind.video.label)
                        video(stats, showsHero: false)
                    }
                    if let music {
                        groupHeader(StatsKind.music.label)
                        MusicStatsSections(stats: music, isWide: isWide, showsHero: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func video(_ stats: WatchStats, showsHero: Bool) -> some View {
        if stats.isEmpty {
            StatsEmptyPeriod(period: period, stats: stats, offset: model.offset)
        } else {
            StatsSections(stats: stats, counts: model.counts, isWide: isWide, compactHero: compactHero, showsHero: showsHero)
        }
    }

    private var loading: some View {
        ProgressView("Adding up what you've played…")
            .foregroundStyle(DT.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2.bold())
            .foregroundStyle(DT.Color.textPrimary)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
