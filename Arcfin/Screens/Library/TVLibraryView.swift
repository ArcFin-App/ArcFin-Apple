// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(tvOS)
import SwiftUI
import JellyfinAPI
import AuthCore

struct TVLibraryView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager

    private let columns = [GridItem(.adaptive(minimum: 400), spacing: 20)]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if mediaRepo.libraries.isEmpty {
                        ContentUnavailableView(
                            "No Libraries",
                            systemImage: "square.grid.2x2",
                            description: Text("Your Jellyfin libraries will appear here.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 400)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(mediaRepo.libraries) { library in
                                NavigationLink(value: library) {
                                    TVBigLibraryCard(library: library)
                                }
                                .buttonStyle(TVCardButtonStyle())
                                .focusEffectDisabled()
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.top, 48)
                        .padding(.bottom, 60)
                        .focusSection()
                    }
                }
            }
            .background(DT.Color.backgroundPrimary)
            .navigationDestination(for: JellyfinLibrary.self) { library in
                LibraryDetailView(library: library)
            }
            .navigationDestination(for: MediaItem.self) { item in
                TVMediaDetailView(item: item)
            }
            .navigationDestination(for: LibraryNavTarget.self) { target in
                switch target {
                case .media(let item):       TVMediaDetailView(item: item)
                case .collection(let item):  TVCollectionDetailView(item: item)
                }
            }
        }
    }
}

// MARK: - Collection detail (BoxSet)

struct TVCollectionDetailView: View {
    let item: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(StreamystatsRepository.self) private var statsRepo

    @State private var items: [MediaItem] = []
    @State private var selectedItem: MediaItem?
    @State private var playbackRequest: PlaybackRequest?

    @State private var availableGenres: [String] = []
    @State private var availableYears: [Int] = []
    @State private var selectedGenres: Set<String> = []
    @State private var selectedYears: Set<Int> = []
    @State private var watchedFilter: LibraryWatchedFilter = .all
    @State private var favoritesOnly = false
    @State private var sortOption: LibrarySortOption = .nameAsc
    @State private var showFilterSheet = false
    /// Mirrors LibraryDetailView.fetchFirstPage()'s guard (commit 708b3fc) — every filter/sort
    /// change spawns its own uncancelled fetch, so an older, slower response could otherwise
    /// overwrite a newer one's results.
    @State private var fetchGeneration = 0

    private var filtersActive: Bool {
        !selectedGenres.isEmpty || !selectedYears.isEmpty || watchedFilter != .all || favoritesOnly
    }

