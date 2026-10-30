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
    @AppStorage(RecentSearches.key) private var recentSearchesData = Data()
    @AppStorage("saveSearchHistory") private var saveSearchHistory = true
    /// Off brings back the plain Library and Discover poster grids.
    @AppStorage("modernSearch") private var modernSearch = true

    private let topResultHeight: CGFloat = 420
    private let posterWidth: CGFloat = 220
    private let landscapeWidth: CGFloat = 400
    private let shelfSpacing: CGFloat = 40
    private let discoverPosterWidth: CGFloat = 120
    private let classicColumns = [GridItem(.adaptive(minimum: 220), spacing: 40)]

    private var recentSearches: [String] { RecentSearches.decode(recentSearchesData) }

    private func saveRecentSearch() {
        guard saveSearchHistory else { return }
        recentSearchesData = RecentSearches.adding(query, to: recentSearchesData)
    }

    var body: some View {
        Group {
            if query.isEmpty, !recentSearches.isEmpty {
                RecentSearchesList(terms: recentSearches, clear: { recentSearchesData = Data() }) { term, label in
                    Button { query = term } label: { label }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .tvFocusRing(cornerRadius: DT.Radius.md)
                }
            } else if query.isEmpty || model.foundNothing {
                SearchEmptyState(query: query)
            } else if !modernSearch {
                classicResults
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DT.Spacing.xl) {
                        if let top = model.jellyfinResults.first {
                            NavigationLink(value: top) {
                                SearchTopResultCard(item: top, height: topResultHeight)
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
                            .padding(.horizontal, DT.Spacing.pagePad)
                        } else if model.isSearchingLibrary {
                            SearchingRow(text: "Searching your library…")
                        }
                        ForEach(model.libraryGroups, id: \.title) { group in
                            libraryShelf(group)
                        }
                        if seerrRepo.isConfigured && (model.isSearchingDiscover || !model.seerrResults.isEmpty) {
                            SearchDiscoverSection(items: model.discoverResults(in: mediaRepo),
                                                  isSearching: model.isSearchingDiscover,
                                                  posterWidth: discoverPosterWidth) { item in
                                NavigationLink(value: item) { SearchDiscoverRow(item: item, posterWidth: discoverPosterWidth) }
                                    .buttonStyle(TVCardButtonStyle())
                                    .focusEffectDisabled()
                                    .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
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
        }
    }

    private func libraryShelf(_ group: SearchModel.LibraryGroup) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            SearchSectionHeader(title: group.title, count: group.items.count)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: shelfSpacing) {
                    ForEach(group.items) { item in
                        NavigationLink(value: item) {
                            SearchShelfCard(item: item, isLandscape: group.isLandscape,
                                            posterWidth: posterWidth, landscapeWidth: landscapeWidth)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.vertical, 30)
            }
            .shelfScrollButtons()
            .scrollClipDisabled()
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
                                NavigationLink(value: item) {
                                    SearchResultCard(title: item.name, subtitle: item.productionYear.map { String($0) },
                                                     imageURL: SearchText.posterImageURL(for: item, in: mediaRepo))
                                }
                                .buttonStyle(TVCardButtonStyle())
                                .focusEffectDisabled()
                                .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
                            }
                        }
                    }
                } else if model.isSearchingLibrary {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if seerrRepo.isConfigured && !model.seerrResults.isEmpty {
                    SearchClassicDiscover {
                        LazyVGrid(columns: classicColumns, spacing: 16) {
                            ForEach(model.seerrResults) { item in
                                NavigationLink(value: item) {
                                    SearchResultCard(title: item.title, subtitle: item.year, imageURL: item.posterURL)
                                }
                                .buttonStyle(TVCardButtonStyle())
                                .focusEffectDisabled()
                                .simultaneousGesture(TapGesture().onEnded { saveRecentSearch() })
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
