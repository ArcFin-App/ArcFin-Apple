import SwiftUI
import SeerrAPI

struct WatchlistView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @State private var isLoading = false
    @State private var requestingItem: SeerrItem? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

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
                            .buttonStyle(.plain)
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
            ZStack {
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
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(.white.opacity(0.06), lineWidth: 1))

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
}
