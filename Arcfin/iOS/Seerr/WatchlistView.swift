// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct WatchlistView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model = WatchlistModel()
    @State private var openedItem: SeerrItem?

    private var isWide: Bool { horizontalSizeClass == .regular }

    private var columns: [GridItem] {
        if isWide {
            return [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 12)]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    var body: some View {
        Group {
            if model.isLoading && seerrRepo.watchlist.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if seerrRepo.watchlist.isEmpty, seerrRepo.authFailed {
                SeerrSignInFailedView()
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
                            Button { openedItem = item } label: {
                                WatchlistCard(item: item, showsRemoveButton: true) {
                                    model.remove(item, seerrRepo: seerrRepo)
                                }
                            }
                            .buttonStyle(.plain)
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
        .alert("Watchlist", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
        .refreshable { await seerrRepo.loadWatchlist(refresh: true) }
        // The title's page, as from Discover, where it can be requested or played.
        .navigationDestination(item: $openedItem) { item in
            SeerrItemDetailView(item: item)
        }
    }
}
