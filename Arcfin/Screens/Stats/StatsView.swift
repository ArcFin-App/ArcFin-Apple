// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import StreamystatsAPI
import AuthCore

struct StatsView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(StreamystatsRepository.self) private var statsRepo

    @Environment(AuthManager.self) private var authManager

    @State private var selectedPeriod: String = "All"
    private let periods = ["7D", "30D", "All"]

    /// Stats for the 7D/30D ranges, fetched on demand; nil for "All", which is what the
    /// repository already loaded for Home.
    private struct PeriodStats {
        var movies: Int
        var episodes: Int
        var topMovies: [MediaItem]
        var topShows: [MediaItem]
    }
    @State private var periodStats: PeriodStats?

    private var displayedMovieCount: Int { periodStats?.movies ?? mediaRepo.playedMovieCount }
    private var displayedEpisodeCount: Int { periodStats?.episodes ?? mediaRepo.playedEpisodeCount }
    private var displayedTopMovies: [MediaItem] { periodStats?.topMovies ?? mediaRepo.topMovies }
    private var displayedTopShows: [MediaItem] { periodStats?.topShows ?? mediaRepo.topShows }

    private var periodStart: Date? {
        switch selectedPeriod {
        case "7D": Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case "30D": Calendar.current.date(byAdding: .day, value: -30, to: Date())
        default: nil
        }
    }

    private func loadPeriodStats() async {
        guard let since = periodStart, case .authenticated(let cred) = authManager.state else {
            periodStats = nil
            return
        }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let client = JellyfinMediaClient()
        async let movies = client.getPlayedCount(credential: cred, authHeader: header, itemType: "Movie", since: since)
        async let episodes = client.getPlayedCount(credential: cred, authHeader: header, itemType: "Episode", since: since)
        async let topMovies = client.getTopPlayed(credential: cred, authHeader: header, itemType: "Movie", since: since)
        async let topShows = client.getTopPlayed(credential: cred, authHeader: header, itemType: "Series", since: since)
        let result = PeriodStats(
            movies: (try? await movies) ?? 0, episodes: (try? await episodes) ?? 0,
            topMovies: (try? await topMovies) ?? [], topShows: (try? await topShows) ?? [])
        guard !Task.isCancelled else { return }
        periodStats = result
    }

    private var totalWatched: Int { displayedMovieCount + displayedEpisodeCount }
    private var movieFraction: Double {
        totalWatched > 0 ? Double(displayedMovieCount) / Double(totalWatched) : 0
    }
    private var episodeFraction: Double {
        totalWatched > 0 ? Double(displayedEpisodeCount) / Double(totalWatched) : 0
    }

    #if os(tvOS)
    private let cardScale: CGFloat = 1.8
    #else
    private let cardScale: CGFloat = 1
    #endif

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                heroSection
                activityRings
                if !displayedTopShows.isEmpty { showsSection }
                if !displayedTopMovies.isEmpty { moviesSection }
                if statsRepo.isConfigured && !statsRepo.recommendations.isEmpty {
                    recommendationsSection
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .screenBackground()
        .ignoresSafeArea(edges: .top)
        .task { if statsRepo.isConfigured { await statsRepo.load() } }
        .task(id: selectedPeriod) { await loadPeriodStats() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statsRepo.isConfigured ? "Streamystats" : "Your Library")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(DT.Color.accent)
                Text("Watch History")
                    .font(.system(.title, design: .default, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.8)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(periods, id: \.self) { p in
                    Button {
                        withAnimation(DT.Animation.fast) { selectedPeriod = p }
                    } label: {
                        Text(p)
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(selectedPeriod == p ? DT.Color.accent : DT.Color.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(selectedPeriod == p ? DT.Color.accent.opacity(0.15) : Color.white.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                selectedPeriod == p ? DT.Color.accent.opacity(0.4) : Color.white.opacity(0.08),
                                lineWidth: 1))
                    }
                    #if os(tvOS)
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .tvFocusRing(cornerRadius: DT.Radius.pill, prominent: true)
                    #else
                    .buttonStyle(.plain)
                    #endif
                }
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 52)
        .padding(.bottom, DT.Spacing.md)
        .background(LinearGradient(
            colors: [DT.Color.accent.opacity(0.07), .clear],
            startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack {
            // Radial glow
            RadialGradient(
                colors: [DT.Color.accent.opacity(0.18), .clear],
                center: .center, startRadius: 0, endRadius: 120)
            .frame(height: 160)

            VStack(spacing: 4) {
                Text("TOTAL WATCHED")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(DT.Color.accent)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(totalWatched)")
                        .font(.system(.largeTitle, design: .default, weight: .heavy))
                        .foregroundStyle(DT.Color.textPrimary)
                        .tracking(-3)
                    Text("items")
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .offset(y: -6)
                }

                HStack(spacing: 16) {
                    statChip("\(displayedMovieCount)", label: "Movies", hex: "8b5cf6")
                    statChip("\(displayedEpisodeCount)", label: "Episodes", hex: "06b6d4")
                    statChip("\(mediaRepo.libraries.count)", label: "Libraries", hex: "10b981")
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, DT.Spacing.lg)
    }

    private func statChip(_ value: String, label: String, hex: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .default, weight: .heavy))
                .foregroundStyle(Color(hex: hex))
            Text(label)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(hex: hex).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: hex).opacity(0.15), lineWidth: 1))
    }

    // MARK: - Activity rings

    private var activityRings: some View {
        HStack(spacing: 16) {
            ringCard(
                value: displayedMovieCount,
                label: "Movies",
                sublabel: "watched",
                fraction: movieFraction,
                hex: "8b5cf6"
            )
            ringCard(
                value: displayedEpisodeCount,
                label: "Episodes",
                sublabel: "watched",
                fraction: episodeFraction,
                hex: "06b6d4"
            )
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.lg)
    }

    private func ringCard(value: Int, label: String, sublabel: String, fraction: Double, hex: String) -> some View {
        let color = Color(hex: hex)
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(fraction, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: fraction)

                Text("\(Int(fraction * 100))%")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 54 * cardScale, height: 54 * cardScale)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(value)")
                    .font(.system(.title2, design: .default, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
                Text(label)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(color)
                Text(sublabel)
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.12), lineWidth: 1))
        .tvFocusable(cornerRadius: 16)
    }

    // MARK: - Top shows

    private var showsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Most Watched Shows")
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.2)
                Spacer()
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(Array(displayedTopShows.enumerated()), id: \.element.id) { i, show in
                    showRow(rank: i + 1, item: show)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .padding(.bottom, DT.Spacing.lg)
    }

    private func showRow(rank: Int, item: MediaItem) -> some View {
        HStack(spacing: 12) {
            // Rank
            ZStack {
                Text("\(rank)")
                    .font(.system(.largeTitle, design: .default, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.06))
                Text("\(rank)")
                    .font(.system(.caption, design: .default, weight: .heavy))
                    .foregroundStyle(rank == 1 ? DT.Color.accent : DT.Color.textSecondary)
            }
            .frame(width: 32)

            if let url = mediaRepo.imageURL(for: item) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: RoundedRectangle(cornerRadius: 6).fill(DT.Color.backgroundTertiary)
                    }
                }
                .frame(width: 36 * cardScale, height: 50 * cardScale)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                if let plays = item.userData?.playCount, plays > 0 {
                    Text("\(plays) episode\(plays == 1 ? "" : "s") played")
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                } else if let year = item.productionYear {
                    Text(String(year))
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }

            Spacer()

            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(.subheadline))
                    .foregroundStyle(DT.Color.accent)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(rank == 1 ? DT.Color.accent.opacity(0.06) : .white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
            rank == 1 ? DT.Color.accent.opacity(0.2) : .white.opacity(0.05), lineWidth: 1))
        .tvFocusable(cornerRadius: 14)
    }

    // MARK: - Top movies

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most Watched Movies")
                .font(.system(.callout, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
                .tracking(-0.2)
                .padding(.horizontal, DT.Spacing.pagePad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(displayedTopMovies.enumerated()), id: \.element.id) { i, movie in
                        movieCard(rank: i + 1, movie: movie)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.lg)
    }

    private func movieCard(rank: Int, movie: MediaItem) -> some View {
        ZStack(alignment: .bottom) {
            if let url = mediaRepo.imageURL(for: movie) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: DT.Color.backgroundSecondary
                    }
                }
                .clipped()
            } else {
                DT.Color.backgroundSecondary
            }

            LinearGradient(colors: [.black.opacity(0.9), .clear], startPoint: .bottom, endPoint: .top)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("#\(rank)")
                        .font(.system(.caption2, design: .default, weight: .heavy))
                        .foregroundStyle(DT.Color.accent)
                    Spacer()
                    if let rating = movie.communityRating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(.caption2))
                            Text(String(format: "%.1f", rating)).font(.system(.caption2, design: .default, weight: .bold))
                        }
                        .foregroundStyle(DT.Color.accent)
                    }
                }
                Text(movie.name)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let year = movie.productionYear {
                    Text(String(year))
                        .font(.system(.caption2))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(10)
        }
        .frame(width: 120 * cardScale, height: 175 * cardScale)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .tvFocusable(cornerRadius: 12)
    }

    // MARK: - Streamystats recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streamystats")
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DT.Color.accent)
                    Text("Recommended For You")
                        .font(.system(.callout, design: .default, weight: .bold))
                        .foregroundStyle(DT.Color.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(statsRepo.recommendations) { rec in
                        if let item = rec.item {
                            VStack(alignment: .leading, spacing: 6) {
                                CachedAsyncImage(url: item.posterURL) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: Rectangle().fill(DT.Color.backgroundTertiary)
                                    }
                                }
                                .frame(width: 90 * cardScale, height: 130 * cardScale)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .clipped()

                                Text(item.displayTitle)
                                    .font(.system(.caption2, design: .default, weight: .semibold))
                                    .foregroundStyle(DT.Color.textPrimary)
                                    .lineLimit(2)
                                    .frame(width: 90 * cardScale, alignment: .leading)

                                if let year = item.productionYear {
                                    Text(String(year))
                                        .font(.system(.caption2))
                                        .foregroundStyle(DT.Color.textSecondary)
                                }
                            }
                            .tvFocusable(cornerRadius: 8)
                        }
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }
}

private extension View {
    /// The remote can only scroll to what it can focus, so on tvOS each card takes focus.
    @ViewBuilder
    func tvFocusable(cornerRadius: CGFloat) -> some View {
        #if os(tvOS)
        focusable().tvFocusRing(cornerRadius: cornerRadius)
        #else
        self
        #endif
    }
}

#Preview {
    StatsView()
        .environment(MediaRepository())
        .environment(StreamystatsRepository())
}
