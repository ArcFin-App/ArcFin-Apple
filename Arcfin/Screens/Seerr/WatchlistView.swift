// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct WatchlistView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @State private var isLoading = false
    @State private var requestingItem: SeerrItem? = nil

    private var columns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12)]
        #elseif os(tvOS)
        [GridItem(.adaptive(minimum: 260), spacing: 20)]
        #else
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        #endif
    }

    var body: some View {
        Group {
            if isLoading && seerrRepo.watchlist.isEmpty {
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
                            Button { requestingItem = item } label: {
                                watchlistCard(item)
                            }
#if os(tvOS)
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
#else
                            .buttonStyle(.plain)
#endif
                        }
                    }
                    .padding(DT.Spacing.pagePad)
                }
            }
        }
        .background(DT.Color.backgroundPrimary)
        .navigationTitle("Watchlist")
        .arcfinNavTitleLarge("Watchlist")
        .task {
            isLoading = true
            await seerrRepo.loadWatchlist()
            isLoading = false
        }
        .refreshable { await seerrRepo.loadWatchlist() }
        .sheet(item: $requestingItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingItem)
                // presentationDetents is an iPhone/iPad card-sheet concept — see the same fix
                // on the player and Search sheets.
                #if !os(tvOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                #endif
        }
    }

    private func watchlistCard(_ item: SeerrItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let url = item.posterURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: DT.Color.backgroundSecondary
                        }
                    }
                    .clipped()
                } else {
                    DT.Color.backgroundSecondary
                }

                // A Button nested inside this card's own outer Button is undefined on touch
                // platforms and genuinely broken on tvOS, where interaction is focus-based —
                // two independently-focusable targets in the same region confuses the focus
                // engine. tvOS relies on the contextMenu below instead, already present.
                #if !os(tvOS)
                Button { remove(item) } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.5))
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                #endif
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(.white.opacity(0.06), lineWidth: 1))
            .tvFocusRing(cornerRadius: DT.Radius.card)
            .contextMenu(menuItems: {
                Button(role: .destructive) {
                    remove(item)
                } label: {
                    Label("Remove from Watchlist", systemImage: "bookmark.slash")
                }
            }, preview: {
                watchlistPreview(item)
            })

            Text(item.title)
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            if let year = item.year {
                Text(year)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    private func watchlistPreview(_ item: SeerrItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = item.posterURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: DT.Color.backgroundSecondary
                        }
                    }
                } else {
                    DT.Color.backgroundSecondary
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

    private func remove(_ item: SeerrItem) {
        HapticManager.impact(.light)
        Task { try? await seerrRepo.removeFromWatchlist(item) }
    }
}
