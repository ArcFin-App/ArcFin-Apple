import SwiftUI
import Combine
import JellyfinAPI
import AuthCore

// MARK: - Main tab container

struct MainTabView: View {
    @State private var searchQuery = ""

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Library", systemImage: "square.grid.2x2") {
                placeholderScreen("Library", icon: "square.grid.2x2")
            }
            Tab("Stats", systemImage: "chart.xyaxis.line") {
                StatsView()
            }
            Tab("Requests", systemImage: "clock") {
                JellyseerrView()
            }
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    SearchView(query: $searchQuery)
                        .searchable(text: $searchQuery, prompt: "Movies, shows, people…")
                        .navigationTitle("Search")
                        .navigationBarTitleDisplayMode(.large)
                        .background(DT.Color.backgroundPrimary)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .preferredColorScheme(.dark)
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
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var heroIndex: Int = 0
    private let heroTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var heroItems: [MediaItem] { Array(mediaRepo.recentlyAdded.prefix(4)) }
    private var usePortraitHero: Bool { sizeClass == .compact }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let screenW = proxy.size.width
                let imageH  = usePortraitHero ? screenW * 1.45 : screenW * 9 / 16
                let heroH   = usePortraitHero ? imageH : imageH + 220

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroBanner(imageH: imageH, screenW: screenW)
                            .frame(height: heroH)

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
                    }
                }
                .background(DT.Color.backgroundPrimary)
                // Extend scroll content behind the transparent nav bar
                .ignoresSafeArea(edges: .top)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        ArcfinIconView(size: 20)
                        Text("arcfin")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DT.Color.textPrimary)
                            .tracking(-0.5)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {} label: {
                        Image(systemName: "bell")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)

                    Text(authManager.state.displayInitials)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular.tint(DT.Color.accent), in: .circle)
                }
            }
            // Transparent nav bar — hero image shows through
            .toolbarBackground(.hidden, for: .navigationBar)
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

    // MARK: - Hero banner

    private func heroBanner(imageH: CGFloat, screenW: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                heroBackground(imageH: imageH, screenW: screenW)
                    .overlay(heroImageFade)
                    .animation(DT.Animation.slow, value: heroIndex)
                if !usePortraitHero { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Side vignette
            HStack(spacing: 0) {
                LinearGradient(colors: [DT.Color.backgroundPrimary.opacity(0.3), .clear],
                               startPoint: .leading, endPoint: .trailing).frame(width: 48)
                Spacer()
                LinearGradient(colors: [.clear, DT.Color.backgroundPrimary.opacity(0.3)],
                               startPoint: .leading, endPoint: .trailing).frame(width: 48)
            }

            heroContent.padding(.bottom, usePortraitHero ? 32 : 24)
        }
        .background(DT.Color.backgroundPrimary)
    }

    private var heroImageFade: some View {
        LinearGradient(
            stops: usePortraitHero
                ? [.init(color: .clear, location: 0.3),
                   .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.75),
                   .init(color: DT.Color.backgroundPrimary, location: 1)]
                : [.init(color: .clear, location: 0.4),
                   .init(color: DT.Color.backgroundPrimary.opacity(0.55), location: 0.78),
                   .init(color: DT.Color.backgroundPrimary, location: 1)],
            startPoint: .top, endPoint: .bottom
        )
    }

    @ViewBuilder
    private func heroBackground(imageH: CGFloat, screenW: CGFloat) -> some View {
        let imageType: JellyfinImageType = usePortraitHero ? .primary : .backdrop
        let fillW = usePortraitHero ? 600 : 900

        if let item = heroItems[safe: heroIndex],
           let url = mediaRepo.imageURL(for: item, type: imageType, fillWidth: fillW) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: heroGradient(for: heroIndex)
                }
            }
            .frame(width: screenW, height: imageH)
            .clipped()
        } else {
            heroGradient(for: heroIndex).frame(width: screenW, height: imageH)
        }
    }

    private func heroGradient(for index: Int) -> some View {
        let p: [[Color]] = [
            [Color(hex: "1a0a2e"), Color(hex: "0a1628")],
            [Color(hex: "1c0e00"), Color(hex: "0e0a00")],
            [Color(hex: "0a0a1c"), Color(hex: "060610")],
        ]
        return LinearGradient(colors: p[index % p.count] + [DT.Color.backgroundPrimary],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Hero content

    private var heroContent: some View {
        VStack(spacing: 0) {
            if let item = heroItems[safe: heroIndex] {
                AsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 76)
                            .shadow(color: .black.opacity(0.7), radius: 12)
                    } else {
                        Text(item.name)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(.white)
                            .tracking(-0.8)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.9), radius: 10)
                            .padding(.horizontal, 32)
                    }
                }
                .id(heroIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: heroIndex)

                Text(heroMeta(item))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 7)
                    .animation(nil, value: heroIndex)
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {} label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12))
                            Text("Play").font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 11)
                    }
                    .glassEffect(.regular.tint(DT.Color.accent).interactive(), in: .rect(cornerRadius: 10))

                    Button {} label: {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle").font(.system(size: 12))
                            Text("More Info").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                }
            }
            .padding(.top, 16)

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

    // MARK: - Recently Added

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
        if item.type == .episode {
            return item.seriesName?.nilIfEmpty ?? item.name.nilIfEmpty ?? "Unknown"
        }
        return item.name.nilIfEmpty ?? "Unknown"
    }

    private func itemDisplaySubtitle(_ item: MediaItem) -> String? {
        if item.type == .episode {
            let s = item.parentIndexNumber.map { "S\($0)" }
            let e = item.indexNumber.map { "E\($0)" }
            return [s, e].compactMap { $0 }.joined().nilIfEmpty
        }
        return item.productionYear.map { "\($0)" }
    }
}

// MARK: - AuthState helpers

private extension AuthState {
    var displayInitials: String {
        guard case .authenticated(let cred) = self else { return "?" }
        return cred.displayName.split(separator: " ")
            .prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

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
