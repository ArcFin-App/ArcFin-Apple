import SwiftUI

// MARK: - Data

private struct TopShow: Identifiable {
    let id = UUID()
    var title: String
    var episodes: Int
    var hours: Double
    var pct: Int
}

private struct TopMovie: Identifiable {
    let id = UUID()
    var title: String
    var hours: Double
    var rating: Double
    var hue: Color
}

private let monthlyHours: [Double] = [28, 45, 33, 61, 52, 38, 72, 84, 67, 91, 78, 103]
private let monthLabels = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

private let topShows: [TopShow] = [
    TopShow(title: "Severance",       episodes: 18, hours: 14.2, pct: 92),
    TopShow(title: "The Last of Us",  episodes: 13, hours: 12.8, pct: 84),
    TopShow(title: "Shogun",          episodes: 10, hours: 16.5, pct: 76),
    TopShow(title: "Fallout",         episodes:  8, hours:  7.9, pct: 61),
    TopShow(title: "True Detective",  episodes:  6, hours:  5.4, pct: 45),
]

private let topMovies: [TopMovie] = [
    TopMovie(title: "Dune: Part Two",    hours: 2.8, rating: 9.2, hue: Color(hex: "1a0a2e")),
    TopMovie(title: "Oppenheimer",       hours: 3.1, rating: 9.0, hue: Color(hex: "1c0e00")),
    TopMovie(title: "Blade Runner 2049", hours: 2.8, rating: 9.5, hue: Color(hex: "0d0a1a")),
    TopMovie(title: "The Revenant",      hours: 2.7, rating: 8.8, hue: Color(hex: "0a0d08")),
]

// Heatmap — 52 weeks × 7 days, intensity 0-4
private let heatmapData: [[Int]] = (0..<52).map { _ in
    (0..<7).map { _ in
        let r = Double.random(in: 0...1)
        return r < 0.35 ? 0 : r < 0.55 ? 1 : r < 0.72 ? 2 : r < 0.87 ? 3 : 4
    }
}

// MARK: - View

struct StatsView: View {
    @State private var selectedPeriod: String = "1Y"
    @State private var hoveredMonth: Int? = nil
    private let periods = ["7D", "30D", "1Y"]
    private let maxHours = monthlyHours.max() ?? 1

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                heroCard
                statCards
                heatmap
                showsSection
                moviesSection

                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Streamystats")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(DT.Color.accent)

