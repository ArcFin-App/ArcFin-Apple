import SwiftUI
import JellyfinAPI

struct ShelfSeeAllView: View {
    let title: String
    let items: [MediaItem]

    @Environment(MediaRepository.self) private var mediaRepo

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        gridCard(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DT.Spacing.pagePad)
        }
        .background(DT.Color.backgroundPrimary)
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func gridCard(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let url = mediaRepo.imageURL(for: item) {
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

            Text(item.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            if let year = item.productionYear {
                Text(String(year))
                    .font(.system(size: 10))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }
}
