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
    private let heroTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var heroItems: [MediaItem] { Array(mediaRepo.recentlyAdded.prefix(4)) }

    var body: some View {
        // GeometryReader BEFORE ignoresSafeArea so we capture the real top inset
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ZStack(alignment: .bottom) {
                // Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroBanner(topInset: topInset)
                            .frame(height: 480 + topInset)

                        VStack(spacing: 0) {
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

                            ShelfRow(title: "Recently Added", badge: "NEW", onSeeAll: {}) {
                                recentlyAddedContent
                            }
                        }
                        .padding(.top, 12)

                        Spacer().frame(height: DT.Size.tabBarHeight + 24)
                    }
                }

                // Tab bar
                ArcfinTabBar(selectedTab: $selectedTab)
            }
            .background(DT.Color.backgroundPrimary)
            .ignoresSafeArea()
            // Nav bar floats above everything, padded into safe area
            .overlay(alignment: .top) {
                navBar(topInset: topInset)
            }
        }
        .task {
            guard case .authenticated(let cred) = authManager.state else { return }
            await mediaRepo.load(credential: cred, authClient: authManager.authClient)
        }
        .onReceive(heroTimer) { _ in
            guard heroItems.count > 1 else { return }
            withAnimation(DT.Animation.slow) { heroIndex = (heroIndex + 1) % heroItems.count }
        }
    }

    // MARK: - Nav bar overlay

    private func navBar(topInset: CGFloat) -> some View {
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
                    .foregroundStyle(.white.opacity(0.85))

                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "1e3a5f"), Color(hex: "0d2040")],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay(Circle().stroke(DT.Color.accent.opacity(0.4), lineWidth: 1.5))
                        .frame(width: 30, height: 30)
                    Text(authManager.state.displayInitials)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DT.Color.accent)
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, topInset + 6)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Hero banner

    private func heroBanner(topInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            // Backdrop image — fills full frame
            heroBackground
                .animation(DT.Animation.slow, value: heroIndex)

            // Heavy bottom fade (Netflix-style)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.1), location: 0.35),
                    .init(color: .black.opacity(0.55), location: 0.65),
                    .init(color: DT.Color.backgroundPrimary, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Side vignette
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [DT.Color.backgroundPrimary.opacity(0.3), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 50)
                Spacer()
                LinearGradient(
                    colors: [.clear, DT.Color.backgroundPrimary.opacity(0.3)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 50)
            }

            // Bottom: logo / title + actions + dots
            heroContent
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let item = heroItems[safe: heroIndex],
           let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 900) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    heroGradient(for: heroIndex)
                }
            }
            .clipped()
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
        VStack(spacing: 0) {
            // Logo image or title text — centred
            if let item = heroItems[safe: heroIndex] {
                AsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
                    if case .success(let img) = phase {
                        img.resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 80)
                            .shadow(color: .black.opacity(0.7), radius: 12)
                    } else {
                        Text(item.name)
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(.white)
                            .tracking(-0.8)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.9), radius: 10)
                            .padding(.horizontal, DT.Spacing.pagePad)
                    }
                }
                .id(heroIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: heroIndex)

                Text(heroMeta(item))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 8)
                    .animation(nil, value: heroIndex)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 12))
                        Text("Play").font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(minWidth: 100)
                    .padding(.vertical, 11)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button {} label: {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").font(.system(size: 12))
                        Text("More Info").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(minWidth: 100)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.12))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 16)

            // Page dots
            if heroItems.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<heroItems.count, id: \.self) { i in
                        Capsule()
                            .fill(i == heroIndex ? .white : Color.white.opacity(0.3))
                            .frame(width: i == heroIndex ? 18 : 6, height: 5)
                            .onTapGesture { withAnimation(DT.Animation.standard) { heroIndex = i } }
                            .animation(DT.Animation.fast, value: heroIndex)
                    }
                }
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func heroMeta(_ item: MediaItem) -> String {
        var parts: [String] = []
        if let year = item.productionYear { parts.append("\(year)") }
        parts.append(item.type == .series ? "Series" : "Movie")
        return parts.joined(separator: " · ")
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
        switch item.type {
        case .episode:
            // Prefer series name; fall back to episode name; then "Unknown"
            return item.seriesName?.nilIfEmpty ?? item.name.nilIfEmpty ?? "Unknown"
        default:
            return item.name.nilIfEmpty ?? "Unknown"
        }
    }

    private func itemDisplaySubtitle(_ item: MediaItem) -> String? {
        switch item.type {
        case .episode:
            let s = item.parentIndexNumber.map { "S\($0)" }
            let e = item.indexNumber.map { "E\($0)" }
            return [s, e].compactMap { $0 }.joined().nilIfEmpty
        default:
            return item.productionYear.map { "\($0)" }
        }
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

// MARK: - AuthState helpers

private extension AuthState {
    var displayInitials: String {
        guard case .authenticated(let cred) = self else { return "?" }
        let words = cred.displayName.split(separator: " ")
        return words.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}

// MARK: - String helpers

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