                Text("Your Watch History")
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
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selectedPeriod == p ? DT.Color.accent.opacity(0.15) : Color.white.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(
                                    selectedPeriod == p ? DT.Color.accent.opacity(0.4) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 52)
        .padding(.bottom, DT.Spacing.md)
        .background(
            LinearGradient(
                colors: [DT.Color.accent.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Hero watch-time card with bar chart

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Ambient glow
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Watch Time · 2026")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(DT.Color.accent)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("847")
                            .font(.system(size: 52, weight: .heavy))
                            .foregroundStyle(DT.Color.textPrimary)
                            .tracking(-2)
                        Text("h")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(DT.Color.accent)
                            .tracking(-0.5)
                    }

                    HStack(spacing: 4) {
                        Text("35.3 days ·")
                            .foregroundStyle(.white.opacity(0.4))
                        Text("↑ 23%")
                            .foregroundStyle(DT.Color.accent)
                        Text("vs last year")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .font(.system(size: 12))

                    // Bar chart
                    barChart
                        .padding(.top, DT.Spacing.sm)

                    // Month labels
                    HStack(spacing: 0) {
                        ForEach(Array(monthLabels.enumerated()), id: \.offset) { _, m in
                            Text(m)
                                .font(.system(size: 7))
                                .foregroundStyle(.white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 3)
                }

                // Corner ambient glow
                RadialGradient(
                    colors: [DT.Color.accent.opacity(0.12), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 60
                )
                .frame(width: 120, height: 120)
                .offset(x: 20, y: -20)
                .allowsHitTesting(false)
            }
            .padding(20)
            .background(DT.Color.accent.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(DT.Color.accent.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.sm)
    }

    private var barChart: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(monthlyHours.enumerated()), id: \.offset) { i, h in
                    let barHeight = CGFloat(h / maxHours) * 36
                    let isHovered = hoveredMonth == i
                    let isLast = i == monthlyHours.count - 1

                    ZStack(alignment: .bottom) {
                        if isHovered {
                            VStack(spacing: 2) {
                                Text("\(Int(h))h")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(DT.Color.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "0e121c").opacity(0.95))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(DT.Color.accent.opacity(0.3), lineWidth: 1)
                                    )
                                Spacer()
                            }
                            .frame(height: 36 + 20)
                        }

                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                isHovered ? DT.Color.accent :
                                    isLast ? DT.Color.accent.opacity(0.7) :
                                    DT.Color.accent.opacity(0.25)
                            )
                            .frame(height: max(2, barHeight))
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .onHover { hovering in
                        hoveredMonth = hovering ? i : nil
                    }
                    .onTapGesture { hoveredMonth = hoveredMonth == i ? nil : i }
                }
            }
            .frame(height: 36, alignment: .bottom)
        }
        .frame(height: 36)
        .animation(DT.Animation.fast, value: hoveredMonth)
    }

    // MARK: - Stat cards

    private var statCards: some View {
        HStack(spacing: 8) {
            miniStatCard(label: "Episodes", value: "342", sub: "this year",  accent: DT.Color.accent.opacity(0.08))
            miniStatCard(label: "Movies",   value: "94",  sub: "watched",    accent: Color(hex: "8b5cf6").opacity(0.08))
            miniStatCard(label: "Streak",   value: "12d", sub: "current",    accent: Color(hex: "10b981").opacity(0.08))
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

    // MARK: - Activity heatmap

    private var heatmap: some View {
        let intensityColors: [Color] = [
            .white.opacity(0.04),
            DT.Color.accent.opacity(0.18),
            DT.Color.accent.opacity(0.38),
            DT.Color.accent.opacity(0.62),
            DT.Color.accent.opacity(0.9),
        ]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Activity Heatmap")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)

                Spacer()

                HStack(spacing: 4) {
                    Text("Less")
                        .font(.system(size: 9))
                        .foregroundStyle(DT.Color.textSecondary)
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(intensityColors[i])
                            .frame(width: 8, height: 8)
                    }
                    Text("More")
                        .font(.system(size: 9))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(heatmapData.indices, id: \.self) { week in
                        VStack(spacing: 2) {
                            ForEach(heatmapData[week].indices, id: \.self) { day in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(intensityColors[heatmapData[week][day]])
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.sm)
    }

    // MARK: - Top shows

    private var showsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Top Shows")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Button("See All") {}
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DT.Color.accent)
                    .buttonStyle(.plain)
            }

            ForEach(Array(topShows.enumerated()), id: \.element.id) { i, show in
                ZStack(alignment: .leading) {
                    // Bar fill behind
                    LinearGradient(
                        colors: [DT.Color.accent.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: CGFloat(show.pct) / 100, anchor: .leading)

                    HStack(spacing: 10) {
                        Text("#\(i + 1)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(DT.Color.accent)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(show.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                            Text("\(show.episodes) eps · \(show.hours, specifier: "%.1f")h")
                                .font(DT.Font.caption2)
                                .foregroundStyle(DT.Color.textSecondary)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(.white.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(DT.Color.accent)
                                        .frame(width: geo.size.width * CGFloat(show.pct) / 100)
                                }
                            }
                            .frame(width: 60, height: 4)

                            Text("\(show.pct)%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DT.Color.accent)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.sm)
    }

    // MARK: - Top movies

    private var moviesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Top Movies")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Button("See All") {}
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DT.Color.accent)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topMovies) { movie in
                        VStack(alignment: .leading, spacing: 8) {
                            // Mini poster
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(LinearGradient(
                                        colors: [movie.hue, Color(hex: "0a0a12")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.06), lineWidth: 1))
                            }
                            .frame(width: 40, height: 56)

                            Text(movie.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(2)
                                .lineSpacing(2)

                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(DT.Color.accent)
                                Text(movie.rating, format: .number.precision(.fractionLength(1)))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(DT.Color.accent)
                                Text("· \(movie.hours, specifier: "%.1f")h")
                                    .font(.system(size: 9))
                                    .foregroundStyle(DT.Color.textSecondary)
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
}

#Preview {
    StatsView()
}
