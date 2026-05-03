import SwiftUI
import Combine

// MARK: - Sample data (replaced by API data later)

private struct HeroItem: Identifiable {
    let id = UUID()
    var title: String
    var meta: String
    var gradient: [Color]
}

private struct ContinueItem: Identifiable {
    let id = UUID()
    var title: String
    var episode: String
    var progress: Double
    var hue: Color
}

private struct MediaItem: Identifiable {
    let id = UUID()
    var title: String
    var year: String
    var hue: Color
}

private struct JellyseerrItem: Identifiable {
    let id = UUID()
    var title: String
    var status: RequestStatus
    var hue: Color
}

private let heroItems: [HeroItem] = [
    HeroItem(title: "Dune: Part Two", meta: "2024 · Sci-Fi · 2h 46m",
             gradient: [Color(hex: "1a0a2e"), Color(hex: "0a1628"), DT.Color.backgroundPrimary]),
    HeroItem(title: "Oppenheimer", meta: "2023 · Drama · 3h 1m",
             gradient: [Color(hex: "1c0e00"), Color(hex: "0e0a00"), DT.Color.backgroundPrimary]),
    HeroItem(title: "The Brutalist", meta: "2024 · Drama · 3h 35m",
             gradient: [Color(hex: "0a0a1c"), Color(hex: "060610"), DT.Color.backgroundPrimary]),
]

private let continueWatching: [ContinueItem] = [
    ContinueItem(title: "Severance", episode: "S2 E7", progress: 0.62, hue: Color(hex: "1a0d2e")),
    ContinueItem(title: "The Last of Us", episode: "S2 E3", progress: 0.31, hue: Color(hex: "0d1a0d")),
    ContinueItem(title: "Shogun", episode: "S1 E9", progress: 0.88, hue: Color(hex: "1a1000")),
    ContinueItem(title: "Fallout", episode: "S1 E5", progress: 0.45, hue: Color(hex: "1a0a00")),
    ContinueItem(title: "True Detective", episode: "S4 E2", progress: 0.15, hue: Color(hex: "0a101a")),
]

private let recentlyAdded: [MediaItem] = [
    MediaItem(title: "Gladiator II", year: "2024", hue: Color(hex: "1c1000")),
    MediaItem(title: "Nosferatu", year: "2024", hue: Color(hex: "0e0010")),
    MediaItem(title: "Alien: Romulus", year: "2024", hue: Color(hex: "00100e")),
    MediaItem(title: "Conclave", year: "2024", hue: Color(hex: "0a0a0a")),
    MediaItem(title: "Heretic", year: "2024", hue: Color(hex: "100810")),
    MediaItem(title: "A Complete Unknown", year: "2024", hue: Color(hex: "080c10")),
]

private let topPicks: [MediaItem] = [
    MediaItem(title: "Blade Runner 2049", year: "2017", hue: Color(hex: "0d0a1a")),
    MediaItem(title: "Arrival", year: "2016", hue: Color(hex: "080d10")),
    MediaItem(title: "The Revenant", year: "2015", hue: Color(hex: "0a0d08")),
    MediaItem(title: "Interstellar", year: "2014", hue: Color(hex: "050510")),
]

private let requests: [JellyseerrItem] = [
    JellyseerrItem(title: "A Real Pain", status: .approved, hue: Color(hex: "0a1010")),
    JellyseerrItem(title: "The Substance", status: .pending, hue: Color(hex: "100808")),
    JellyseerrItem(title: "I Saw the TV Glow", status: .downloading, hue: Color(hex: "080a10")),
]

// MARK: - App tab

enum AppTab: Hashable, CaseIterable {
    case home, search, library, stats, requests

    var label: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .library: "Library"
        case .stats: "Stats"
        case .requests: "Requests"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .library: "square.grid.2x2"
        case .stats: "chart.xyaxis.line"
        case .requests: "clock"
        }
    }

    var activeIcon: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .library: "square.grid.2x2.fill"
        case .stats: "chart.xyaxis.line"
        case .requests: "clock.fill"
        }
    }
}

// MARK: - Main tab container

struct MainTabView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:     HomeView(selectedTab: $selectedTab)
                case .search:   placeholderScreen("Search", icon: "magnifyingglass")
                case .library:  placeholderScreen("Library", icon: "square.grid.2x2")
                case .stats:    StatsView()
                case .requests: JellyseerrView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ArcfinTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func placeholderScreen(_ title: String, icon: String) -> some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .thin))
                    .foregroundStyle(DT.Color.textSecondary)
                Text(title)
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }
}

