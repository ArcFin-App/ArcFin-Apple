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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
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
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(.white.opacity(0.06), lineWidth: 1))
            .contextMenu {
                Button(role: .destructive) {
                    remove(item)
                } label: {
                    Label("Remove from Watchlist", systemImage: "bookmark.slash")
                }
            }

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            if let year = item.year {
                Text(year)
                    .font(.system(size: 10))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    private func remove(_ item: SeerrItem) {
        HapticManager.impact(.light)
        Task { try? await seerrRepo.removeFromWatchlist(item) }
    }
}
