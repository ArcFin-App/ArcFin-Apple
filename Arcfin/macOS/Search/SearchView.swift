// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

struct SearchView: View {
    @Binding var query: String

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var model = SearchModel()
    @State private var requestingSeerrItem: SeerrItem?
    @State private var openedItem: MediaItem?
    /// Channels and programmes, between the library results and Discover.
    @State private var liveTV = LiveTVModel()
    @AppStorage(RecentSearches.key) private var recentSearchesData = Data()
    @AppStorage("saveSearchHistory") private var saveSearchHistory = true
    /// Off brings back the plain Library and Discover poster grids.
    @AppStorage("modernSearch") private var modernSearch = true

    private let topResultHeight: CGFloat = 300
    private let posterWidth: CGFloat = 150
    private let landscapeWidth: CGFloat = 300
    private let shelfSpacing: CGFloat = 16
    private let discoverPosterWidth: CGFloat = 80
    private let classicColumns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    private var recentSearches: [String] { RecentSearches.decode(recentSearchesData) }

    private var searchesLiveTV: Bool {
        ProfileRules.shared.canWatchLiveTV && mediaRepo.libraries.contains { $0.collectionType == .livetv }
    }

    private var foundNothing: Bool {
        model.foundNothing && !liveTV.isSearching && !liveTV.hasSearchResults
    }

    private func saveRecentSearch() {
        guard saveSearchHistory else { return }
        recentSearchesData = RecentSearches.adding(query, to: recentSearchesData)
    }

    var body: some View {
        Group {
            if query.isEmpty, !recentSearches.isEmpty {
                RecentSearchesList(terms: recentSearches, clear: { recentSearchesData = Data() }) { term, label in
                    Button { query = term } label: { label }
                        .buttonStyle(.plain)
                }
            } else if query.isEmpty || foundNothing {
                SearchEmptyState(query: query)
            } else if !modernSearch {
                classicResults
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DT.Spacing.xl) {
                        if let top = model.jellyfinResults.first {
                            Button { openedItem = top } label: {
                                SearchTopResultCard(item: top, height: topResultHeight)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
                            .padding(.horizontal, DT.Spacing.pagePad)
                        } else if model.isSearchingLibrary {
                            SearchingRow(text: "Searching your library…")
                        }
                        ForEach(model.libraryGroups, id: \.title) { group in
                            libraryShelf(group)
                        }
                        if liveTV.hasSearchResults {
                            LiveTVSearchSection(model: liveTV)
                                .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
                        }
                        if seerrRepo.isConfigured && (model.isSearchingDiscover || !model.seerrResults.isEmpty) {
                            SearchDiscoverSection(items: model.discoverResults(in: mediaRepo),
                                                  isSearching: model.isSearchingDiscover,
                                                  posterWidth: discoverPosterWidth) { item in
                                Button {
                                    saveRecentSearch()
                                    requestingSeerrItem = item
                                } label: { SearchDiscoverRow(item: item, posterWidth: discoverPosterWidth) }
                                .buttonStyle(PressableButtonStyle())
                            }
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .animation(DT.Animation.fast, value: model.jellyfinResults)
                    .animation(DT.Animation.fast, value: model.seerrResults)
                }
            }
        }
        .screenBackground()
        .onChange(of: query) { _, newValue in
            model.search(newValue, authManager: authManager, mediaRepo: mediaRepo, seerrRepo: seerrRepo)
            liveTV.searchQuery = searchesLiveTV ? newValue : ""
            liveTV.search(authManager: authManager)
        }
        .liveTVPresentations(model: liveTV)
        // A NavigationLink(value:) can't always find the stack's destination on the Mac.
        .navigationDestination(item: $openedItem) { item in
            MediaDetailView(item: item)
        }
        .sheet(item: $requestingSeerrItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingSeerrItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private func libraryShelf(_ group: SearchModel.LibraryGroup) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            SearchSectionHeader(title: group.title, count: group.items.count)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: shelfSpacing) {
                    ForEach(group.items) { item in
                        Button { openedItem = item } label: {
                            SearchShelfCard(item: item, isLandscape: group.isLandscape,
                                            posterWidth: posterWidth, landscapeWidth: landscapeWidth)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
            .shelfScrollButtons()
        }
    }

    // MARK: - Classic layout

    private var classicResults: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DT.Spacing.xl) {
                if !model.jellyfinResults.isEmpty {
                    VStack(alignment: .leading, spacing: DT.Spacing.sectionGap) {
                        Text("Library")
                            .font(DT.Font.cardTitle)
                            .foregroundStyle(DT.Color.textPrimary)
                        LazyVGrid(columns: classicColumns, spacing: 16) {
                            ForEach(model.jellyfinResults) { item in
                                Button { openedItem = item } label: {
                                    SearchResultCard(title: item.name, subtitle: item.productionYear.map { String($0) },
                                                     imageURL: SearchText.posterImageURL(for: item, in: mediaRepo))
                                }
                                .buttonStyle(PressableButtonStyle())
                                .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
                            }
                        }
                    }
                } else if model.isSearchingLibrary {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if liveTV.hasSearchResults {
                    LiveTVSearchSection(model: liveTV)
                        .padding(.horizontal, -DT.Spacing.pagePad)
                }
                if seerrRepo.isConfigured && !model.seerrResults.isEmpty {
                    SearchClassicDiscover {
                        LazyVGrid(columns: classicColumns, spacing: 16) {
                            ForEach(model.seerrResults) { item in
                                Button {
                                    saveRecentSearch()
                                    requestingSeerrItem = item
                                } label: {
                                    SearchResultCard(title: item.title, subtitle: item.year, imageURL: item.posterURL)
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }
}
