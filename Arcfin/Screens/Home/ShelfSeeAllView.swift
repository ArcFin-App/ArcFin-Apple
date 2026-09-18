import SwiftUI
import JellyfinAPI

struct ShelfSeeAllView: View {
    let title: String
    let items: [MediaItem]
    var isLandscape: Bool = false

    @Environment(MediaRepository.self) private var mediaRepo
    @State private var selectedItem: MediaItem?

    private var columns: [GridItem] {
        let count = isLandscape ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    Button { selectedItem = item } label: {
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
        // Self-contained rather than relying on an ancestor's navigationDestination(for:) —
        // a NavigationLink pushed from a view that itself was pushed via
        // navigationDestination(item:) could silently fail to navigate until popping back.
        .navigationDestination(item: $selectedItem) { item in
            MediaDetailView(item: item)
        }
    }

    private func imageURL(for item: MediaItem) -> URL? {
        guard isLandscape else { return mediaRepo.imageURL(for: item) }
        if item.type == .episode {
            return mediaRepo.imageURL(for: item, type: .primary, fillWidth: 500)
        }
        return mediaRepo.imageURL(for: item, type: .thumb, fillWidth: 500)
            ?? mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 500)
    }

    private func gridCard(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let url = imageURL(for: item) {
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
            .aspectRatio(isLandscape ? 16 / 9 : 2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(.white.opacity(0.06), lineWidth: 1))

            Text(cardTitle(item))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            if let subtitle = cardSubtitle(item) {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func cardTitle(_ item: MediaItem) -> String {
        item.type == .episode ? (item.seriesName ?? item.name) : item.name
    }

    private func cardSubtitle(_ item: MediaItem) -> String? {
        guard item.type == .episode else {
            return item.productionYear.map { String($0) }
        }
        let s = item.parentIndexNumber.map { "S\($0)" }
        let e = item.indexNumber.map { "E\($0)" }
        let code = [s, e].compactMap { $0 }.joined()
        return [code.isEmpty ? nil : code, item.name].compactMap { $0 }.joined(separator: " · ")
    }
}