    private let client = JellyfinMediaClient()
    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    var body: some View {
        GeometryReader { proxy in
            let sh = proxy.size.height
            let sw = proxy.size.width

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    showcaseSection(screenW: sw, screenH: sh)
                        .frame(height: sh * 0.88)
                    belowFoldSection
                        .padding(.vertical, 72)
                        .focusSection()
                }
                .focusSection()
            }
            .ignoresSafeArea()
        }
        .background(DT.Color.backgroundPrimary)
        .navigationDestination(item: $selectedItem) { i in
            TVMediaDetailView(item: i)
        }
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                playbackRequest = PlaybackRequest(item: next, startTicks: 0)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            NavigationStack {
                TVLibraryFilterList(
                    availableGenres: availableGenres, availableYears: availableYears,
                    selectedGenres: $selectedGenres, selectedYears: $selectedYears,
                    watchedFilter: $watchedFilter, favoritesOnly: $favoritesOnly, sortOption: $sortOption
                )
                .navigationTitle("Filter & Sort")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showFilterSheet = false }
                    }
                }
            }
        }
        .onChange(of: selectedGenres) { _, _ in Task { await load() } }
        .onChange(of: selectedYears) { _, _ in Task { await load() } }
        .onChange(of: watchedFilter) { _, _ in Task { await load() } }
        .onChange(of: favoritesOnly) { _, _ in Task { await load() } }
        .onChange(of: sortOption) { _, _ in Task { await load() } }
        .task { await load() }
        .task { await loadFilterOptions() }
    }

    // MARK: - Showcase

    private func showcaseSection(screenW: CGFloat, screenH: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)

            let heroURL = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920)
                ?? mediaRepo.imageURL(for: item, type: .primary, fillWidth: 1200)
            if let url = heroURL {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else { fallbackGradient }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                fallbackGradient.frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.5),
                .init(color: DT.Color.backgroundPrimary, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [DT.Color.backgroundPrimary.opacity(0.85), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: screenW * 0.65)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 28) {
                Text(item.name)
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 12)

                if !items.isEmpty {
                    Text("\(items.count) \(items.count == 1 ? "item" : "items")")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.65))
                }

                HStack(spacing: 20) {
                    Button {
                        guard let first = items.first else { return }
                        playbackRequest = PlaybackRequest(item: first, startTicks: first.userData?.playbackPositionTicks ?? 0)
                    } label: {
                        TVDetailButtonLabel(icon: "play.fill", text: "Play All", isPrimary: true)
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()

                    Button {
                        if statsRepo.isConfigured {
                            Task { try? await statsRepo.addToWatchlist(itemId: item.id) }
                        }
                    } label: {
                        TVDetailButtonLabel(icon: "bookmark", text: "Watchlist")
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()

                    Button {
                        showFilterSheet = true
                    } label: {
                        TVDetailButtonLabel(
                            icon: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                            text: "Filter & Sort"
                        )
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
        .focusSection()
    }

    private var fallbackGradient: some View {
        LinearGradient(
            colors: [DT.Color.accentDeep.opacity(0.4), DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Below fold

    @ViewBuilder
    private var belowFoldSection: some View {
        if !items.isEmpty {
            itemsSection.focusSection()
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("In this Collection")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(items) { ci in
                        Button { selectedItem = ci } label: {
                            TVCollectionItemCard(item: ci, imageURL: mediaRepo.imageURL(for: ci, type: .primary, fillWidth: 400))
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 20)
                .focusSection()
            }
            .scrollClipDisabled()
        }
        .padding(.bottom, 40)
    }

    // MARK: - Load

    private func load() async {
        guard let cred = credential, let header = authHeader else { return }
        fetchGeneration += 1
        let generation = fetchGeneration
        let fetched = try? await client.getLibraryItems(
            credential: cred, authHeader: header,
            libraryId: item.id, startIndex: 0, limit: 500,
            recursive: true, includeItemTypes: "Movie,Series",
            genres: Array(selectedGenres), years: Array(selectedYears),
            isPlayed: watchedFilter == .all ? nil : watchedFilter == .watched,
            isFavorite: favoritesOnly ? true : nil,
            sortBy: sortOption.sortBy, sortOrder: sortOption.sortOrder
        )
        guard generation == fetchGeneration else { return }
        items = fetched?.items ?? []
    }

    private func loadFilterOptions() async {
        guard let cred = credential, let header = authHeader else { return }
        let options = try? await client.getLibraryFilterOptions(
            credential: cred, authHeader: header, libraryId: item.id, includeItemTypes: "Movie,Series"
        )
        availableGenres = options?.genres ?? []
        availableYears = options?.years ?? []
    }
}

// MARK: - Filter & sort list (tvOS)

/// LibraryFilterList in LibraryView.swift is gated behind `#if !os(tvOS)`, so it isn't
/// available to this target — this mirrors its content/mechanism instead of duplicating
/// that conditional (out of scope for this file), reusing the shared LibraryWatchedFilter/
/// LibrarySortOption enums as instructed.
private struct TVLibraryFilterList: View {
    let availableGenres: [String]
    let availableYears: [Int]
    @Binding var selectedGenres: Set<String>
    @Binding var selectedYears: Set<Int>
    @Binding var watchedFilter: LibraryWatchedFilter
    @Binding var favoritesOnly: Bool
    @Binding var sortOption: LibrarySortOption

    var body: some View {
        List {
            Section("Sort By") {
                ForEach(LibrarySortOption.allCases) { option in
                    filterRow(option.rawValue, isSelected: sortOption == option) {
                        sortOption = option
                    }
                }
            }

            Section("Status") {
                Picker("Status", selection: $watchedFilter) {
                    ForEach(LibraryWatchedFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                Toggle("Favourites Only", isOn: $favoritesOnly)
            }

            if !availableGenres.isEmpty {
                Section("Genre") {
                    ForEach(availableGenres, id: \.self) { genre in
                        filterRow(genre, isSelected: selectedGenres.contains(genre)) {
                            toggle(genre, in: &selectedGenres)
                        }
                    }
                }
            }

            if !availableYears.isEmpty {
                Section("Year") {
                    ForEach(availableYears, id: \.self) { year in
                        filterRow(String(year), isSelected: selectedYears.contains(year)) {
                            toggle(year, in: &selectedYears)
                        }
                    }
                }
            }

            if !selectedGenres.isEmpty || !selectedYears.isEmpty || watchedFilter != .all || favoritesOnly {
                Section {
                    Button(role: .destructive) {
                        selectedGenres.removeAll()
                        selectedYears.removeAll()
                        watchedFilter = .all
                        favoritesOnly = false
                    } label: {
                        Text("Clear All Filters").frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }

    private func filterRow(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(DT.Color.accent)
                }
            }
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

// MARK: - Collection item card

private struct TVCollectionItemCard: View {
    let item: MediaItem
    let imageURL: URL?
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .fill(DT.Color.backgroundSecondary)
                }
            }
            .frame(width: 200, height: 300)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3))
            .shadow(color: isFocused ? DT.Color.accent.opacity(0.45) : .clear, radius: 12)
            .compositingGroup()
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)

            VStack(alignment: .leading, spacing: 2) {
                if let year = item.productionYear {
                    Text(String(year))
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                Text(item.name)
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
            }
            .frame(width: 200, height: 56, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Big library card for tvOS

private struct TVBigLibraryCard: View {
    let library: JellyfinLibrary
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .fill(LinearGradient(
                    colors: [
                        Color(hex: library.collectionType.accentHex).opacity(0.25),
                        DT.Color.backgroundSecondary,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.lg)
                        .stroke(isFocused ? DT.Color.accent : Color.white.opacity(0.06), lineWidth: isFocused ? 3 : 1)
                )

            VStack(spacing: 20) {
                Image(systemName: library.collectionType.systemIcon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(
                        isFocused
                            ? DT.Color.accent
                            : Color(hex: library.collectionType.accentHex)
                    )
                    .animation(DT.Animation.fast, value: isFocused)

                Text(library.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
            }
            .padding(32)
        }
        .frame(height: 225)
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 14)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)
        .contentShape(Rectangle())
    }
}
#endif