// MARK: - Home screen

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @State private var heroIndex: Int = 0
    private let heroTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroBanner
                        .frame(height: 260)

                    VStack(spacing: 0) {
                        // Continue Watching
                        ShelfRow(title: "Continue Watching", onSeeAll: {}) {
                            ForEach(continueWatching) { item in
                                PosterCard(
                                    title: item.title,
                                    subtitle: item.episode,
                                    accentHue: item.hue,
                                    progress: item.progress
                                )
                            }
                        }

                        // Recently Added
                        ShelfRow(title: "Recently Added", badge: "NEW", onSeeAll: {}) {
                            ForEach(recentlyAdded) { item in
                                PosterCard(title: item.title, subtitle: item.year, accentHue: item.hue)
                            }
                        }

                        // Jellyseerr Requests
                        ShelfRow(title: "Jellyseerr Requests", badge: "\(requests.count)", onSeeAll: {}) {
                            ForEach(requests) { item in
                                RequestCard(title: item.title, status: item.status, accentHue: item.hue)
                            }
                        }

                        // Top Picks
                        ShelfRow(title: "Streamystats — Your Top Picks", onSeeAll: {}) {
                            ForEach(topPicks) { item in
                                PosterCard(title: item.title, subtitle: item.year, accentHue: item.hue)
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Bottom padding for tab bar
                    Spacer().frame(height: DT.Size.tabBarHeight + 16)
                }
            }

            // Floating tab bar
            ArcfinTabBar(selectedTab: $selectedTab)
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea()
        .onReceive(heroTimer) { _ in
            withAnimation(DT.Animation.slow) {
                heroIndex = (heroIndex + 1) % heroItems.count
            }
        }
    }

    // MARK: - Hero banner

    private var heroBanner: some View {
        let hero = heroItems[heroIndex]
        return ZStack(alignment: .bottom) {
            // Cinematic background
            LinearGradient(
                colors: hero.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .animation(DT.Animation.slow, value: heroIndex)

            // Cinematic overlay (fade to black at bottom)
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.3), DT.Color.backgroundPrimary],
                startPoint: .top,
                endPoint: .bottom
            )

            // Scan lines
            Canvas { context, size in
                for y in stride(from: 0, through: size.height, by: 3) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.black.opacity(0.03))
                    )
                }
            }
            .allowsHitTesting(false)

            // Lens flare accent
            RadialGradient(
                colors: [DT.Color.accent.opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 80
            )
            .frame(width: 120, height: 120)
            .offset(x: 80, y: -80)

            // Nav bar
            VStack {
                navBar
                Spacer()
            }

            // Hero content
            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                // Featured chip
                HStack(spacing: 4) {
                    Circle()
                        .fill(DT.Color.accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: DT.Color.accent, radius: 3)
                    Text("Featured")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(DT.Color.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(DT.Color.accent.opacity(0.12))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DT.Color.accent.opacity(0.3), lineWidth: 1))
                .padding(.bottom, 8)

                Text(hero.title)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-1)
                    .shadow(color: .black.opacity(0.8), radius: 8)
                    .animation(nil, value: heroIndex)

                Text(hero.meta)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .animation(nil, value: heroIndex)

                HStack(spacing: 8) {
                    // Play button
                    Button {
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Play")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(DT.Color.accent)
                        .clipShape(Capsule())
                        .shadow(color: DT.Color.accent.opacity(0.4), radius: 10)
                    }
                    .buttonStyle(.plain)

                    // More Info button
                    Button {
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                            Text("More Info")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.1))
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Hero dots
                    HStack(spacing: 4) {
                        ForEach(heroItems.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == heroIndex ? DT.Color.accent : Color.white.opacity(0.3))
                                .frame(width: i == heroIndex ? 14 : 4, height: 4)
                                .onTapGesture {
                                    withAnimation(DT.Animation.standard) { heroIndex = i }
                                }
                                .animation(DT.Animation.fast, value: heroIndex)
                        }
                    }
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.md)
        }
    }

    // MARK: - Nav bar (Liquid Glass)

    private var navBar: some View {
        HStack {
            HStack(spacing: 6) {
                ArcfinIconView(size: 20)
                Text("arcfin")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
            }

            Spacer()

            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.8))

                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "1e3a5f"), Color(hex: "0d2040")],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .overlay(Circle().stroke(DT.Color.accent.opacity(0.4), lineWidth: 1.5))
                        .frame(width: 28, height: 28)

                    Text("JD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DT.Color.accent)
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .frame(height: 48)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background(.ultraThinMaterial.opacity(0.5))
    }
}

// MARK: - Tab bar (Liquid Glass)

struct ArcfinTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabItem(tab)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(height: DT.Size.tabBarHeight)
        .background(.ultraThinMaterial)
        .background(Color(hex: "0a0a14").opacity(0.72))
        .overlay(
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func tabItem(_ tab: AppTab) -> some View {
        let active = selectedTab == tab
        return Button {
            withAnimation(DT.Animation.fast) { selectedTab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: active ? tab.activeIcon : tab.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(active ? DT.Color.accent : DT.Color.textSecondary)
                    .symbolRenderingMode(active ? .hierarchical : .monochrome)

                Text(tab.label)
                    .font(DT.Font.tabLabel)
                    .fontWeight(active ? .semibold : .regular)
                    .foregroundStyle(active ? DT.Color.accent : DT.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainTabView()
}
