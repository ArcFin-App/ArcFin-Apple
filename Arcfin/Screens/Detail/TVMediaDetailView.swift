// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(tvOS)
import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore

struct TVMediaDetailView: View {
    static let scrollSpace = "tvDetailScroll"

    let item: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(StreamystatsRepository.self) private var statsRepo

    @State private var detail: MediaItemDetail?
    @State private var awards: [WikidataAward] = []
    @State private var seasons: [MediaItem] = []
    @State private var selectedSeason: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var trailers: [MediaItem] = []
    @State private var similarItems: [MediaItem] = []
    @State private var seerrRelatedItems: [SeerrItem] = []
    @State private var isLoading = true
    @State private var showFullDescription = false
    @State private var selectedEpisode: MediaItem?
    @State private var selectedPerson: MediaPerson?
    @State private var initialEpisodeID: String?
    @State private var nextEpisode: MediaItem?
    @State private var playbackRequest: PlaybackRequest?
    @State private var requestingSeerrItem: SeerrItem?
    @State private var sectionOffsets: [CGFloat] = []

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
            .coordinateSpace(name: Self.scrollSpace)
            // TVFoldSnappingBehavior (shared with TVHomeView) only dampens the single
            // hero/shelf fold boundary — it intentionally leaves every target further down
            // untouched, since forcing it to always snap to just two points broke scrolling
            // past the first shelf there. That guard means it does nothing for transitions
            // between below-fold sections here (Episodes/Trailers/Cast/Recommended), which
            // is exactly where tvOS's default focus-driven centering still recenters on
            // whatever short section just gained focus, reading as a big gap above/below
            // it — confirmed happening regardless of whether a trailer is present at all.
            // Extend the same idea across every section boundary instead of just the fold.
            .scrollTargetBehavior(TVSectionSnappingBehavior(
                showcaseHeight: sh * 0.88, sectionOffsets: sectionOffsets
            ))
            .onPreferenceChange(TVSectionOffsetKey.self) { sectionOffsets = $0.sorted() }
            .ignoresSafeArea()
        }
        .background(DT.Color.backgroundPrimary)
        .task { await load() }
        .task(id: item.tmdbId) {
            guard let tmdbId = item.tmdbId else { return }
            awards = await WikidataAwardsClient.shared.awards(
                tmdbId: tmdbId, mediaType: item.type == .series ? .tv : .movie
            )
        }
        .onChange(of: selectedSeason) { _, season in
            guard let season, let seriesId = seasonSeriesId,
                  let cred = credential, let header = authHeader else { return }
            Task {
                episodes = (try? await client.getEpisodes(
                    credential: cred, authHeader: header,
                    seriesId: seriesId, seasonId: season.id)) ?? []
            }
        }
        .navigationDestination(item: $selectedEpisode) { ep in
            TVMediaDetailView(item: ep)
        }
        .navigationDestination(item: $selectedPerson) { person in
            PersonDetailView(person: person)
        }
        .fullScreenCover(isPresented: $showFullDescription) {
            fullDescriptionCover
        }
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                playbackRequest = PlaybackRequest(item: next, startTicks: 0)
            }
        }
        .sheet(item: $requestingSeerrItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingSeerrItem)
        }
    }

    // MARK: - Showcase (above fold)

    private func showcaseSection(screenW: CGFloat, screenH: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920) {
                CachedAsyncImage(url: url) { phase in
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
        CachedAsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
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
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                Text(rating)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.3), lineWidth: 1))
            }
            if let mins = detail?.runtimeMinutes {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                Text("\(mins)m").font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
            }
            if let rating = item.communityRating {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(DT.Color.accent)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(DT.Color.accent)
                }
            }
            if detail?.is4K == true { qualityBadge("4K", color: DT.Color.accent) }
            if detail?.isHDR == true { qualityBadge("HDR", color: Color(hex: "F59E0B")) }
            if !awards.isEmpty {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill").font(.system(size: 16))
                    Text(awardsLabel).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(Color(hex: "f59e0b"))
            }
        }
    }

    /// One entry → that award's own name; a few → joined; many → just the count.
    private var awardsLabel: String {
        let names = Array(Set(awards.map(\.name))).sorted()
        if names.count == 1 { return "Won \(names[0])" }
        if names.count <= 3 { return "Won \(names.joined(separator: ", "))" }
        return "Won \(names.count) Awards"
    }

    private var threeColumnLayout: some View {
        HStack(alignment: .top, spacing: 40) {
            actionColumn.frame(width: 260)
            descriptionColumn
            infoColumn.frame(width: 260)
        }
    }

    private var playLabel: String {
        if let ep = nextEpisode ?? (item.type == .episode ? item : nil),
           let num = ep.indexNumber {
            return "Play E\(num)"
        }
        return "Play"
    }

    private var actionColumn: some View {
        VStack(spacing: 14) {
            Button {
                let target = nextEpisode ?? item
                playbackRequest = PlaybackRequest(item: target, startTicks: target.userData?.playbackPositionTicks ?? 0)
            } label: {
                TVDetailButtonLabel(icon: "play.fill", text: playLabel, isPrimary: true)
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()

            Button {
                if statsRepo.isConfigured {
                    Task { try? await statsRepo.addToWatchlist(itemId: item.id) }
                }
            } label: {
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
        if !seasons.isEmpty { seriesSection.trackSectionOffset().focusSection() }
        if !trailers.isEmpty { trailersSection.trackSectionOffset().focusSection() }
        if let d = detail, !d.cast.isEmpty { castSection(d).trackSectionOffset().focusSection() }
        if !seerrRelatedItems.isEmpty {
            seerrRelatedSection.trackSectionOffset().focusSection()
        } else if !similarItems.isEmpty {
            similarSection.trackSectionOffset().focusSection()
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
                    TVSeasonPickerLabel(name: selectedSeason?.name ?? "Season")
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
            }
            .padding(.horizontal, 80)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(episodes) { ep in
                            Button { selectedEpisode = ep } label: {
                                TVEpisodeCard(ep: ep)
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .id(ep.id)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 20)
                    .focusSection()
                }
                .scrollClipDisabled()
                .onChange(of: episodes) { _, newEps in
                    guard let target = initialEpisodeID,
                          newEps.contains(where: { $0.id == target }) else { return }
                    proxy.scrollTo(target, anchor: .leading)
                    initialEpisodeID = nil
                }
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
                        Button {
                            playbackRequest = PlaybackRequest(item: trailer, startTicks: 0)
                        } label: {
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
                .padding(.top, 20)
                .focusSection()
            }
            .scrollClipDisabled()
        }
        .padding(.bottom, 56)
    }

    private func castSection(_ d: MediaItemDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Cast").padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(d.cast) { person in
                        Button { selectedPerson = person } label: {
                            CastPersonCard(
                                imageURL: person.primaryImageTag.flatMap {
                                    mediaRepo.personImageURL(personId: person.id, tag: $0, fillWidth: 120)
                                },
                                name: person.name,
                                role: person.role,
                                placeholder: { personPlaceholder }
                            )
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 20)
                .focusSection()
            }
            .scrollClipDisabled()
        }
        .padding(.bottom, 56)
    }

    private var personPlaceholder: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .font(.system(size: 22))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
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
                .padding(.top, 20)
                .focusSection()
            }
            .scrollClipDisabled()
        }
        .padding(.bottom, 56)
    }

    private var seerrRelatedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Recommended").padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(seerrRelatedItems) { sim in
                        Button { requestingSeerrItem = sim } label: {
                            PosterCard(
                                title: sim.title,
                                subtitle: sim.year,
                                imageURL: sim.backdropURL ?? sim.posterURL
                            )
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 20)
                .focusSection()
            }
            .scrollClipDisabled()
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

        // Awaited like every other section's fetch above — a detached Task here let the
        // page finish loading and render (isLoading already false) before trailers arrived,
        // so trailersSection popped in late and shoved Cast/Recommended down into an
        // already-settled, already-focused layout, reading as an unexplained gap.
        trailers = (try? await client.getTrailers(
            credential: cred, authHeader: header, itemId: item.id, limit: 6)) ?? []

        if let seriesId = seasonSeriesId {
            seasons = (try? await client.getSeasons(credential: cred, authHeader: header, seriesId: seriesId)) ?? []
            guard let first = seasons.first else { return }

            var target = first
            switch item.type {
            case .series:
                // Ask the server which episode is next — use its season and scroll to it.
                if let nextEp = try? await client.getNextEpisode(credential: cred, authHeader: header, seriesId: seriesId) {
                    if let seasonNum = nextEp.parentIndexNumber,
                       let matched = seasons.first(where: { $0.indexNumber == seasonNum }) {
                        target = matched
                    }
                    initialEpisodeID = nextEp.id
                    nextEpisode = nextEp
                }
            case .episode:
                target = selectedSeasonForCurrentItem(from: seasons) ?? first
                initialEpisodeID = item.id
            case .season:
                target = selectedSeasonForCurrentItem(from: seasons) ?? first
            default:
                break
            }

            selectedSeason = target
            episodes = (try? await client.getEpisodes(
                credential: cred, authHeader: header,
                seriesId: seriesId, seasonId: target.id)) ?? []
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

// MARK: - Season picker label

private struct TVSeasonPickerLabel: View {
    let name: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(isFocused ? .white : DT.Color.accent)
            Image(systemName: "chevron.down")
                .font(.system(size: 18))
                .foregroundStyle(isFocused ? .white : DT.Color.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(isFocused ? DT.Color.accent : DT.Color.accent.opacity(0.1)))
        .shadow(color: isFocused ? DT.Color.accent.opacity(0.45) : .clear, radius: 10)
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }
}

