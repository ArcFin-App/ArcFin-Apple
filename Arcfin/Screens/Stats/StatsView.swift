// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import StreamystatsAPI

struct StatsView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(StreamystatsRepository.self) private var statsRepo

    @State private var selectedPeriod: String = "All"
    private let periods = ["7D", "30D", "All"]

    private var totalWatched: Int { mediaRepo.playedMovieCount + mediaRepo.playedEpisodeCount }
    private var movieFraction: Double {
        totalWatched > 0 ? Double(mediaRepo.playedMovieCount) / Double(totalWatched) : 0
    }
    private var episodeFraction: Double {
        totalWatched > 0 ? Double(mediaRepo.playedEpisodeCount) / Double(totalWatched) : 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                heroSection
                activityRings
                if !mediaRepo.topShows.isEmpty { showsSection }
                if !mediaRepo.topMovies.isEmpty { moviesSection }
                if statsRepo.isConfigured && !statsRepo.recommendations.isEmpty {
                    recommendationsSection
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
        .task { if statsRepo.isConfigured { await statsRepo.load() } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statsRepo.isConfigured ? "Streamystats" : "Your Library")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(DT.Color.accent)
                Text("Watch History")
                    .font(.system(size: 26, weight: .heavy))
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
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selectedPeriod == p ? DT.Color.accent : DT.Color.textSecondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(selectedPeriod == p ? DT.Color.accent.opacity(0.15) : Color.white.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                selectedPeriod == p ? DT.Color.accent.opacity(0.4) : Color.white.opacity(0.08),
                                lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
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
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(DT.Color.accent)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(totalWatched)")
                        .font(.system(size: 64, weight: .heavy))
                        .foregroundStyle(DT.Color.textPrimary)
                        .tracking(-3)
                    Text("items")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .offset(y: -6)
                }

                HStack(spacing: 16) {
                    statChip("\(mediaRepo.playedMovieCount)", label: "Movies", hex: "8b5cf6")
                    statChip("\(mediaRepo.playedEpisodeCount)", label: "Episodes", hex: "06b6d4")
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
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color(hex: hex))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
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
                value: mediaRepo.playedMovieCount,
                label: "Movies",
                sublabel: "watched",
                fraction: movieFraction,
                hex: "8b5cf6"
            )
            ringCard(
                value: mediaRepo.playedEpisodeCount,
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(sublabel)
                    .font(.system(size: 10))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Top shows

    private var showsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Most Watched Shows")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.2)
                Spacer()
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(Array(mediaRepo.topShows.enumerated()), id: \.element.id) { i, show in
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
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.06))
                Text("\(rank)")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(rank == 1 ? DT.Color.accent : DT.Color.textSecondary)
            }
            .frame(width: 32)

            if let url = mediaRepo.imageURL(for: item) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: RoundedRectangle(cornerRadius: 6).fill(DT.Color.backgroundTertiary)
                    }
                }
                .frame(width: 36, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                if let plays = item.userData?.playCount, plays > 0 {
                    Text("\(plays) episode\(plays == 1 ? "" : "s") played")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.textSecondary)
                } else if let year = item.productionYear {
                    Text(String(year))
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }

            Spacer()

            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(DT.Color.accent)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(rank == 1 ? DT.Color.accent.opacity(0.06) : .white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(
            rank == 1 ? DT.Color.accent.opacity(0.2) : .white.opacity(0.05), lineWidth: 1))
    }

    // MARK: - Top movies

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most Watched Movies")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
                .tracking(-0.2)
                .padding(.horizontal, DT.Spacing.pagePad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(mediaRepo.topMovies.enumerated()), id: \.element.id) { i, movie in
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
                AsyncImage(url: url) { phase in
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
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(DT.Color.accent)
                    Spacer()
                    if let rating = movie.communityRating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(size: 8))
                            Text(String(format: "%.1f", rating)).font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(DT.Color.accent)
                    }
                }
                Text(movie.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let year = movie.productionYear {
                    Text(String(year))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(10)
        }
        .frame(width: 120, height: 175)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    // MARK: - Streamystats recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streamystats")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DT.Color.accent)
                    Text("Recommended For You")
                        .font(.system(size: 16, weight: .bold))
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
                                AsyncImage(url: item.posterURL) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: Rectangle().fill(DT.Color.backgroundTertiary)
                                    }
                                }
                                .frame(width: 90, height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .clipped()

                                Text(item.displayTitle)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(DT.Color.textPrimary)
                                    .lineLimit(2)
                                    .frame(width: 90, alignment: .leading)

                                if let year = item.productionYear {
                                    Text(String(year))
                                        .font(.system(size: 9))
                                        .foregroundStyle(DT.Color.textSecondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }
}

#Preview {
    StatsView()
        .environment(MediaRepository())
        .environment(StreamystatsRepository())
}
