import SwiftUI
import Combine
import JellyfinAPI
import AuthCore

// MARK: - App tab

enum AppTab: Hashable, CaseIterable {
    case home, search, library, stats, requests

    var label: String {
        switch self {
        case .home:     "Home"
        case .search:   "Search"
        case .library:  "Library"
        case .stats:    "Stats"
        case .requests: "Requests"
        }
    }

    var icon: String {
        switch self {
        case .home:     "house"
        case .search:   "magnifyingglass"
        case .library:  "square.grid.2x2"
        case .stats:    "chart.xyaxis.line"
        case .requests: "clock"
        }
    }

    var activeIcon: String {
        switch self {
        case .home:     "house.fill"
        case .search:   "magnifyingglass"
        case .library:  "square.grid.2x2.fill"
        case .stats:    "chart.xyaxis.line"
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
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo

    @State private var heroIndex: Int = 0
    private let heroTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    private var heroItems: [MediaItem] { Array(mediaRepo.recentlyAdded.prefix(3)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroBanner.frame(height: 260)

                    VStack(spacing: 0) {
                        // Continue Watching
                        if !mediaRepo.continueWatching.isEmpty {
                            ShelfRow(title: "Continue Watching", onSeeAll: {}) {
                                ForEach(mediaRepo.continueWatching) { item in
                                    PosterCard(
                                        title: itemDisplayTitle(item),
                                        subtitle: itemDisplaySubtitle(item),
                                        progress: item.userData?.playedPercentage.map { $0 / 100 },
                                        imageURL: mediaRepo.imageURL(for: item)
                                    )
                                }
                            }
                        }

                        // Recently Added
                        ShelfRow(title: "Recently Added", badge: "NEW", onSeeAll: {}) {
                            recentlyAddedContent
                        }
                    }
                    .padding(.top, 8)

                    Spacer().frame(height: DT.Size.tabBarHeight + 16)
                }
            }

            ArcfinTabBar(selectedTab: $selectedTab)
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea()
        .task {
            guard case .authenticated(let cred) = authManager.state else { return }
            await mediaRepo.load(credential: cred, authClient: authManager.authClient)
        }
        .onReceive(heroTimer) { _ in
            guard heroItems.count > 1 else { return }
            withAnimation(DT.Animation.slow) { heroIndex = (heroIndex + 1) % heroItems.count }
        }
    }

    // MARK: - Hero banner

    private var heroBanner: some View {
        ZStack(alignment: .bottom) {
            heroBackground
                .animation(DT.Animation.slow, value: heroIndex)

            // Cinematic overlay
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

            // Lens flare
            RadialGradient(colors: [DT.Color.accent.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 80)
                .frame(width: 120, height: 120)
                .offset(x: 80, y: -80)

            VStack { navBar; Spacer() }

            heroContent
        }
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let item = heroItems[safe: heroIndex],
           let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 800) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill().clipped()
                default:
                    heroGradient(for: heroIndex)
                }
            }
        } else {
            heroGradient(for: heroIndex)
        }
    }

    private func heroGradient(for index: Int) -> some View {
        let gradients: [[Color]] = [
            [Color(hex: "1a0a2e"), Color(hex: "0a1628"), DT.Color.backgroundPrimary],
            [Color(hex: "1c0e00"), Color(hex: "0e0a00"), DT.Color.backgroundPrimary],
            [Color(hex: "0a0a1c"), Color(hex: "060610"), DT.Color.backgroundPrimary],
        ]
        let colors = gradients[index % gradients.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroContent: some View {
        let item = heroItems[safe: heroIndex]
        let title = item?.name ?? "Arcfin"
        let meta = heroMeta(item)
        let dotCount = max(heroItems.count, 1)

        return VStack(alignment: .leading, spacing: 0) {
            Spacer()

            HStack(spacing: 4) {
                Circle().fill(DT.Color.accent).frame(width: 5, height: 5).shadow(color: DT.Color.accent, radius: 3)
                Text("Featured")
                    .font(.system(size: 9, weight: .bold)).tracking(0.8).textCase(.uppercase)
                    .foregroundStyle(DT.Color.accent)
            }
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(DT.Color.accent.opacity(0.12)).background(.ultraThinMaterial)
            .clipShape(Capsule()).overlay(Capsule().stroke(DT.Color.accent.opacity(0.3), lineWidth: 1))
            .padding(.bottom, 8)

            Text(title)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(DT.Color.textPrimary)
                .tracking(-1).shadow(color: .black.opacity(0.8), radius: 8)
                .animation(nil, value: heroIndex)

            Text(meta)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4).padding(.bottom, 12)
                .animation(nil, value: heroIndex)

            HStack(spacing: 8) {
                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text("Play").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(DT.Color.accent).clipShape(Capsule())
                    .shadow(color: DT.Color.accent.opacity(0.4), radius: 10)
                }
                .buttonStyle(.plain)

                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 10))
                        Text("More Info").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.white.opacity(0.1)).background(.ultraThinMaterial)
                    .clipShape(Capsule()).overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        Capsule()
                            .fill(i == heroIndex ? DT.Color.accent : Color.white.opacity(0.3))
                            .frame(width: i == heroIndex ? 14 : 4, height: 4)
                            .onTapGesture { withAnimation(DT.Animation.standard) { heroIndex = i } }
                            .animation(DT.Animation.fast, value: heroIndex)
                    }
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    private func heroMeta(_ item: MediaItem?) -> String {
        guard let item else { return "" }
        var parts: [String] = []
        if let year = item.productionYear { parts.append("\(year)") }
        parts.append(item.type == .series ? "Series" : "Movie")
        return parts.joined(separator: " · ")
    }

    // MARK: - Nav bar

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
                        .fill(LinearGradient(colors: [Color(hex: "1e3a5f"), Color(hex: "0d2040")], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().stroke(DT.Color.accent.opacity(0.4), lineWidth: 1.5))
                        .frame(width: 28, height: 28)
                    Text(authManager.state.displayInitials)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DT.Color.accent)
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .frame(height: 48)
        .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
        .background(.ultraThinMaterial.opacity(0.5))
    }

    // MARK: - Recently Added content

    @ViewBuilder
    private var recentlyAddedContent: some View {
        if mediaRepo.recentlyAdded.isEmpty {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: DT.Size.posterCard.width, height: DT.Size.posterCard.height)
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(.white.opacity(0.04), lineWidth: 1))
            }
        } else {
            ForEach(mediaRepo.recentlyAdded) { item in
                PosterCard(
                    title: item.name,
                    subtitle: item.productionYear.map { "\($0)" },
                    imageURL: mediaRepo.imageURL(for: item)
                )
            }
        }
    }

    // MARK: - Helpers

    private func itemDisplayTitle(_ item: MediaItem) -> String {
        if item.type == .episode, let series = item.seriesName { return series }
        return item.name
    }

    private func itemDisplaySubtitle(_ item: MediaItem) -> String? {
        if item.type == .episode {
            let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
            let e = item.indexNumber.map { "E\($0)" } ?? ""
            let se = [s, e].filter { !$0.isEmpty }.joined()
            return se.isEmpty ? nil : se
        }
        return item.productionYear.map { "\($0)" }
    }
}

// MARK: - Tab bar

struct ArcfinTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in tabItem(tab) }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(height: DT.Size.tabBarHeight)
        .background(.ultraThinMaterial)
        .background(Color(hex: "0a0a14").opacity(0.72))
        .overlay(Rectangle().fill(.white.opacity(0.07)).frame(height: 1), alignment: .top)
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

// MARK: - AuthState + display helpers

private extension AuthState {
    var displayInitials: String {
        guard case .authenticated(let cred) = self else { return "?" }
        let words = cred.displayName.split(separator: " ")
        let initials = words.prefix(2).compactMap { $0.first }.map { String($0) }.joined()
        return initials.uppercased().isEmpty ? "?" : initials.uppercased()
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(MediaRepository())
}
