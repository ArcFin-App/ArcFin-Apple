import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore

struct MediaDetailView: View {
    let item: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var detail: MediaItemDetail?
    @State private var similarItems: [MediaItem] = []
    @State private var seerrRelatedItems: [SeerrItem] = []
    @State private var seriesItem: MediaItem?
    @State private var seasons: [MediaItem] = []
    @State private var selectedSeason: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var selectedEpisode: MediaItem?
    @State private var loadedSeasonId: String?
    @State private var trailers: [MediaItem] = []
    @State private var isLoading = true
    @State private var requestingSeerrItem: SeerrItem?

    private let client = JellyfinMediaClient()

    private var credential: ServerCredential? { authManager.state.credential }

    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroSection
                titleBlock
                if isLoading { loadingContent }
                else { detailContent }
                Spacer().frame(height: DT.Size.tabBarHeight + 24)
            }
#if os(tvOS)
            .focusSection()
#endif
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
        .navigationDestination(item: $selectedEpisode) { ep in
            MediaDetailView(item: ep)
        }
        .sheet(item: $requestingSeerrItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingSeerrItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .task { await load() }
        .onChange(of: selectedSeason) { _, season in
            guard let season, season.id != loadedSeasonId,
                  let seriesId = seasonSeriesId,
                  let cred = credential, let header = authHeader else { return }
            Task {
                loadedSeasonId = season.id
                episodes = (try? await client.getEpisodes(credential: cred, authHeader: header,
                                                          seriesId: seriesId, seasonId: season.id)) ?? []
            }
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let cred = credential, let header = authHeader else { return }

        async let detailTask = client.getItemDetail(credential: cred, authHeader: header, itemId: item.id)
        trailers = []
        
        let fetchedDetail = try? await detailTask
        detail = fetchedDetail

        if let fetchedDetail, let mediaType = seerrMediaType(for: fetchedDetail.item),
           let tmdbId = fetchedDetail.item.tmdbId {
            seerrRelatedItems = await seerrRepo.relatedMedia(mediaType: mediaType, mediaId: tmdbId)
        }
        if seerrRelatedItems.isEmpty {
            similarItems = (try? await client.getSimilarItems(credential: cred, authHeader: header, itemId: item.id)) ?? []
        } else {
            similarItems = []
        }

        Task {
            let fetchedTrailers = (try? await client.getTrailers(
                credential: cred,
                authHeader: header,
                itemId: item.id,
                limit: 6
            )) ?? []
            await MainActor.run {
                trailers = fetchedTrailers
            }
        }

        if let seriesId = seasonSeriesId {
            seasons = (try? await client.getSeasons(credential: cred, authHeader: header, seriesId: seriesId)) ?? []
            if let first = seasons.first {
                var target = selectedSeasonForCurrentItem(from: seasons) ?? first
                // For a series entry point, ask the server which episode is next
                if item.type == .series,
                   let nextEp = try? await client.getNextEpisode(credential: cred, authHeader: header, seriesId: seriesId),
                   let seasonNum = nextEp.parentIndexNumber,
                   let matched = seasons.first(where: { $0.indexNumber == seasonNum }) {
                    target = matched
                }
                selectedSeason = target
                loadedSeasonId = target.id
                episodes = (try? await client.getEpisodes(credential: cred, authHeader: header,
                                                          seriesId: seriesId, seasonId: target.id)) ?? []
            }
        }

        if item.type == .episode, let seriesId = item.seriesId {
            seriesItem = (try? await client.getItemDetail(credential: cred, authHeader: header, itemId: seriesId))?.item
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            if let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 900) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    default: fallbackHero
                    }
                }
            } else { fallbackHero }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.6),
                    .init(color: DT.Color.backgroundPrimary, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: 260)
        .clipped()
    }

    private var fallbackHero: some View {
        LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Title block

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            // Portrait poster
            if let url = mediaRepo.imageURL(for: item, type: .primary, fillWidth: 200) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: RoundedRectangle(cornerRadius: 10).fill(DT.Color.backgroundSecondary)
                    }
                }
                .frame(width: 90, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DT.Color.backgroundSecondary)
                    .frame(width: 90, height: 132)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
                    .lineLimit(3)

                metaRow
                qualityRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, -50)
        .padding(.bottom, DT.Spacing.md)
    }

    private var metaRow: some View {
        HStack(spacing: 6) {
            if let year = item.productionYear {
                Text(String(year))
                    .font(.system(size: 12))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = detail?.officialRating, !rating.isEmpty {
                Text("·").foregroundStyle(.white.opacity(0.2)).font(.system(size: 12))
                Text(rating)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(DT.Color.textSecondary.opacity(0.35), lineWidth: 1))
            }
            if let mins = detail?.runtimeMinutes {
                Text("·").foregroundStyle(.white.opacity(0.2)).font(.system(size: 12))
                Text("\(mins)m")
                    .font(.system(size: 12))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = item.communityRating {
                Text("·").foregroundStyle(.white.opacity(0.2)).font(.system(size: 12))
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(DT.Color.accent)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DT.Color.accent)
                }
            }
        }
    }

    private var qualityRow: some View {
        HStack(spacing: 6) {
            if detail?.is4K == true { qualityBadge("4K", color: Color(hex: "06B6D4")) }
            if detail?.isHDR == true { qualityBadge("HDR", color: Color(hex: "F59E0B")) }
            if let codec = detail?.videoStream?.codec?.uppercased() {
                qualityBadge(codec, color: Color(hex: "8B5CF6"))
            }
        }
    }

    private func qualityBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Play button

    private var playButton: some View {
#if os(tvOS)
        Button {} label: { TVPlayButtonLabel() }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.md)
