// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// Discover on iPhone, iPad and Mac: trending, upcoming and genre grids of request cards, and
/// Seerr search. Each platform's `SeerrView` passes its grid columns and spacing.
struct SeerrDiscoverPage: View {
    @Bindable var model: SeerrDiscoverModel
    let discoverColumns: [GridItem]
    let gridSpacing: CGFloat

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(MediaRepository.self) private var mediaRepo

    @State private var searchText = ""
    @State private var requestingItem: SeerrItem? = nil
    @State private var openedItem: SeerrItem?

    private var genresForType: [SeerrGenre] { model.genres(in: seerrRepo) }
    private var trendingForType: [SeerrItem] { model.trending(in: seerrRepo) }
    private var showsTrending: Bool { model.showsTrending(in: seerrRepo) }
    private var upcomingForType: [SeerrItem] { model.upcoming(in: seerrRepo) }

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
            await model.load(seerrRepo: seerrRepo)
        }
        .onChange(of: searchText) { _, query in
            model.search(query, seerrRepo: seerrRepo)
        }
        .onChange(of: model.selectedGenre) { _, genre in
            model.loadGenreResults(genre, seerrRepo: seerrRepo)
        }
        .onChange(of: model.mediaType) { _, _ in
            model.mediaTypeChanged()
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
                } else if let selectedGenre = model.selectedGenre {
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
                    if !model.languageItems.isEmpty, let languageName = model.languageName {
                        itemGrid(title: "Popular in \(languageName)", items: Array(model.languageItems.prefix(10)), isLoading: false)
                    }
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .refreshable { await model.refresh(seerrRepo: seerrRepo) }
        .task(id: model.mediaType) { await model.loadLanguageItems(seerrRepo: seerrRepo) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchText.isEmpty {
                // Movies / TV Shows
                Picker("Media Type", selection: $model.mediaType) {
                    Text("Movies").tag(RequestMediaType.movie)
                    Text("TV Shows").tag(RequestMediaType.tv)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, DT.Spacing.sm)

                // Genre chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        genreChip(label: "All", isSelected: model.selectedGenre == nil) {
                            withAnimation(DT.Animation.fast) { model.selectedGenre = nil }
                        }
                        ForEach(genresForType) { genre in
                            genreChip(label: genre.name, isSelected: model.selectedGenre == genre) {
                                withAnimation(DT.Animation.fast) { model.selectedGenre = genre }
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
        itemGrid(title: genre.name, items: model.genreResults, isLoading: model.isLoadingGenre)
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
                LazyVGrid(columns: discoverColumns, spacing: gridSpacing) {
                    ForEach(items) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    private func discoverCard(_ item: SeerrItem) -> some View {
        Button { openedItem = item } label: {
            discoverCardContent(item)
        }
        .buttonStyle(.plain)
        .contextMenu(menuItems: {
            let alreadyRequested = seerrRepo.matchingRequest(for: item) != nil
            let isAvailable = mediaRepo.hasInLibrary(item)
            Button {
                model.toggleWatchlist(item, seerrRepo: seerrRepo)
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
        let isAvailable = mediaRepo.hasInLibrary(item)

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
                    Button { model.toggleWatchlist(item, seerrRepo: seerrRepo) } label: {
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

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Search Results")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if model.isSearching { ProgressView().scaleEffect(0.7) }
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            if !model.isSearching && model.searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(height: 200)
            } else {
                LazyVGrid(columns: discoverColumns, spacing: gridSpacing) {
                    ForEach(model.searchResults) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }
}
