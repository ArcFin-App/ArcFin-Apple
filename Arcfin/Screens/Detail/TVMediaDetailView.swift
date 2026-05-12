#if os(tvOS)
import SwiftUI
import JellyfinAPI
import JellyseerrAPI
import AuthCore

struct TVMediaDetailView: View {
    let item: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(JellyseerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    @State private var detail: MediaItemDetail?
    @State private var seasons: [MediaItem] = []
    @State private var selectedSeason: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var trailers: [MediaItem] = []
    @State private var similarItems: [MediaItem] = []
    @State private var seerrRelatedItems: [SeerrItem] = []
    @State private var isLoading = true
    @State private var showFullDescription = false

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
        .task { await load() }
        .onChange(of: selectedSeason) { _, season in
            guard let season, let seriesId = seasonSeriesId,
                  let cred = credential, let header = authHeader else { return }
            Task {
                episodes = (try? await client.getEpisodes(
                    credential: cred, authHeader: header,
                    seriesId: seriesId, seasonId: season.id)) ?? []
            }
        }
        .fullScreenCover(isPresented: $showFullDescription) {
            fullDescriptionCover
        }
    }

    // MARK: - Showcase (above fold)

    private func showcaseSection(screenW: CGFloat, screenH: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        fallbackGradient
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            } else {
                fallbackGradient.frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.5),
                    .init(color: DT.Color.backgroundPrimary, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [DT.Color.backgroundPrimary.opacity(0.85), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: screenW * 0.65)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 28) {
                logoBlock
                metaRow
                threeColumnLayout
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
        .focusSection()
    }