// MARK: - Episode card

private struct TVEpisodeCard: View {
    let ep: MediaItem
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: mediaRepo.episodeThumbnailURL(for: ep, fillWidth: 400)) { phase in
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

// MARK: - Cast person card

private struct CastPersonCard<Placeholder: View>: View {
    let imageURL: URL?
    let name: String
    let role: String?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let imageURL {
                    CachedAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: placeholder()
                        }
                    }
                } else {
                    placeholder()
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(Circle().stroke(hovered ? DT.Color.accent.opacity(0.6) : Color.white.opacity(0.1), lineWidth: hovered ? 2 : 1))
            .scaleEffect(hovered ? 1.06 : 1)

            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let role, !role.isEmpty {
                Text(role)
                    .font(.system(size: 9))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 70, alignment: .top)
        .animation(DT.Animation.fast, value: hovered)
    }
}

private struct TVSectionOffsetKey: PreferenceKey {
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    // Reports this section's own top edge, in the scroll view's content coordinate space,
    // so TVSectionSnappingBehavior below knows every section boundary on the page, not
    // just the single hero/shelf fold TVFoldSnappingBehavior already handles.
    func trackSectionOffset() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TVSectionOffsetKey.self,
                    value: [geo.frame(in: .named(TVMediaDetailView.scrollSpace)).minY]
                )
            }
        )
    }
}

