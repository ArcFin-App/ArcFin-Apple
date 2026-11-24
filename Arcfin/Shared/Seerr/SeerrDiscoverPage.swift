// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI
import JellyfinAPI

/// Discover on iPhone, iPad and Mac: lists of wide cards (trending, popular, upcoming) with
/// shelves of posters like Home's between them, including the services picked in Popular
/// Elsewhere, a few genres and titles like the last one watched. Genre and search results are
/// a poster grid. Each platform's `SeerrView` passes its grid spacing.
struct SeerrDiscoverPage: View {
    @Bindable var model: SeerrDiscoverModel
    let gridSpacing: CGFloat

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(MediaRepository.self) private var mediaRepo

    @State private var searchText = ""
    @State private var requestingItem: SeerrItem? = nil
    @State private var openedItem: SeerrItem?
    @State private var pageSize: CGSize = .zero
    @AppStorage(StreamingServicePrefs.key) private var servicesData = Data()

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
            .toolbar {
                if seerrRepo.isConfigured {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            SeerrRequestsListView(filter: nil, title: "Requests")
                        } label: {
                            Label("Requests", systemImage: "text.badge.checkmark")
                        }
                    }
                }
            }
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
        .appSheet(item: $requestingItem) { item in
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
            Text("Add your Seerr server URL and credentials in Settings › Integrations › Seerr.")
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
            VStack(alignment: .leading, spacing: 0) {
                header
                if !searchText.isEmpty {
                    searchResultsSection
                } else if let selectedGenre = model.selectedGenre {
                    posterGrid(title: selectedGenre.name, items: model.genreResults, isLoading: model.isLoadingGenre)
                } else if seerrRepo.isLoadingDiscover && trendingForType.isEmpty {
                    loadingContent
                } else if trendingForType.isEmpty, let error = seerrRepo.discoverError {
                    discoverErrorCard(error)
                } else {
                    discoverShelves
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { pageSize = $0 }
        .refreshable {
            await model.refresh(seerrRepo: seerrRepo)
            await loadMoreRows()
        }
        .task(id: model.mediaType) { await model.loadLanguageItems(seerrRepo: seerrRepo) }
        .task(id: moreRowsKey) { await loadMoreRows() }
    }

    private enum FeaturedKind: String { case trending, popular, upcoming }

    private enum DiscoverBlock: Identifiable {
        case featured(FeaturedKind, [SeerrItem])
        case row(SeerrDiscoverModel.DiscoverRow)

        var id: String {
            switch self {
            case .featured(let kind, _): "featured-\(kind.rawValue)"
            case .row(let row): row.id
            }
        }
    }

    /// Wide cards, a few rows, wide cards again: trending, then titles like the last one
    /// watched, the picked services and genres; popular; more of the same; then upcoming and
    /// whatever rows are left. A title gets a wide card once.
    private var blocks: [DiscoverBlock] {
        var featuredIDs = Set<Int>()
        let services = model.serviceRows
        let genres = model.genreRows
        let language: SeerrDiscoverModel.DiscoverRow? = model.languageName.flatMap { name in
            model.languageItems.isEmpty ? nil
                : .init(id: "language", title: String(localized: "Popular in \(name)"), items: model.languageItems)
        }
        var blocks: [DiscoverBlock] = []
        blocks += featuredBlocks(showsTrending ? .trending : .popular, items: trendingForType,
                                 restTitle: showsTrending ? String(localized: "Trending Now") : String(localized: "Popular"),
                                 featuredIDs: &featuredIDs)
        blocks += [model.becauseYouWatched, services.first, genres.first].compactMap { $0.map(DiscoverBlock.row) }
        if showsTrending {
            blocks += featuredBlocks(.popular, items: model.popular(in: seerrRepo),
                                     restTitle: model.mediaType == .tv ? String(localized: "Popular Series") : String(localized: "Popular Movies"),
                                     featuredIDs: &featuredIDs)
        }
        blocks += [services.dropFirst().first, genres.dropFirst().first, language].compactMap { $0.map(DiscoverBlock.row) }
        blocks += featuredBlocks(.upcoming, items: upcomingForType, restTitle: String(localized: "Upcoming"), featuredIDs: &featuredIDs)
        blocks += (services.dropFirst(2) + genres.dropFirst(2)).map(DiscoverBlock.row)
        return blocks
    }

    private func featuredBlocks(_ kind: FeaturedKind, items: [SeerrItem], restTitle: String, featuredIDs: inout Set<Int>) -> [DiscoverBlock] {
        let top = Array(items.filter { $0.backdropURL != nil && !featuredIDs.contains($0.id) }.prefix(Self.featuredCount))
        featuredIDs.formUnion(top.map(\.id))
        let rest = items.filter { !top.contains($0) }
        var result: [DiscoverBlock] = []
        if !top.isEmpty { result.append(.featured(kind, top)) }
        if !rest.isEmpty { result.append(.row(.init(id: "\(kind.rawValue)-rest", title: restTitle, items: rest))) }
        return result
    }

    private var discoverShelves: some View {
        ForEach(blocks) { block in
            switch block {
            case .featured(let kind, let items): featuredCarousel(items, kind: kind)
            case .row(let row): shelf(title: row.title, items: row.items)
            }
        }
    }

    /// Changes whenever a row beyond Seerr's own lists needs loading again.
    private var moreRowsKey: String {
        let services = StreamingServicePrefs.decode(servicesData).map(\.id)
        return "\(model.mediaType)-\(services)-\(genresForType.count)-\(seerrRepo.hasCatalog)-\(mediaRepo.watchAgain.first?.id ?? "")"
    }

    private func loadMoreRows() async {
        await model.loadMoreRows(seerrRepo: seerrRepo, mediaRepo: mediaRepo, services: StreamingServicePrefs.decode(servicesData))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searchText.isEmpty {
                Picker("Media Type", selection: $model.mediaType) {
                    Text("Movies").tag(RequestMediaType.movie)
                    Text("TV Shows").tag(RequestMediaType.tv)
                }
                .pickerStyle(.segmented)
                .onChange(of: model.mediaType) { HapticManager.selection() }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.sm)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        genreChip(label: String(localized: "All"), isSelected: model.selectedGenre == nil) {
                            withAnimation(DT.Animation.fast) { model.selectedGenre = nil }
                        }
                        ForEach(genresForType) { genre in
                            genreChip(label: genre.name, isSelected: model.selectedGenre == genre) {
                                withAnimation(DT.Animation.fast) { model.selectedGenre = genre }
                            }
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                }
                .shelfScrollButtons()
                .padding(.bottom, DT.Spacing.lg)
            }
        }
        .padding(.top, 12)
    }

    private func genreChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            Text(label)
                .font(.system(.footnote, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DT.Color.onAccent : DT.Color.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(isSelected ? DT.Color.accent : DT.Color.textPrimary.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Featured

    private static let featuredCount = 5

    /// Page-wide on a phone held upright. No taller than 40% of what's on screen, so in
    /// landscape a card leaves room for the rows around it, and no wider than 560 pt, so an
    /// iPad or Mac shows part of the next one.
    private var featuredWidth: CGFloat {
        let available = max(pageSize.width - DT.Spacing.pagePad * 2, 0)
        let fitsHeight = pageSize.height * 0.4 * 16 / 9
        return min(available, 560, fitsHeight)
    }

    private func featuredCarousel(_ items: [SeerrItem], kind: FeaturedKind) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: DT.Spacing.shelfGap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    featuredCard(item, rank: index + 1, kind: kind)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .scrollTargetBehavior(.viewAligned)
        .shelfScrollButtons()
        .padding(.bottom, DT.Spacing.xl)
    }

    private func featuredCard(_ item: SeerrItem, rank: Int, kind: FeaturedKind) -> some View {
        let isAvailable = mediaRepo.hasInLibrary(item)
        let request = isAvailable ? nil : seerrRepo.matchingRequest(for: item)
        let canRequest = !isAvailable && !seerrRepo.isRequested(item) && seerrRepo.mayRequest(item.mediaType)
        let width = featuredWidth
        return ZStack(alignment: .bottomTrailing) {
            Button { openedItem = item } label: {
                ZStack(alignment: .bottomLeading) {
                    CachedAsyncImage(url: item.backdropURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: posterPlaceholder
                        }
                    }
                    .frame(width: width, height: width * 9 / 16)
                    .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.35),
                            .init(color: .black.opacity(0.85), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(featuredLabel(kind, rank: rank))
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(DT.Color.accent)
                        Text(item.title)
                            .font(.system(.title3, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(metaLine(item))
                                .font(.system(.footnote))
                                .foregroundStyle(.white.opacity(0.75))
                            if isAvailable {
                                availabilityPill(label: String(localized: "In Library"), hex: "10b981")
                            } else if let request {
                                let status = request.localizedDisplayStatus
                                availabilityPill(label: status.label, hex: status.colorHex)
                            }
                        }
                    }
                    .padding(DT.Spacing.md)
                    // Leaves room for the buttons in the corner.
                    .padding(.trailing, 96)
                }
                .frame(width: width, height: width * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .contentShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            }
            .buttonStyle(PressableButtonStyle())
            .contextMenu { discoverMenu(item) }

            HStack(spacing: 8) {
                watchlistButton(item)
                if canRequest {
                    Button { requestingItem = item } label: {
                        Image(systemName: "plus")
                            .font(.system(.body, weight: .bold))
                            .foregroundStyle(DT.Color.onAccent)
                            .frame(width: 40, height: 40)
                            .background(DT.Color.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Request \(item.title)")
                }
            }
            .padding(DT.Spacing.md)
        }
    }

    private func featuredLabel(_ kind: FeaturedKind, rank: Int) -> String {
        switch kind {
        case .trending: String(localized: "#\(rank) in Trending")
        case .popular: String(localized: "#\(rank) in Popular")
        case .upcoming: String(localized: "Coming Soon")
        }
    }

    private func watchlistButton(_ item: SeerrItem) -> some View {
        let inWatchlist = seerrRepo.isInWatchlist(item)
        return Button { model.toggleWatchlist(item, seerrRepo: seerrRepo) } label: {
            Image(systemName: inWatchlist ? "bookmark.fill" : "bookmark")
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(inWatchlist ? "Remove from Watchlist" : "Add to Watchlist")
    }

    private func metaLine(_ item: SeerrItem) -> String {
        let kind = item.mediaType == .tv ? String(localized: "Series") : String(localized: "Movie")
        return [item.year, kind].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Shelves and grids

    private func shelf(title: String, items: [SeerrItem]) -> some View {
        ShelfRow(title: title, onSeeAll: nil) {
            ForEach(items) { item in
                poster(item)
            }
        }
        .padding(.bottom, DT.Spacing.xl)
    }

    private func poster(_ item: SeerrItem) -> some View {
        Button { openedItem = item } label: {
            PosterCard(title: item.title, subtitle: posterSubtitle(item), imageURL: item.posterURL)
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu { discoverMenu(item) }
    }

    private func posterSubtitle(_ item: SeerrItem) -> String? {
        let status: String? = mediaRepo.hasInLibrary(item) ? String(localized: "In Library")
            : seerrRepo.isRequested(item) ? String(localized: "Requested") : nil
        return [item.year, status].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    @ViewBuilder
    private func discoverMenu(_ item: SeerrItem) -> some View {
        Button {
            model.toggleWatchlist(item, seerrRepo: seerrRepo)
        } label: {
            Label(
                seerrRepo.isInWatchlist(item) ? "Remove from Watchlist" : "Add to Watchlist",
                systemImage: seerrRepo.isInWatchlist(item) ? "bookmark.slash" : "bookmark"
            )
        }
        if !mediaRepo.hasInLibrary(item), !seerrRepo.isRequested(item), seerrRepo.mayRequest(item.mediaType) {
            Button {
                requestingItem = item
            } label: {
                Label("Request", systemImage: "plus.circle")
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: DT.Size.posterCard.width, maximum: DT.Size.posterCard.width), spacing: gridSpacing)]
    }

    private func posterGrid(title: String, items: [SeerrItem], isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sectionGap) {
            HStack {
                Text(title)
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.7) }
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            if items.isEmpty && !isLoading {
                ContentUnavailableView("Nothing Here", systemImage: "film")
                    .frame(height: 160)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: DT.Spacing.lg) {
                    ForEach(items) { item in
                        poster(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
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
                Task { await seerrRepo.retrySignIn() }
            }
            .buttonStyle(.bordered)
            .tint(DT.Color.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private var posterPlaceholder: some View {
        LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func availabilityPill(label: String, hex: String) -> some View {
        StatusPill(label: label, color: DT.Color.palette(hex))
    }

    // MARK: - Loading skeleton

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .fill(DT.Color.textPrimary.opacity(0.08))
                .frame(width: featuredWidth, height: featuredWidth * 9 / 16)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.xl)
            ShelfRow(title: String(localized: "Trending Now")) {
                ForEach(0..<6, id: \.self) { _ in PosterCard(title: "Loading Title") }
            }
            .redacted(reason: .placeholder)
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchResultsSection: some View {
        if !model.isSearching && model.searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
        } else {
            posterGrid(title: String(localized: "Search Results"), items: model.searchResults, isLoading: model.isSearching)
        }
    }
}