    @ViewBuilder
    private var logoBlock: some View {
        AsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
            if case .success(let img) = phase {
                img.resizable().scaledToFit()
                    .frame(maxWidth: 360, maxHeight: 108)
                    .shadow(color: .black.opacity(0.7), radius: 14)
            } else {
                Text(item.name)
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 12)
            }
        }
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            if let year = item.productionYear {
                Text(String(year)).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
            }
            if let rating = detail?.officialRating, !rating.isEmpty {
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text(rating)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.3), lineWidth: 1))
            }
            if let mins = detail?.runtimeMinutes {
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text("\(mins)m").font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
            }
            if let rating = item.communityRating {
                Text("·").foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(DT.Color.accent)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(DT.Color.accent)
                }
            }
            if detail?.is4K == true { qualityBadge("4K", color: DT.Color.accent) }
            if detail?.isHDR == true { qualityBadge("HDR", color: Color(hex: "F59E0B")) }
        }
    }

    private var threeColumnLayout: some View {
        HStack(alignment: .top, spacing: 40) {
            actionColumn.frame(width: 260)
            descriptionColumn
            infoColumn.frame(width: 260)
        }
    }

    private var actionColumn: some View {
        VStack(spacing: 14) {
            Button {} label: {
                TVDetailButtonLabel(icon: "play.fill", text: "Play", isPrimary: true)
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()

            Button {} label: {
                TVDetailButtonLabel(icon: "bookmark", text: "Watchlist")
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
        }
    }

    @ViewBuilder
    private var descriptionColumn: some View {
        let overview = detail?.item.overview ?? item.overview
        if let overview, !overview.isEmpty {
            Button { showFullDescription = true } label: {
                TVDescriptionLabel(text: overview)
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
        }
    }

    @ViewBuilder
    private var infoColumn: some View {
        if let d = detail {
            VStack(alignment: .leading, spacing: 18) {
                if !d.directors.isEmpty {
                    infoRow(
                        label: "Director",
                        value: d.directors.prefix(2).map { $0.name }.joined(separator: ", ")
                    )
                }
                if !d.cast.isEmpty {
                    infoRow(
                        label: "Starring",
                        value: d.cast.prefix(3).map { $0.name }.joined(separator: ", ")
                    )
                }
                if !d.genres.isEmpty {
                    infoRow(
                        label: "Genre",
                        value: d.genres.prefix(2).joined(separator: ", ")
                    )
                }
                if let studio = d.studios.first {
                    infoRow(label: "Studio", value: studio)
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DT.Color.textSecondary)
            Text(value)
                .font(.system(size: 20))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
        }
    }

    // MARK: - Below fold

    @ViewBuilder
    private var belowFoldSection: some View {
        if !seasons.isEmpty { seriesSection.focusSection() }
        if !trailers.isEmpty { trailersSection.focusSection() }
        if !seerrRelatedItems.isEmpty {
            seerrRelatedSection.focusSection()
        } else if !similarItems.isEmpty {
            similarSection.focusSection()
        }
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("Episodes")
                Spacer()
                Menu {
                    ForEach(seasons) { season in
                        Button(season.name) { selectedSeason = season }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedSeason?.name ?? "Season")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(DT.Color.accent)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18))
                            .foregroundStyle(DT.Color.accent)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(DT.Color.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: DT.Radius.pill)
            }
            .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(episodes) { ep in
                        TVEpisodeCard(ep: ep)
                    }
                }
                .padding(.horizontal, 80)
                .focusSection()
            }
        }
        .padding(.bottom, 56)
    }

    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Trailers").padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(trailers) { trailer in
                        NavigationLink(value: trailer) {
                            PosterCard(
                                title: trailer.name,
                                imageURL: mediaRepo.imageURL(for: trailer)
                            )
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, 80)
                .focusSection()
            }
        }
        .padding(.bottom, 56)
    }

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("More Like This").padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(similarItems) { sim in
                        NavigationLink(value: sim) {
                            PosterCard(
                                title: sim.name,
                                subtitle: sim.productionYear.map { String($0) },
                                imageURL: mediaRepo.tvImageURL(for: sim, fillWidth: 640)
                            )
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, 80)
                .focusSection()
            }
        }
        .padding(.bottom, 56)
    }

    private var seerrRelatedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Recommended").padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(seerrRelatedItems) { sim in
                        PosterCard(
                            title: sim.title,
                            subtitle: sim.year,
                            imageURL: sim.backdropURL ?? sim.posterURL
                        )
                    }
                }
                .padding(.horizontal, 80)
            }
        }
        .padding(.bottom, 56)
    }

    // MARK: - Full description cover

    private var fullDescriptionCover: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(item.name)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.white)
                    if let overview = detail?.item.overview ?? item.overview {
                        Text(overview)
                            .font(.system(size: 26))
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineSpacing(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Close") { showFullDescription = false }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .padding(.top, 8)
                }
                .padding(80)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let cred = credential, let header = authHeader else { return }

        let fetchedDetail = try? await client.getItemDetail(credential: cred, authHeader: header, itemId: item.id)
        detail = fetchedDetail

        if let fetchedDetail, let mediaType = seerrMediaType(for: fetchedDetail.item),
           let tmdbId = fetchedDetail.item.tmdbId {
            seerrRelatedItems = await seerrRepo.relatedMedia(mediaType: mediaType, mediaId: tmdbId)
        }
        if seerrRelatedItems.isEmpty {
            similarItems = (try? await client.getSimilarItems(credential: cred, authHeader: header, itemId: item.id)) ?? []
        }

        Task {
            let fetched = (try? await client.getTrailers(
                credential: cred, authHeader: header, itemId: item.id, limit: 6)) ?? []
            await MainActor.run { trailers = fetched }
        }

        if let seriesId = seasonSeriesId {
            seasons = (try? await client.getSeasons(credential: cred, authHeader: header, seriesId: seriesId)) ?? []
            if let first = seasons.first {
                selectedSeason = selectedSeasonForCurrentItem(from: seasons) ?? first
                episodes = (try? await client.getEpisodes(
                    credential: cred, authHeader: header,
                    seriesId: seriesId, seasonId: selectedSeason?.id ?? first.id)) ?? []
            }
        }
    }

    // MARK: - Helpers

    private var fallbackGradient: some View {
        LinearGradient(
            colors: [DT.Color.accentDeep.opacity(0.4), DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private func qualityBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(DT.Color.textPrimary)
    }

    private func seerrMediaType(for item: MediaItem) -> RequestMediaType? {
        switch item.type {
        case .movie: .movie
        case .series, .season, .episode: .tv
        default: nil
        }
    }

    private var seasonSeriesId: String? {
        switch item.type {
        case .series: item.id
        case .season, .episode: item.seriesId
        default: nil
        }
    }

    private func selectedSeasonForCurrentItem(from seasons: [MediaItem]) -> MediaItem? {
        if item.type == .episode, let seasonNumber = item.parentIndexNumber {
            return seasons.first { $0.indexNumber == seasonNumber }
        }
        if item.type == .season {
            return seasons.first { $0.id == item.id } ?? seasons.first
        }
        return seasons.first
    }
}

// MARK: - Episode card

private struct TVEpisodeCard: View {
    let ep: MediaItem
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: mediaRepo.imageURL(for: ep, type: .primary, fillWidth: 400)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: DT.Radius.card).fill(DT.Color.backgroundSecondary)
                }
            }
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3)
            )
            .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 10)
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)

            VStack(alignment: .leading, spacing: 3) {
                if let epNum = ep.indexNumber {
                    Text("Ep \(epNum)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DT.Color.accent)
                }
                Text(ep.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .lineLimit(1)
                    .animation(DT.Animation.fast, value: isFocused)
            }
            .frame(width: 320, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        TVMediaDetailView(item: MediaItem(
            id: "1", name: "Severance", type: .series,
            backdropImageTags: [], productionYear: 2022, communityRating: 8.7
        ))
        .environment(MediaRepository())
        .environment(AuthManager())
        .environment(JellyseerrRepository())
    }
}
#endif
