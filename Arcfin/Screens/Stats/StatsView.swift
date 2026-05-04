import SwiftUI

struct StatsView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(StreamystatsRepository.self) private var statsRepo

    @State private var selectedPeriod: String = "All"
    @State private var hoveredMonth: Int? = nil
    private let periods = ["7D", "30D", "All"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                heroCard
                statCards
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
                    .font(.system(size: 24, weight: .heavy))
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
            colors: [DT.Color.accent.opacity(0.06), .clear],
            startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library Stats")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(DT.Color.accent)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        let totalItems = mediaRepo.playedMovieCount + mediaRepo.playedEpisodeCount
                        Text("\(totalItems)")
                            .font(.system(size: 52, weight: .heavy))
                            .foregroundStyle(DT.Color.textPrimary)
                            .tracking(-2)
                        Text(" items")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(DT.Color.accent)
                            .tracking(-0.5)
                    }

                    HStack(spacing: 4) {
                        Text("\(mediaRepo.playedMovieCount) movies ·")
                            .foregroundStyle(.white.opacity(0.4))
                        Text("\(mediaRepo.playedEpisodeCount) episodes")
                            .foregroundStyle(DT.Color.accent)
                        Text("watched")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .font(.system(size: 12))
                }

                RadialGradient(
                    colors: [DT.Color.accent.opacity(0.12), .clear],
                    center: .center, startRadius: 0, endRadius: 60)
                .frame(width: 120, height: 120)
                .offset(x: 20, y: -20)
                .allowsHitTesting(false)
            }
            .padding(20)
            .background(DT.Color.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(DT.Color.accent.opacity(0.15), lineWidth: 1))
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.sm)
    }

    // MARK: - Stat cards

    private var statCards: some View {
        HStack(spacing: 8) {
            miniStatCard(
                label: "Movies",
                value: "\(mediaRepo.playedMovieCount)",
                sub: "watched",
                accent: Color(hex: "8b5cf6").opacity(0.08))
            miniStatCard(
                label: "Episodes",
                value: "\(mediaRepo.playedEpisodeCount)",
                sub: "watched",
                accent: DT.Color.accent.opacity(0.08))
            miniStatCard(
                label: "Libraries",
                value: "\(mediaRepo.libraries.count)",
                sub: "connected",
                accent: Color(hex: "10b981").opacity(0.08))
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.sm)
    }

    private func miniStatCard(label: String, value: String, sub: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Color.clear
                RadialGradient(colors: [accent, .clear], center: .center, startRadius: 0, endRadius: 30)
                    .frame(width: 60, height: 60)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(DT.Color.textSecondary)
            Text(value)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(DT.Color.textPrimary)
                .tracking(-1)
            Text(sub)
                .font(DT.Font.caption2)
                .foregroundStyle(DT.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: - Top shows (real Jellyfin data)

    private var showsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Most Watched Shows")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
            }

            ForEach(Array(mediaRepo.topShows.enumerated()), id: \.element.id) { i, show in
                showRow(rank: i + 1, item: show)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.sm)
    }

    private func showRow(rank: Int, item: MediaItem) -> some View {
        HStack(spacing: 10) {
            Text("#\(rank)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(DT.Color.accent)
                .frame(width: 24)

            if let url = mediaRepo.imageURL(for: item) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 4).fill(DT.Color.backgroundTertiary)
                    }
                }
                .frame(width: 30, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                if let plays = item.userData?.playCount, plays > 0 {
                    Text("\(plays) episode\(plays == 1 ? "" : "s") played")
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                } else if let year = item.productionYear {
                    Text("\(year)")
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Top movies (real Jellyfin data)

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Most Watched Movies")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, DT.Spacing.pagePad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(mediaRepo.topMovies) { movie in
                        VStack(alignment: .leading, spacing: 8) {
                            if let url = mediaRepo.imageURL(for: movie) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: RoundedRectangle(cornerRadius: 6).fill(DT.Color.backgroundTertiary)
                                    }
                                }
                                .frame(width: 40, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.06), lineWidth: 1))
                            }
                            Text(movie.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(2)
                                .lineSpacing(2)
                            if let rating = movie.communityRating, rating > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(DT.Color.accent)
                                    Text(rating, format: .number.precision(.fractionLength(1)))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(DT.Color.accent)
                                }
                            }
                        }
                        .padding(12)
                        .frame(width: 130, alignment: .leading)
                        .background(.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.07), lineWidth: 1))
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Streamystats recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streamystats")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DT.Color.accent)
                    Text("Recommended For You")
                        .font(DT.Font.cardTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
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
                                    Text("\(year)")
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
