// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Charts
import JellyfinAPI
import AuthCore

/// Watch stats worked out from the server's own record of what this profile has watched.
struct StatsView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("statsPeriod") private var period = StatsPeriod.month
    @State private var offset = 0
    @State private var watched: [WatchedTitle] = []
    @State private var details: [String: StatsTitleDetails] = [:]
    @State private var counts = StatsLibraryCounts()
    @State private var stats: WatchStats?
    @State private var phase = Phase.loading
    /// Landscape and iPad: the cards go in two columns instead of one long, stretched one.
    @State private var isWide = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #if !os(tvOS)
    @State private var showShare = false
    #endif

    private enum Phase { case loading, loaded, failed }

    var body: some View {
        NavigationStack {
            content
                .screenBackground()
                .arcfinNavTitleLarge("Stats")
                #if !os(tvOS)
                .toolbar {
                    if let stats, !stats.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showShare = true } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showShare) {
                    if let stats {
                        StatsShareSheet(stats: stats, name: authManager.state.credential?.displayName)
                    }
                }
                #endif
                .navigationDestination(for: MediaItem.self) { item in
                    #if os(tvOS)
                    TVMediaDetailView(item: item)
                    #else
                    MediaDetailView(item: item)
                    #endif
                }
                .navigationDestination(for: MediaPerson.self) { PersonDetailView(person: $0) }
        }
        .task(id: authManager.state.credential?.id) { await load() }
        .task(id: StatsInput(period: period, offset: offset, loaded: phase == .loaded, count: watched.count, details: details.count)) { await compute() }
        .onChange(of: period) { offset = 0 }
    }

    private struct StatsInput: Equatable {
        let period: StatsPeriod
        let offset: Int
        let loaded: Bool
        let count: Int
        let details: Int
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading where stats == nil:
            ProgressView("Adding up what you've watched…")
                .foregroundStyle(DT.Color.textSecondary)
        case .failed where watched.isEmpty:
            ContentUnavailableView {
                Label("Couldn't Load Stats", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection to the server, then try again.")
            } actions: {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
            }
        default:
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    periodPicker
                    if period != .allTime, let stats { periodStepper(stats) }
                    if let stats {
                        if stats.isEmpty {
                            emptyPeriod
                        } else {
                            sections(stats)
                        }
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: isWide ? 1300 : 900)
                .frame(maxWidth: .infinity)
            }
            #if !os(tvOS)
            .refreshable { await load() }
            .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { isWide = $0 }
            #endif
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    /// Steps back through earlier weeks, months or years, and forward again to the current one.
    private func periodStepper(_ stats: WatchStats) -> some View {
        HStack(spacing: 12) {
            stepButton("chevron.left", label: "Previous \(period.title)", disabled: !stats.hasEarlier) { offset -= 1 }
            VStack(spacing: 1) {
                Text(stats.name)
                    .font(.system(.headline))
                    .foregroundStyle(DT.Color.textPrimary)
                    .contentTransition(.numericText())
                Text(stats.heading)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            stepButton("chevron.right", label: "Next \(period.title)", disabled: offset == 0) { offset += 1 }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func stepButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(.body, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        #if os(tvOS)
        .buttonStyle(.bordered)
        #else
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        #endif
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var emptyPeriod: some View {
        ContentUnavailableView {
            Label(period == .allTime ? "Nothing Watched Yet" : "Nothing Watched in \(stats?.name ?? period.title)", systemImage: "popcorn")
        } description: {
            Text(period == .allTime
                 ? "Finish a movie or an episode and your stats start here."
                 : offset == 0
                    ? "Pick a longer period, go back to an earlier one, or come back once you've finished something."
                    : "Nothing you finished was last played then. Try another \(period.title.lowercased()).")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func sections(_ stats: WatchStats) -> some View {
        // A phone on its side has little height; the full-size hero would fill it.
        StatsHero(stats: stats, compact: verticalSizeClass == .compact)
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
        StatsCard(title: "Activity", subtitle: activitySubtitle(stats)) {
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
            .accessibilityLabel("Watch time, \(stats.name)")
            .accessibilityValue(activitySubtitle(stats))
        }
    }

    private func activitySubtitle(_ stats: WatchStats) -> String {
        guard let busiest = stats.busiestDay else { return "" }
        let day = busiest.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return "Busiest day: \(day), \(StatsFormat.duration(busiest.seconds))"
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
        StatsCard(title: "Habits", subtitle: habitSummary(stats)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140 * StatsMetrics.scale), spacing: 12)], spacing: 12) {
                if stats.offset == 0 {
                    StatTile(value: "\(stats.currentStreak)", unit: stats.currentStreak == 1 ? "day" : "days", label: "Current streak", icon: "flame.fill", hex: "F97316")
                }
                StatTile(value: "\(stats.longestStreak)", unit: stats.longestStreak == 1 ? "day" : "days", label: "Longest streak", icon: "trophy.fill", hex: "EAB308")
                StatTile(value: "\(stats.activeDays)", unit: stats.activeDays == 1 ? "day" : "days", label: "Days you watched", icon: "calendar", hex: "06b6d4")
                StatTile(value: StatsFormat.duration(stats.averagePerActiveDay), unit: nil, label: "On a watching day", icon: "clock.fill", hex: "8b5cf6")
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
        if let day = stats.busiestWeekday { parts.append("Mostly \(Calendar.current.weekdaySymbols[day])s") }
        if let hour = stats.busiestHour { parts.append(DayPart(hour: hour).phrase) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Shows and movies

    private func showsSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(title: "Top Shows")
            VStack(spacing: 10) {
                ForEach(Array(stats.topShows.prefix(6).enumerated()), id: \.element.id) { index, show in
                    NavigationLink(value: show.item) {
                        ShowRow(rank: index + 1, show: show)
                    }
                    .arcfinPlainButton(cornerRadius: DT.Radius.lg)
                }
            }
        }
    }

    private func moviesSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(title: "Top Movies")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(stats.topMovies.enumerated()), id: \.element.id) { index, title in
                        NavigationLink(value: title.item) {
                            PosterTile(item: title.item, rank: index + 1,
                                       caption: title.playCount > 1 ? "Watched \(title.playCount) times" : title.item.productionYear.map(String.init))
                        }
                        .arcfinPlainButton(cornerRadius: DT.Radius.md)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func rewatchedSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(title: "On Repeat")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(stats.rewatched) { title in
                        NavigationLink(value: title.item.type == .episode ? StatsFormat.series(of: title.item) : title.item) {
                            PosterTile(item: title.item.type == .episode ? StatsFormat.series(of: title.item) : title.item,
                                       rank: nil, caption: "\(title.playCount) plays",
                                       title: title.item.type == .episode ? StatsFormat.episodeName(title.item) : nil)
                        }
                        .arcfinPlainButton(cornerRadius: DT.Radius.md)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Taste

    private func genresCard(_ stats: WatchStats) -> some View {
        let total = stats.genres.reduce(0) { $0 + $1.seconds }
        return StatsCard(title: "Genres", subtitle: stats.genres.first.map { "Mostly \($0.name)" }) {
            VStack(spacing: 12) {
                ForEach(Array(stats.genres.enumerated()), id: \.element.id) { index, genre in
                    RankedBar(name: genre.name,
                              detail: StatsFormat.duration(genre.seconds),
                              fraction: total > 0 ? genre.seconds / total : 0,
                              color: StatsFormat.palette[index % StatsFormat.palette.count])
                }
            }
        }
    }

    private func peopleSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !stats.actors.isEmpty {
                StatsSectionHeader(title: "Seen Most On Screen")
                peopleRow(stats.actors)
            }
            if !stats.directors.isEmpty {
                StatsSectionHeader(title: "Directors")
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
                    .arcfinPlainButton(cornerRadius: 50 * StatsMetrics.scale)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    private func tasteCard(_ stats: WatchStats) -> some View {
        StatsCard(title: "Your Taste", subtitle: tasteSubtitle(stats)) {
            if !stats.decades.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("By decade")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    let peak = stats.decades.max { $0.count < $1.count }?.decade
                    Chart(stats.decades) { decade in
                        BarMark(x: .value("Decade", "\(decade.decade)s"), y: .value("Titles", decade.count))
                            .foregroundStyle(decade.decade == peak ? DT.Color.palette("8b5cf6") : DT.Color.palette("8b5cf6").opacity(0.35))
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
        return "Most at home in the \(peak.decade)s"
    }

    // MARK: - Highlights and library

    private func highlightsCard(_ stats: WatchStats) -> some View {
        StatsCard(title: "Highlights", subtitle: nil) {
            VStack(spacing: 14) {
                if let rating = stats.averageMovieRating {
                    FactRow(icon: "star.fill", hex: "EAB308", title: "Average movie rating",
                            value: rating.formatted(.number.precision(.fractionLength(1))))
                }
                if let best = stats.highestRated, let rating = best.item.communityRating {
                    FactLink(item: best.item, icon: "rosette", hex: "10b981", title: "Highest rated",
                             value: "\(best.item.name) · \(rating.formatted(.number.precision(.fractionLength(1))))")
                }
                if let longest = stats.longestMovie, longest.runTimeTicks > 0 {
                    FactLink(item: longest.item, icon: "hourglass", hex: "8b5cf6", title: "Longest movie",
                             value: "\(longest.item.name) · \(StatsFormat.duration(longest.runtimeSeconds))")
                }
                if let oldest = stats.oldestTitle, let year = oldest.item.productionYear {
                    FactLink(item: oldest.item, icon: "film.stack", hex: "F97316", title: "Oldest movie",
                             value: "\(oldest.item.name) · \(String(year))")
                }
                FactRow(icon: "sum", hex: "06b6d4", title: "That's about",
                        value: StatsFormat.equivalent(stats.seconds))
                if stats.period == .allTime, let first = stats.firstPlayed {
                    FactRow(icon: "clock.arrow.circlepath", hex: "EC4899", title: "Watching since",
                            value: first.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
    }

    private var libraryCard: some View {
        StatsCard(title: "Your Library", subtitle: "All time, across the server") {
            HStack(spacing: 12) {
                CompletionRing(label: "Movies", done: counts.watchedMovies, total: counts.movies, hex: "8b5cf6")
                CompletionRing(label: "Episodes", done: counts.watchedEpisodes, total: counts.episodes, hex: "06b6d4")
                CompletionRing(label: "Shows finished", done: counts.finishedShows, total: counts.shows, hex: "10b981")
            }
            HStack(spacing: 12) {
                StatTile(value: "\(counts.inProgress)", unit: nil, label: "In progress", icon: "play.circle.fill", hex: "F97316")
                StatTile(value: "\(counts.favourites)", unit: nil, label: "Favourites", icon: "heart.fill", hex: "EC4899")
            }
        }
    }

    private func recentSection(_ stats: WatchStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSectionHeader(title: "Recently Watched")
            VStack(spacing: 8) {
                ForEach(stats.titles.prefix(10)) { title in
                    NavigationLink(value: title.item) {
                        RecentRow(title: title)
                    }
                    .arcfinPlainButton(cornerRadius: DT.Radius.md)
                }
            }
        }
    }

    // MARK: - Loading

    private func load() async {
        guard case .authenticated(let credential) = authManager.state else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let client = JellyfinMediaClient()
        phase = .loading
        async let countsTask = client.getStatsLibraryCounts(credential: credential, authHeader: header)
        guard let titles = try? await client.getWatchedTitles(credential: credential, authHeader: header) else {
            phase = .failed
            return
        }
        // Each show's own details for every show watched; cast and crew only for the shows
        // and movies most likely to matter, as People makes each item many times bigger.
        var seriesIds: [String] = []
        var seenSeries = Set<String>()
        for title in titles {
            if let id = title.item.seriesId, seenSeries.insert(id).inserted { seriesIds.append(id) }
        }
        let movieIds = titles.filter { $0.item.type == .movie }.prefix(150).map(\.id)
        let creditIds = Array(seriesIds.prefix(60)) + movieIds
        async let showDetails = client.getStatsDetails(credential: credential, authHeader: header,
                                                       ids: Array(seriesIds.prefix(500)), includePeople: false)
        async let creditDetails = client.getStatsDetails(credential: credential, authHeader: header,
                                                         ids: creditIds, includePeople: true)
        var merged = (try? await showDetails) ?? [:]
        merged.merge((try? await creditDetails) ?? [:]) { _, withPeople in withPeople }
        watched = titles
        details = merged
        counts = await countsTask
        phase = .loaded
    }

    private func compute() async {
        guard phase == .loaded else { return }
        let all = watched, details = details, period = period, offset = offset
        let result = await Task.detached(priority: .userInitiated) {
            WatchStats(all: all, details: details, period: period, offset: offset)
        }.value
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : DT.Animation.standard) { stats = result }
    }
}

// MARK: - Building blocks

enum StatsMetrics {
    #if os(tvOS)
    static let scale: CGFloat = 1.8
    #else
    static let scale: CGFloat = 1
    #endif
}

enum StatsFormat {
    static let palette = ["06b6d4", "8b5cf6", "10b981", "F97316", "EC4899", "EAB308", "3B82F6", "EF4444"].map(DT.Color.palette)

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

private enum DayPart: CaseIterable {
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
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Late night"
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
        case .evening: "8b5cf6"
        case .night: "3B82F6"
        }
    }
}

private struct StatsCard<Content: View>: View {
    let title: String
    let subtitle: String?
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
        #if os(tvOS)
        .focusable()
        .tvFocusRing(cornerRadius: DT.Radius.xl)
        #endif
    }
}

private struct StatsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DT.Font.cardTitle)
            .foregroundStyle(DT.Color.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The period's headline over the artwork of what was watched most.
private struct StatsHero: View {
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
                    .foregroundStyle(DT.Color.palette("06b6d4"))
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
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            heroFallback
                        }
                    }
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
        #if os(tvOS)
        .focusable()
        .tvFocusRing(cornerRadius: DT.Radius.xl)
        #endif
    }

    private var heroFallback: some View {
        LinearGradient(colors: [DT.Color.palette("0891B2"), DT.Color.palette("1C1C26")], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct HeroCount: View {
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

private struct StatTile: View {
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

private struct DayPartBar: View {
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
                        Text("\(part.title) \(Int((seconds / total * 100).rounded()))%")
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

private struct ShowRow: View {
    let rank: Int
    let show: WatchStats.Show
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
                .foregroundStyle(rank == 1 ? DT.Color.accent : DT.Color.textSecondary)
                .frame(width: 26 * StatsMetrics.scale)
            CachedAsyncImage(url: mediaRepo.imageURL(for: show.item)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    DT.Color.backgroundTertiary
                }
            }
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
            #if !os(tvOS)
            Image(systemName: "chevron.right")
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.6))
                .accessibilityHidden(true)
            #endif
        }
        .padding(12)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct PosterTile: View {
    let item: MediaItem
    let rank: Int?
    let caption: String?
    var title: String?
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: mediaRepo.imageURL(for: item)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    DT.Color.backgroundTertiary
                }
            }
            .frame(width: 120 * StatsMetrics.scale, height: 180 * StatsMetrics.scale)
            .clipped()
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
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
                .lineLimit(2)
            if let caption {
                Text(caption)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .frame(width: 120 * StatsMetrics.scale, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PersonTile: View {
    let entry: WatchStats.Person
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let tag = entry.person.primaryImageTag, let url = mediaRepo.personImageURL(personId: entry.person.id, tag: tag, fillWidth: 240) {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 84 * StatsMetrics.scale, height: 84 * StatsMetrics.scale)
            .clipped()
            .contentShape(Rectangle())
            .clipShape(Circle())
            Text(entry.person.name)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(entry.titles) \(entry.titles == 1 ? "title" : "titles")")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
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

private struct RankedBar: View {
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
                Text("\(detail) · \(Int((fraction * 100).rounded()))%")
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

private struct CompletionRing: View {
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
                Text("\(Int((fraction * 100).rounded()))%")
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

private struct FactRow: View {
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

private struct FactLink: View {
    let item: MediaItem
    let icon: String
    let hex: String
    let title: String
    let value: String

    var body: some View {
        NavigationLink(value: item) {
            FactRow(icon: icon, hex: hex, title: title, value: value)
                .contentShape(Rectangle())
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.sm)
    }
}

private struct RecentRow: View {
    let title: WatchedTitle
    @Environment(MediaRepository.self) private var mediaRepo

    private var poster: MediaItem {
        title.item.type == .episode ? StatsFormat.series(of: title.item) : title.item
    }

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: mediaRepo.imageURL(for: poster)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    DT.Color.backgroundTertiary
                }
            }
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

private struct FlowChips: View {
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
    }
}

#Preview {
    StatsView()
        .environment(MediaRepository())
}