#else
        Button {} label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 14))
                Text("Play").font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(LinearGradient(
                colors: [DT.Color.accentDeep, DT.Color.accent],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            .shadow(color: DT.Color.accent.opacity(0.35), radius: 12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
#endif
    }

    // MARK: - Loading skeleton

    private var loadingContent: some View {
        VStack(spacing: DT.Spacing.md) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 14)
                    .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.top, DT.Spacing.md)
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        playButton

        // Genres
        if let d = detail, !d.genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(d.genres, id: \.self) { genre in
                        Text(genre)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DT.Color.textSecondary)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(.white.opacity(0.05))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
            .padding(.bottom, DT.Spacing.md)
#if os(tvOS)
            .focusSection()
#endif
        }

        // Overview
        if let overview = detail?.item.overview ?? item.overview, !overview.isEmpty {
            overviewSection(overview)
        }

        // Cast
        if let d = detail, !d.cast.isEmpty { castSection(d) }

        // Crew
        if let d = detail, (!d.directors.isEmpty || !d.writers.isEmpty) { crewSection(d) }

        if let seriesItem, item.type == .episode {
            seriesLinkSection(seriesItem)
        }

        // Series: seasons + episodes
        if !seasons.isEmpty { seriesSection }

        // Trailers
        if !trailers.isEmpty { trailersSection }

        // Similar / recommended
        if !seerrRelatedItems.isEmpty {
            seerrRelatedSection
        } else if !similarItems.isEmpty {
            similarSection
        }
    }

    // MARK: - Overview

    private func overviewSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Overview")
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(DT.Color.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Cast

    private func castSection(_ d: MediaItemDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Cast").padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(d.cast) { person in
                        VStack(spacing: 6) {
                            if let tag = person.primaryImageTag,
                               let url = mediaRepo.personImageURL(personId: person.id, tag: tag, fillWidth: 120) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: personPlaceholder
                                    }
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
                            } else {
                                personPlaceholder
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            }

                            Text(person.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            if let role = person.role, !role.isEmpty {
                                Text(role)
                                    .font(.system(size: 9))
                                    .foregroundStyle(DT.Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 70, alignment: .top)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
#if os(tvOS)
        .focusSection()
#endif
    }

    private var personPlaceholder: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .font(.system(size: 22))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
    }

    // MARK: - Crew

    private func crewSection(_ d: MediaItemDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !d.directors.isEmpty {
                crewRow(label: "Director", people: d.directors)
            }
            if !d.writers.isEmpty {
                crewRow(label: "Writer", people: d.writers.prefix(3).map { $0 })
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    private func crewRow(label: String, people: [MediaPerson]) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DT.Color.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(people.map { $0.name }.joined(separator: ", "))
                .font(.system(size: 12))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Series seasons + episodes

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Menu {
                    ForEach(seasons) { season in
                        Button(season.name) { selectedSeason = season }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(selectedSeason?.name ?? "Season")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(DT.Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
#if os(tvOS)
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: DT.Radius.pill)
#else
                .buttonStyle(.plain)
                .fixedSize()
#endif

                Spacer()

                Text("Episodes")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            VStack(spacing: 8) {
                ForEach(episodes) { ep in
                    episodeRow(ep)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .padding(.bottom, DT.Spacing.md)
#if os(tvOS)
        .focusSection()
#endif
    }

    private func seriesLinkSection(_ series: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Series")
            NavigationLink(value: series) {
                HStack(spacing: 10) {
                    Image(systemName: "tv")
                        .font(.system(size: 14))
                        .foregroundStyle(DT.Color.accent)
                    Text(series.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.05), lineWidth: 1))
            }
#if os(tvOS)
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .tvFocusRing(cornerRadius: 10)
#else
            .buttonStyle(.plain)
#endif
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    private func episodeRow(_ ep: MediaItem) -> some View {
        let isWatched = ep.userData?.played == true
        let pct = ep.userData?.playedPercentage ?? 0

        return Button { selectedEpisode = ep } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        if let url = mediaRepo.episodeThumbnailURL(for: ep) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: episodeThumbPlaceholder
                                }
                            }
                        } else {
                            episodeThumbPlaceholder
                        }

                        if isWatched {
                            Color.black.opacity(0.45)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(hex: "10b981"))
                        } else if pct > 0 {
                            VStack(spacing: 0) {
                                Spacer()
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(.white.opacity(0.25)).frame(height: 3)
                                        Rectangle()
                                            .fill(DT.Color.accent)
                                            .frame(width: geo.size.width * CGFloat(min(pct / 100.0, 1.0)), height: 3)
                                    }
                                }
                                .frame(height: 3)
                            }
                        }
                    }
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 4) {
                        if let epNum = ep.indexNumber {
                            Text("E\(epNum)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DT.Color.accent)
                        }
                        Text(ep.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let overview = ep.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(3)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                HapticManager.impact(.light)
                markEpisodeWatched(ep, watched: !isWatched)
            } label: {
                Label(isWatched ? "Mark as Unwatched" : "Mark as Watched",
                      systemImage: isWatched ? "eye.slash" : "checkmark")
            }
        }
    }

    private var episodeThumbPlaceholder: some View {
        Rectangle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(
                Image(systemName: "play.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.3))
            )
    }

    private func markEpisodeWatched(_ ep: MediaItem, watched: Bool) {
        guard let cred = credential, let header = authHeader else { return }
        Task {
            try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
            if let idx = episodes.firstIndex(where: { $0.id == ep.id }) {
                var updated = episodes[idx]
                let old = updated.userData ?? UserData()
                updated.userData = UserData(
                    playbackPositionTicks: watched ? 0 : old.playbackPositionTicks,
                    playCount: watched ? old.playCount + 1 : max(0, old.playCount - 1),
                    isFavorite: old.isFavorite,
                    played: watched,
                    playedPercentage: watched ? nil : old.playedPercentage
                )
                episodes[idx] = updated
            }
        }
    }

    // MARK: - Similar items

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("More Like This").padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(similarItems) { sim in
                        NavigationLink(value: sim) {
                            PosterCard(
                                title: sim.name,
                                subtitle: sim.productionYear.map { String($0) },
                                imageURL: mediaRepo.imageURL(for: sim)
                            )
                        }
#if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
#else
                        .buttonStyle(.plain)
#endif
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#if os(tvOS)
                .focusSection()
#endif
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    private var seerrRelatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Recommended").padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(seerrRelatedItems) { sim in
                        Button { requestingSeerrItem = sim } label: {
                            PosterCard(
                                title: sim.title,
                                subtitle: sim.year,
                                imageURL: sim.posterURL
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Trailers").padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trailers) { trailer in
                        NavigationLink(value: trailer) {
                            PosterCard(
                                title: trailer.name,
                                subtitle: nil,
                                imageURL: mediaRepo.imageURL(for: trailer)
                            )
                        }
#if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
#else
                        .buttonStyle(.plain)
#endif
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#if os(tvOS)
                .focusSection()
#endif
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Helpers

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
            return seasons.first(where: { $0.indexNumber == seasonNumber })
        }
        if item.type == .season {
            return seasons.first(where: { $0.id == item.id }) ?? seasons.first
        }
        // .series: in-progress season first, then next after last fully-watched, then first
        if let inProgress = seasons.first(where: {
            ($0.userData?.playedPercentage ?? 0) > 0 && $0.userData?.played != true
        }) {
            return inProgress
        }
        if let lastPlayedIdx = seasons.lastIndex(where: { $0.userData?.played == true }),
           lastPlayedIdx + 1 < seasons.count {
            return seasons[lastPlayedIdx + 1]
        }
        return seasons.first
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(DT.Color.textPrimary)
            .tracking(-0.3)
    }
}

// MARK: - tvOS play button label
// Separate struct so @Environment(\.isFocused) reads the button's focus state,
// not the outer container. Ring/glow are drawn inside the button bounds only —
// no bleed into the surrounding layout padding.

#if os(tvOS)
private struct TVPlayButtonLabel: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .font(.system(size: 14 * DT.Scale.font))
            Text("Play")
                .font(.system(size: 16 * DT.Scale.font, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14 * DT.Scale.font)
        .background(LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.accent],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .stroke(isFocused ? Color.white.opacity(0.6) : Color.clear, lineWidth: 3)
        )
        .shadow(
            color: isFocused ? DT.Color.accent.opacity(0.55) : DT.Color.accent.opacity(0.15),
            radius: isFocused ? 18 : 6
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)
    }
}
#endif

#Preview {
    NavigationStack {
        MediaDetailView(item: MediaItem(
            id: "1", name: "Dune: Part Two", type: .movie,
            backdropImageTags: [], productionYear: 2024, communityRating: 8.3
        ))
        .environment(MediaRepository())
        .environment(AuthManager())
    }
}
