// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct WatchlistView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @State private var model = WatchlistModel()

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 20)]
    }

    var body: some View {
        Group {
            if model.isLoading && seerrRepo.watchlist.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if seerrRepo.watchlist.isEmpty {
                ContentUnavailableView(
                    "Watchlist Empty",
                    systemImage: "bookmark",
                    description: Text("Titles you add to your watchlist will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(seerrRepo.watchlist) { item in
                            NavigationLink(value: item) {
                                WatchlistCard(item: item, showsRemoveButton: false) {
                                    model.remove(item, seerrRepo: seerrRepo)
                                }
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                        }
                    }
                    .padding(DT.Spacing.pagePad)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Watchlist")
        .arcfinNavTitleLarge("Watchlist")
        .task { await model.load(seerrRepo: seerrRepo) }
        .refreshable { await seerrRepo.loadWatchlist() }
    }
}
