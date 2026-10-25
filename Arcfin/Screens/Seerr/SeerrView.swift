// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct SeerrView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var mediaType: RequestMediaType = .movie
    @State private var selectedGenre: SeerrGenre? = nil
    @State private var genreResults: [SeerrItem] = []
    @State private var isLoadingGenre = false
    @State private var searchText = ""
    @State private var searchResults: [SeerrItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var requestingItem: SeerrItem? = nil
    @State private var openedItem: SeerrItem?
    /// Popular titles first made in this device's language, when it isn't English.
    @State private var languageItems: [SeerrItem] = []
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Two across fits a phone; on a wider iPad two stretched each poster to half the
    /// screen, so it fills the width with posters of a phone-like size instead.
    private var discoverColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 8)]
        }
        return [.init(.flexible()), .init(.flexible())]
    }
#elseif os(macOS)
    private let discoverColumns = [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 12)]
#else
    private let discoverColumns: [GridItem] = [.init(.flexible()), .init(.flexible())]
#endif

    private var genresForType: [SeerrGenre] {
        mediaType == .tv ? seerrRepo.tvGenres : seerrRepo.movieGenres
    }

    private var trendingForType: [SeerrItem] {
        let trending = seerrRepo.trending.filter { $0.mediaType == mediaType }
        // Seerr can fail trending on its own (500 when its TMDB request fails); popular
        // titles stand in rather than an empty page.
        return trending.isEmpty ? (mediaType == .tv ? seerrRepo.popularTV : seerrRepo.popularMovies) : trending
    }

    private var showsTrending: Bool { seerrRepo.trending.contains { $0.mediaType == mediaType } }

    private var upcomingForType: [SeerrItem] {
        mediaType == .tv ? seerrRepo.upcomingTV : seerrRepo.upcomingMovies
    }

    var body: some View {
        NavigationStack {
            Group {
                if !seerrRepo.isConfigured {
                    notConfiguredView
                } else {
                    mainContent
                }
            }
            .screenBackground()
            .navigationTitle("Discover")
            .arcfinNavTitleLarge("Discover")
            .searchable(text: $searchText, prompt: "Movies, series, people…")
            .navigationDestination(for: SeerrItem.self) { item in
                SeerrItemDetailView(item: item)
            }
            // On the Mac a card's NavigationLink(value:) can't find the destination above.
            .navigationDestination(item: $openedItem) { item in
                SeerrItemDetailView(item: item)
            }
        }
        .task(id: seerrRepo.isConfigured) {
            guard seerrRepo.isConfigured else { return }
            // Refetches live every time this appears, but loadDiscover() only flips the
            // loading flag (and so only shows a skeleton) when there's truly nothing cached
            // yet — otherwise this updates the already-visible list in place.
            async let discover: Void = seerrRepo.loadDiscover()
            async let genres: Void = seerrRepo.loadGenres()
            async let upcoming: Void = seerrRepo.loadUpcoming()
            // The bookmarks on every card read it.
            async let watchlist: Void = seerrRepo.loadWatchlist()
            _ = await (discover, genres, upcoming, watchlist)
        }
        .onChange(of: searchText) { _, query in
            performSearch(query: query)
        }
        .onChange(of: selectedGenre) { _, genre in
            loadGenreResults(genre)
        }
        .onChange(of: mediaType) { _, _ in
            selectedGenre = nil
            genreResults = []
        }
        .sheet(item: $requestingItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Not configured

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .scaledFont(size: 48)
                .foregroundStyle(DT.Color.accent)
            Text("Seerr Not Connected")
                .font(.system(.title3, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Add your Seerr server URL and credentials in Settings → Plugins → Seerr.")
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                if !searchText.isEmpty {
                    searchResultsSection
                } else if let selectedGenre {
                    genreResultsSection(selectedGenre)
                } else {
                    if seerrRepo.isLoadingDiscover && trendingForType.isEmpty {
                        loadingGrid
                    } else if trendingForType.isEmpty, let error = seerrRepo.discoverError {
                        discoverErrorCard(error)
                    } else {
                        trendingSection
                    }
                    if !upcomingForType.isEmpty {
                        upcomingSection
                    }
                    if !languageItems.isEmpty, let languageName {
                        itemGrid(title: "Popular in \(languageName)", items: Array(languageItems.prefix(10)), isLoading: false)
                    }
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .refreshable {
            async let discover: Void = seerrRepo.loadDiscover()
            async let upcoming: Void = seerrRepo.loadUpcoming()
            async let watchlist: Void = seerrRepo.loadWatchlist()
            _ = await (discover, upcoming, watchlist)
            await loadLanguageItems()
        }
        .task(id: mediaType) { await loadLanguageItems() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchText.isEmpty {
                // Movies / TV Shows
                Picker("Media Type", selection: $mediaType) {
                    Text("Movies").tag(RequestMediaType.movie)
                    Text("TV Shows").tag(RequestMediaType.tv)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, DT.Spacing.sm)

                // Genre chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        genreChip(label: "All", isSelected: selectedGenre == nil) {
                            withAnimation(DT.Animation.fast) { selectedGenre = nil }
                        }
                        ForEach(genresForType) { genre in
                            genreChip(label: genre.name, isSelected: selectedGenre == genre) {
                                withAnimation(DT.Animation.fast) { selectedGenre = genre }
                            }
                        }
                    }
                }
                .shelfScrollButtons()
                .padding(.bottom, DT.Spacing.md)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 12)
    }

    private func genreChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.caption2, design: .default, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? DT.Color.accent : DT.Color.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(isSelected ? DT.Color.accent.opacity(0.15) : DT.Color.textPrimary.opacity(0.05))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    isSelected ? DT.Color.accent.opacity(0.45) : DT.Color.textPrimary.opacity(0.08),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trending / Upcoming / Genre sections

    private var deviceLanguage: String? {
        guard let code = Locale.current.language.languageCode?.identifier, code != "en" else { return nil }
        return code
    }

    private var languageName: String? {
        deviceLanguage.flatMap { Locale.current.localizedString(forLanguageCode: $0) }
    }

    private func loadLanguageItems() async {
        guard let deviceLanguage else { return }
        languageItems = await seerrRepo.discoverByLanguage(deviceLanguage, mediaType: mediaType)
    }

    private func discoverErrorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(DT.Color.palette("f59e0b"))
            Text("Couldn't load Discover from Seerr")
                .font(.headline)
                .foregroundStyle(DT.Color.textPrimary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                seerrRepo.clearAuthFailure()
                Task { await seerrRepo.loadDiscover() }
            }
            .buttonStyle(.bordered)
            .tint(DT.Color.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private var trendingSection: some View {
        itemGrid(title: showsTrending ? "Trending Now" : "Popular", items: trendingForType, isLoading: seerrRepo.isLoadingDiscover)
    }

    private var upcomingSection: some View {
        itemGrid(title: "Upcoming", items: upcomingForType, isLoading: false)
    }

    private func genreResultsSection(_ genre: SeerrGenre) -> some View {
        itemGrid(title: genre.name, items: genreResults, isLoading: isLoadingGenre)
    }

    private func itemGrid(title: String, items: [SeerrItem], isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            if items.isEmpty && !isLoading {
                ContentUnavailableView("Nothing Here", systemImage: "film")
                    .frame(height: 160)
            } else {
#if os(tvOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DT.Spacing.shelfGap) {
                        ForEach(items) { item in
                            Button { requestingItem = item } label: {
                                PosterCard(
                                    title: item.title,
                                    subtitle: item.year,
                                    imageURL: item.backdropURL ?? item.posterURL
                                )
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .focusSection()
                }
                .shelfScrollButtons()
#elseif os(macOS)
                LazyVGrid(columns: discoverColumns, spacing: 12) {
                    ForEach(items) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#else
                LazyVGrid(columns: discoverColumns, spacing: 8) {
                    ForEach(items) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#endif
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    private func loadGenreResults(_ genre: SeerrGenre?) {
        guard let genre else { genreResults = []; return }
        isLoadingGenre = true
        genreResults = []
        Task {
            genreResults = await seerrRepo.discoverByGenre(genre.id, mediaType: mediaType)
            isLoadingGenre = false
        }
    }

    private func toggleWatchlist(_ item: SeerrItem) {
        HapticManager.impact(.light)
        Task {
            if seerrRepo.isInWatchlist(item) {
                try? await seerrRepo.removeFromWatchlist(item)
            } else {
                try? await seerrRepo.addToWatchlist(item)
            }
        }
    }

    private func discoverCard(_ item: SeerrItem) -> some View {
        Button { openedItem = item } label: {
            discoverCardContent(item)
        }
        .buttonStyle(.plain)
        .contextMenu(menuItems: {
            let alreadyRequested = seerrRepo.matchingRequest(for: item) != nil
            let isAvailable = item.availabilityStatus == .available
            Button {
                toggleWatchlist(item)
            } label: {
                Label(
                    seerrRepo.isInWatchlist(item) ? "Remove from Watchlist" : "Add to Watchlist",
                    systemImage: seerrRepo.isInWatchlist(item) ? "bookmark.slash" : "bookmark"
                )
            }
            if !isAvailable && !alreadyRequested {
                Button {
                    requestingItem = item
                } label: {
                    Label("Request", systemImage: "plus.circle")
                }
            }
        }, preview: {
            discoverCardPreview(item)
        })
    }

    private func discoverCardPreview(_ item: SeerrItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = item.posterURL {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: posterPlaceholder(item: item)
                        }
                    }
                } else {
                    posterPlaceholder(item: item)
                }
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(item.title)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }

    private func discoverCardContent(_ item: SeerrItem) -> some View {
        let matchingRequest = seerrRepo.matchingRequest(for: item)
        let alreadyRequested = matchingRequest != nil
        let isAvailable = item.availabilityStatus == .available

        return ZStack(alignment: .bottomLeading) {
            // Poster
            if let url = item.posterURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: posterPlaceholder(item: item)
                    }
                }
                .clipped()
            } else {
                posterPlaceholder(item: item)
            }

            // Type badge + watchlist toggle
            VStack {
                HStack {
                    Text(item.mediaType == .tv ? "SERIES" : "MOVIE")
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.5))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Spacer()
                    Button { toggleWatchlist(item) } label: {
                        Image(systemName: seerrRepo.isInWatchlist(item) ? "bookmark.fill" : "bookmark")
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.5))
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .frame(width: 44, height: 44, alignment: .topTrailing)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(seerrRepo.isInWatchlist(item) ? "Remove from watchlist" : "Add to watchlist")
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(8)

            // Bottom info
            VStack(alignment: .leading, spacing: 4) {
                if isAvailable {
                    availabilityPill(label: "Available", hex: "10b981")
                } else if let matchingRequest {
                    let status = matchingRequest.displayStatus
                    availabilityPill(label: status.label, hex: status.colorHex)
                }

                Text(item.title)
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)

                if let year = item.year {
                    Text(year)
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                }

                if !isAvailable && !alreadyRequested {
                    Button { requestingItem = item } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle").font(.system(.caption2))
                            Text("Request").font(.system(.caption2, design: .default, weight: .bold))
                        }
                        .foregroundStyle(DT.Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(DT.Color.accent.opacity(0.15))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DT.Color.accent.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(LinearGradient(
                colors: [.black.opacity(0.95), .clear],
                startPoint: .bottom, endPoint: .top))
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private func posterPlaceholder(item: SeerrItem) -> some View {
        LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func availabilityPill(label: String, hex: String) -> some View {
        StatusPill(label: label, color: DT.Color.palette(hex))
    }

    // MARK: - Loading skeleton

    private var loadingGrid: some View {
        LazyVGrid(columns: discoverColumns, spacing: 8) {
            ForEach(Self.placeholderDiscoverItems) { item in
                discoverCardContent(item)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
        .redacted(reason: .placeholder)
    }

    private static let placeholderDiscoverItems: [SeerrItem] = (0..<6).map { i in
        SeerrItem(id: -(i + 1), title: "Loading Title", mediaType: .movie, year: "0000")
    }

    // MARK: - Search

    /// Debounced, and a response for an older query never replaces a newer one's results.
    private func performSearch(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else { searchResults = []; isSearching = false; return }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let results = await seerrRepo.search(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Search Results")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if isSearching { ProgressView().scaleEffect(0.7) }
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            if !isSearching && searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(height: 200)
            } else {
#if os(tvOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DT.Spacing.shelfGap) {
                        ForEach(searchResults) { item in
                            Button { requestingItem = item } label: {
                                PosterCard(
                                    title: item.title,
                                    subtitle: item.year,
                                    imageURL: item.backdropURL ?? item.posterURL
                                )
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .focusSection()
                }
                .shelfScrollButtons()
#elseif os(macOS)
                LazyVGrid(columns: discoverColumns, spacing: 12) {
                    ForEach(searchResults) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#else
                LazyVGrid(columns: discoverColumns, spacing: 8) {
                    ForEach(searchResults) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#endif
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }
}
