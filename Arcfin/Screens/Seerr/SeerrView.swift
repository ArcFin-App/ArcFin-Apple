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
    @State private var requestingItem: SeerrItem? = nil

    private var genresForType: [SeerrGenre] {
        mediaType == .tv ? seerrRepo.tvGenres : seerrRepo.movieGenres
    }

    private var trendingForType: [SeerrItem] {
        seerrRepo.trending.filter { $0.mediaType == mediaType }
    }

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
            .background(DT.Color.backgroundPrimary)
            .navigationTitle("Discover")
            .arcfinNavTitleLarge("Discover")
            .navigationDestination(for: SeerrItem.self) { item in
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
            _ = await (discover, genres, upcoming)
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
                .font(.system(size: 48))
                .foregroundStyle(DT.Color.accent)
            Text("Seerr Not Connected")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Add your Seerr server URL and credentials in Settings → Plugins → Seerr.")
                .font(.system(size: 14))
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
                    } else {
                        trendingSection
                    }
                    if !upcomingForType.isEmpty {
                        upcomingSection
                    }
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .refreshable {
            async let discover: Void = seerrRepo.loadDiscover()
            async let upcoming: Void = seerrRepo.loadUpcoming()
            _ = await (discover, upcoming)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.Color.textSecondary)
                TextField("Search movies, series, people…", text: $searchText)
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textPrimary)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.06))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1))
            .padding(.bottom, DT.Spacing.sm)

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
                .padding(.bottom, DT.Spacing.md)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 12)
    }

    private func genreChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? DT.Color.accent : DT.Color.textSecondary)
                .padding(.horizontal, 14).padding(.vertical, 5)
                .background(isSelected ? DT.Color.accent.opacity(0.15) : Color.white.opacity(0.05))
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(
                    isSelected ? DT.Color.accent.opacity(0.45) : Color.white.opacity(0.08),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trending / Upcoming / Genre sections

    private var trendingSection: some View {
        itemGrid(title: "Trending Now", items: trendingForType, isLoading: seerrRepo.isLoadingDiscover)
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
#elseif os(macOS)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)], spacing: 8) {
                    ForEach(items) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#else
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
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
        NavigationLink(value: item) {
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
                    AsyncImage(url: url) { phase in
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
                .font(.system(size: 14, weight: .semibold))
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
                AsyncImage(url: url) { phase in
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
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.5))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Spacer()
                    Button { toggleWatchlist(item) } label: {
                        Image(systemName: seerrRepo.isInWatchlist(item) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.5))
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)

                if let year = item.year {
                    Text(year)
                        .font(.system(size: 9))
                        .foregroundStyle(DT.Color.textSecondary)
                }

                if !isAvailable && !alreadyRequested {
                    Button { requestingItem = item } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle").font(.system(size: 9))
                            Text("Request").font(.system(size: 9, weight: .bold))
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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private func posterPlaceholder(item: SeerrItem) -> some View {
        LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func availabilityPill(label: String, hex: String) -> some View {
        StatusPill(label: label, color: Color(hex: hex))
    }

    // MARK: - Loading skeleton

    private var loadingGrid: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
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

    private func performSearch(query: String) {
        guard !query.isEmpty else { searchResults = []; isSearching = false; return }
        isSearching = true
        Task {
            searchResults = await seerrRepo.search(query: query)
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
#elseif os(macOS)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 8)], spacing: 8) {
                    ForEach(searchResults) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#else
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
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