// Generalizes TVFoldSnappingBehavior's hero-fold dampening to every below-fold section
// boundary on this screen. tvOS's default focus-driven scrolling centers whatever just
// gained focus in the viewport — fine for a tall section, but each below-fold section here
// (Episodes, Trailers, Cast, Recommended) is much shorter than the screen, so centering on
// a card inside one reads as a big empty gap above and below it. Snapping to the nearest
// known section start instead keeps the top of whichever section just gained focus flush
// with the viewport, matching how the hero/shelf fold already behaves.
private struct TVSectionSnappingBehavior: ScrollTargetBehavior {
    let showcaseHeight: CGFloat
    let sectionOffsets: [CGFloat]

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let candidates = [0, showcaseHeight] + sectionOffsets
        guard let nearest = candidates.min(by: {
            abs($0 - target.rect.minY) < abs($1 - target.rect.minY)
        }) else { return }
        // Only pull toward a snap point that's actually close — an unconditional snap
        // fights normal scrolling through a section's own tall content (e.g. a long
        // overview) the same way an earlier unconditional version of the fold behavior
        // broke scrolling past the first shelf on Home.
        guard abs(nearest - target.rect.minY) < showcaseHeight * 0.3 else { return }
        target.rect.origin.y = nearest
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
        .environment(SeerrRepository())
    }
}
#endif
