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
    @State private var openSeerrItem: SeerrItem?
    @State private var sectionOffsets: [CGFloat] = []
    @State private var isFavorite = false
    @State private var likes: Bool?
    @State private var isWatched = false
    @State private var showSubtitleSearch = false
    @State private var seriesItem: MediaItem?
    @State private var jellyfinRecommended: MovieRecommendationCategory?
    /// Collections and playlists this title (or an episode's show) is in.
    @State private var containingCollections: [MediaItem] = []
    @State private var containingPlaylists: [MediaItem] = []
    @State private var openedCollection: MediaItem?
    @State private var openedPlaylist: MediaItem?
    @State private var loadedSeasonId: String?
    @Namespace private var focusNamespace

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
            .focusScope(focusNamespace)
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
        .screenBackground()
        .task { await load() }
        .task(id: item.id) {
            guard let credential, let authHeader else { return }
            let found = await ContainingSets.shared.sets(containing: [item.id, item.seriesId].compactMap { $0 },
                                                         credential: credential, authHeader: authHeader)
            containingCollections = found.collections
            containingPlaylists = found.playlists
        }
        .navigationDestination(item: $openedCollection) { TVCollectionDetailView(item: $0) }
        .navigationDestination(item: $openedPlaylist) { LibraryDetailView(playlistItem: $0) }
        .task(id: item.tmdbId) {
            guard let tmdbId = item.tmdbId else { return }
            awards = await WikidataAwardsClient.shared.awards(
                tmdbId: tmdbId, mediaType: item.type == .series ? .tv : .movie
            )
        }
        .onChange(of: selectedSeason) { _, season in
            guard let season, season.id != loadedSeasonId, let seriesId = seasonSeriesId,
                  let cred = credential, let header = authHeader else { return }
            Task {
                loadedSeasonId = season.id
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
        // The fixed wait after the player closes can beat the stop report to the server.
        .onReceive(NotificationCenter.default.publisher(for: .arcfinPlaybackReported)) { _ in
            Task { await refreshAfterPlayback(waitForReport: false) }
        }
        .fullScreenCover(item: $playbackRequest, onDismiss: { Task { await refreshAfterPlayback() } }) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                playbackRequest = PlaybackRequest(item: next, startTicks: 0)
            }
        }
        .navigationDestination(item: $openSeerrItem) { TVSeerrItemDetailView(item: $0) }
        .sheet(isPresented: $showSubtitleSearch) {
            NavigationStack {
                SubtitleSearchView(itemId: item.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { showSubtitleSearch = false } }
                    }
            }
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
                Text(String(year)).font(.system(size: 23)).foregroundStyle(.white.opacity(0.7))
            }
            if let rating = detail?.officialRating, !rating.isEmpty {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                Text(rating)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.3), lineWidth: 1))
            }
            if let mins = detail?.runtimeMinutes {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                Text("\(mins)m").font(.system(size: 23)).foregroundStyle(.white.opacity(0.7))
            }
            if let rating = item.communityRating {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(DT.Color.accent)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 23, weight: .bold)).foregroundStyle(DT.Color.accent)
                }
            }
            if let critics = detail?.criticRating {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 5) {
                    Image(systemName: critics >= 60 ? "checkmark.seal.fill" : "xmark.seal.fill").font(.system(size: 16))
                    Text(Double(critics) / 100, format: .percent.precision(.fractionLength(0))).font(.system(size: 23, weight: .bold))
                }
                .foregroundStyle(critics >= 60 ? DT.Color.palette("10b981") : DT.Color.palette("f59e0b"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Critics score \(Int(critics.rounded())) percent")
            }
            if detail?.is4K == true { qualityBadge("4K", color: DT.Color.accent) }
            if detail?.isHDR == true { qualityBadge("HDR", color: DT.Color.palette("F59E0B")) }
            if !awards.isEmpty {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill").font(.system(size: 16))
                    Text(awardsLabel).font(.system(size: 23, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(DT.Color.palette("f59e0b"))
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

    /// A series itself isn't playable; Play on its page starts the episode the server says is next.
    private var playTarget: MediaItem {
        item.type == .series ? (nextEpisode ?? item) : (detail?.item ?? item)
    }

    private var isResumable: Bool {
        guard let ud = playTarget.userData else { return false }
        return ud.playbackPositionTicks > 0 && !ud.played
    }

    private var playLabel: String {
        let episode = playTarget.type == .episode ? playTarget.indexNumber.map { "E\($0)" } : nil
        if isResumable {
            if let total = item.type == .series ? nil : detail?.runTimeTicks,
               let position = playTarget.userData?.playbackPositionTicks, total > position {
                let minutes = Int(Double(total - position) / 10_000_000 / 60)
                let left = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
                return "Resume · \(left) left"
            }
            return episode.map { "Resume \($0)" } ?? "Resume"
        }
        return episode.map { "Play \($0)" } ?? "Play"
    }

    private var actionColumn: some View {
        VStack(spacing: 14) {
            Button {
                playbackRequest = PlaybackRequest(item: playTarget, startTicks: isResumable ? (playTarget.userData?.playbackPositionTicks ?? 0) : 0)
            } label: {
                TVDetailButtonLabel(icon: "play.fill", text: playLabel, isPrimary: true)
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .prefersDefaultFocus(true, in: focusNamespace)
            .accessibilityIdentifier("detail.play")

            if isResumable {
                Button {
                    playbackRequest = PlaybackRequest(item: playTarget, startTicks: 0)
                } label: {
                    TVDetailButtonLabel(icon: "arrow.counterclockwise", text: "Start Over")
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
            }

            HStack(spacing: 14) {
                Button { toggleFavorite() } label: {
                    TVDetailButtonLabel(icon: isFavorite ? "heart.fill" : "heart", text: "")
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                Menu {
                    moreMenuContent
                } label: {
                    TVDetailButtonLabel(icon: "ellipsis", text: "")
                }
                .accessibilityLabel("More")
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
        }
    }

    @ViewBuilder
    private var moreMenuContent: some View {
        Button { setRating(true) } label: {
            Label(likes == true ? "Remove Like" : "Like", systemImage: likes == true ? "hand.thumbsup.fill" : "hand.thumbsup")
        }
        Button { setRating(false) } label: {
            Label(likes == false ? "Remove Dislike" : "Dislike", systemImage: likes == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
        }
        if item.type == .movie || item.type == .episode {
            Button { markWatched(!isWatched) } label: {
                Label(isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: isWatched ? "eye.slash" : "checkmark")
            }
        }
        Button { PlaylistStore.shared.addingItem = item } label: {
            Label("Add to Playlist…", systemImage: "text.badge.plus")
        }
        if (item.type == .movie || item.type == .episode) && ProfileRules.shared.canManageSubtitles {
            Button { showSubtitleSearch = true } label: {
                Label("Search for Subtitles…", systemImage: "captions.bubble")
            }
        }
    }

    private func setRating(_ value: Bool) {
        guard let cred = credential, let header = authHeader else { return }
        let newValue: Bool? = likes == value ? nil : value
        likes = newValue
        Task { try? await client.setRating(credential: cred, authHeader: header, itemId: item.id, likes: newValue) }
    }

    private func toggleFavorite() {
        guard let cred = credential, let header = authHeader else { return }
        isFavorite.toggle()
        let newValue = isFavorite
        Task { try? await client.markFavorite(credential: cred, authHeader: header, itemId: item.id, favorite: newValue) }
    }

    private func markWatched(_ watched: Bool) {
        guard let cred = credential, let header = authHeader else { return }
        isWatched = watched
        Task {
            try? await client.markWatched(credential: cred, authHeader: header, itemId: item.id, watched: watched)
            await refreshAfterPlayback(waitForReport: false)
        }
    }

    private func markEpisodeWatched(_ ep: MediaItem, watched: Bool) {
        guard let cred = credential, let header = authHeader else { return }
        Task {
            try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
            await refreshAfterPlayback(waitForReport: false)
        }
    }

    private enum WatchScope { case season, series }

    private func markScopeWatched(_ scope: WatchScope, watched: Bool) {
        guard let cred = credential, let header = authHeader, let seriesId = seasonSeriesId else { return }
        let seasonEpisodes = episodes
        let allSeasons = seasons
        Task {
            switch scope {
            case .season:
                for ep in seasonEpisodes {
                    try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
                }
            case .series:
                for season in allSeasons {
                    let eps = (try? await client.getEpisodes(credential: cred, authHeader: header, seriesId: seriesId, seasonId: season.id)) ?? []
                    for ep in eps {
                        try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
                    }
                }
            }
            await refreshAfterPlayback(waitForReport: false)
        }
    }

    /// Re-reads progress after the player closes, so Play becomes Resume and the episodes show
    /// what was watched.
    private func refreshAfterPlayback(waitForReport: Bool = true) async {
        guard let cred = credential, let header = authHeader else { return }
        if waitForReport { try? await Task.sleep(for: .milliseconds(700)) }
        if let fresh = try? await client.getItemDetail(credential: cred, authHeader: header, itemId: item.id) {
            detail = fresh
            isWatched = fresh.item.userData?.played ?? false
        }
        guard let seriesId = seasonSeriesId else { return }
        if item.type == .series,
           let next = try? await client.getNextEpisode(credential: cred, authHeader: header, seriesId: seriesId) {
            nextEpisode = next
        }
        if let seasonId = loadedSeasonId,
           let fresh = try? await client.getEpisodes(credential: cred, authHeader: header, seriesId: seriesId, seasonId: seasonId) {
            episodes = fresh
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
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(DT.Color.textSecondary)
            Text(value)
                .font(.system(size: 23))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
        }
    }

    // MARK: - Below fold

    // One stack, so the page's padding wraps the sections once instead of padding each of
    // them. Each section brings its own 56 pt below it.
    private var belowFoldSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room under the hero's buttons, which grow when focused, so they don't cover the heading.
            if !seasons.isEmpty { seriesSection.padding(.top, 48).trackSectionOffset().focusSection() }
            if let seriesItem, item.type == .episode {
                itemRow("Series", [seriesItem]).trackSectionOffset().focusSection()
            }
            if !trailers.isEmpty {
                trailersSection.padding(.top, trailersFollowHero ? 48 : 0).trackSectionOffset().focusSection()
            }
            TitleInsights(tmdbId: insightsTmdbId, mediaType: seerrMediaType(for: item), part: .ratings, spacingBelow: 56)
                .padding(.horizontal, 80)
                .focusSection()
            if let d = detail, !d.cast.isEmpty { castSection(d).trackSectionOffset().focusSection() }
            if !seerrRelatedItems.isEmpty {
                seerrRelatedSection.trackSectionOffset().focusSection()
            } else if !similarItems.isEmpty {
                similarSection.trackSectionOffset().focusSection()
            }
            if let jellyfinRecommended, !jellyfinRecommended.items.isEmpty {
                itemRow(jellyfinRecommended.title, jellyfinRecommended.items).trackSectionOffset().focusSection()
            }
            if !containingCollections.isEmpty {
                setRow(containingCollections.count == 1 ? "Collection" : "Collections", containingCollections) { openedCollection = $0 }
                    .trackSectionOffset().focusSection()
            }
            if !containingPlaylists.isEmpty {
                setRow("In Your Playlists", containingPlaylists) { openedPlaylist = $0 }
                    .trackSectionOffset().focusSection()
            }
            TitleInsights(tmdbId: insightsTmdbId, mediaType: seerrMediaType(for: item), detail: detail, part: .details)
                .padding(.horizontal, 80)
                .focusSection()
        }
    }

    /// An episode's TMDB id is the episode's own, which the title lookups don't take.
    private var insightsTmdbId: Int? {
        item.type == .episode ? nil : (detail?.item.tmdbId ?? item.tmdbId)
    }

    private func itemRow(_ title: String, _ items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(title).padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { rec in
                        NavigationLink(value: rec) {
                            PosterCard(
                                title: rec.name,
                                subtitle: rec.productionYear.map { String($0) },
                                imageURL: mediaRepo.tvImageURL(for: rec, fillWidth: 640)
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

    /// Collections or playlists, which open their own pages rather than a title's.
    private func setRow(_ title: String, _ sets: [MediaItem], open: @escaping (MediaItem) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(title).padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(sets) { set in
                        Button { open(set) } label: {
                            PosterCard(title: set.name, imageURL: mediaRepo.tvImageURL(for: set, fillWidth: 640))
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

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionTitle("Episodes")
                Spacer()
                Menu {
                    Button("Mark Season Watched") { markScopeWatched(.season, watched: true) }
                    Button("Mark Season Unwatched") { markScopeWatched(.season, watched: false) }
                    Button("Mark Series Watched") { markScopeWatched(.series, watched: true) }
                    Button("Mark Series Unwatched") { markScopeWatched(.series, watched: false) }
                } label: {
                    TVSeasonPickerLabel(name: "Watched", systemImage: "checkmark.circle")
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
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
                            let watched = ep.userData?.played == true
                            Button { selectedEpisode = ep } label: {
                                TVEpisodeCard(ep: ep, badge: episodeBadge(ep))
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .contextMenu {
                                Button {
                                    playbackRequest = PlaybackRequest(item: ep, startTicks: ep.userData?.playbackPositionTicks ?? 0)
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }
                                Button { markEpisodeWatched(ep, watched: !watched) } label: {
                                    Label(watched ? "Mark as Unwatched" : "Mark as Watched", systemImage: watched ? "eye.slash" : "checkmark")
                                }
                            }
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

    private var trailersFollowHero: Bool {
        seasons.isEmpty && !(seriesItem != nil && item.type == .episode)
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
                            TVCastPersonCard(
                                imageURL: person.primaryImageTag.flatMap {
                                    mediaRepo.personImageURL(personId: person.id, tag: $0, fillWidth: 240)
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
                .font(.system(size: 44))
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
                        Button { openSeerrItem = sim } label: {
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
                        .tvFocusRing(cornerRadius: DT.Radius.md)
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
        isFavorite = fetchedDetail?.item.userData?.isFavorite ?? item.userData?.isFavorite ?? false
        likes = fetchedDetail?.item.userData?.likes ?? item.userData?.likes
        isWatched = fetchedDetail?.item.userData?.played ?? item.userData?.played ?? false
        if item.type == .episode, let seriesId = item.seriesId {
            seriesItem = (try? await client.getItemDetail(credential: cred, authHeader: header, itemId: seriesId))?.item
        }

        if let fetchedDetail, let mediaType = seerrMediaType(for: fetchedDetail.item),
           let tmdbId = fetchedDetail.item.tmdbId {
            seerrRelatedItems = await seerrRepo.relatedMedia(mediaType: mediaType, mediaId: tmdbId)
        }
        if seerrRelatedItems.isEmpty {
            similarItems = (try? await client.getSimilarItems(credential: cred, authHeader: header, itemId: item.id)) ?? []
        }
        if seerrRelatedItems.isEmpty, item.type == .movie {
            let categories = (try? await client.getMovieRecommendations(credential: cred, authHeader: header)) ?? []
            let shown = Set(similarItems.map(\.id))
            if let match = categories.first(where: { $0.baselineItemName?.caseInsensitiveCompare(item.name) == .orderedSame }) {
                let fresh = match.items.filter { !shown.contains($0.id) && $0.id != item.id }
                if fresh.count >= 3 {
                    jellyfinRecommended = MovieRecommendationCategory(
                        id: match.id, recommendationType: match.recommendationType,
                        baselineItemName: match.baselineItemName, items: fresh)
                }
            }
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
            loadedSeasonId = target.id
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
            .font(.system(size: 23, weight: .bold))
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

    /// "NEW" for an unwatched episode out in the last two weeks; "FINALE" for the season's last.
    private func episodeBadge(_ ep: MediaItem) -> String? {
        if ep.userData?.played != true, let premiere = ep.premiereDate,
           premiere <= Date(), Date().timeIntervalSince(premiere) < 14 * 86_400 {
            return "NEW"
        }
        if episodes.count > 1, ep.id == episodes.last?.id { return "FINALE" }
        return nil
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
    var systemImage = "chevron.down"
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(isFocused ? .white : DT.Color.accent)
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(isFocused ? .white : DT.Color.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Capsule().fill(isFocused ? DT.Color.accent : DT.Color.accent.opacity(0.1)))
        .shadow(color: isFocused ? DT.Color.accent.opacity(0.45) : .clear, radius: 10)
        .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}

// MARK: - Episode card

private struct TVEpisodeCard: View {
    let ep: MediaItem
    var badge: String? = nil
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.isFocused) private var isFocused
    @AppStorage("spoilerProtection") private var spoilerProtection = false

    private var hidesSpoilers: Bool {
        spoilerProtection && ep.userData?.played != true && (ep.userData?.playedPercentage ?? 0) == 0
    }

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
            .blur(radius: hidesSpoilers ? 24 : 0)
            .overlay {
                if ep.userData?.played == true {
                    ZStack {
                        Color.black.opacity(0.45)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(DT.Color.palette("10b981"))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let pct = ep.userData?.playedPercentage, pct > 0, ep.userData?.played != true {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.25))
                            Rectangle().fill(DT.Color.accent).frame(width: geo.size.width * min(pct / 100, 1))
                        }
                    }
                    .frame(height: 5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3)
            )
            .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 10)
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if let epNum = ep.indexNumber {
                        Text("Ep \(epNum)")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(DT.Color.accent)
                    }
                    if let badge {
                        Text(badge)
                            .font(.system(size: 23, weight: .bold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(DT.Color.accent.opacity(0.18), in: Capsule())
                            .foregroundStyle(DT.Color.accent)
                    }
                }
                Text(ep.name)
                    .font(.system(size: 23, weight: .semibold))
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

private struct TVCastPersonCard<Placeholder: View>: View {
    let imageURL: URL?
    let name: String
    let role: String?
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(spacing: 8) {
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
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(Circle().stroke(isFocused ? DT.Color.accent : Color.white.opacity(0.1), lineWidth: isFocused ? 4 : 1))
            .shadow(color: isFocused ? DT.Color.accent.opacity(0.45) : .clear, radius: 12)
            .scaleEffect(isFocused ? 1.08 : 1)

            Text(name)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let role, !role.isEmpty {
                Text(role)
                    .font(.system(size: 23))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 160, alignment: .top)
        .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)
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
