// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore
#if os(iOS)
import SwiftData
import Persistence
#endif

struct MediaDetailView: View {
    let item: MediaItem
    #if !os(tvOS)
    /// Passed down from whichever screen pushed this view (Home/Library/PersonDetail each
    /// own their own @Namespace) so the Similar/Recommended rows below can zoom into a
    /// further MediaDetailView the same way the original poster tap did. nil when reached
    /// from a source that doesn't do the zoom transition (e.g. the Home hero banner).
    var zoomNamespace: Namespace.ID? = nil
    #endif

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager
    #if os(iOS)
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.modelContext) private var modelContext
    #endif
    #if os(macOS)
    @Environment(PlaybackPresenter.self) private var playbackPresenter
    #endif
    @Environment(\.dismiss) private var dismiss

    @State private var detail: MediaItemDetail?
    @State private var awards: [WikidataAward] = []
    @State private var isFavorite = false
    @State private var similarItems: [MediaItem] = []
    @State private var seerrRelatedItems: [SeerrItem] = []
    /// Jellyfin-native fallback for the "Recommended" row when Seerr isn't configured —
    /// Movies/Recommendations is server-wide, not per-item, so this is filtered down to
    /// whichever returned category (if any) names this movie as its baseline.
    @State private var jellyfinRecommended: MovieRecommendationCategory?
    @State private var seriesItem: MediaItem?
    /// The episode a series-level Play/Resume button actually starts — a series itself
    /// isn't playable, so this is what getNextEpisode() resolves to.
    @State private var nextEpisode: MediaItem?
    @State private var seasons: [MediaItem] = []
    @State private var selectedSeason: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var selectedEpisode: MediaItem?
    @State private var selectedPerson: MediaPerson?
    @State private var loadedSeasonId: String?
    @State private var trailers: [MediaItem] = []
    @State private var remoteTrailer: RemoteTrailer?
    @State private var youTubeTrailer: RemoteTrailer?
    @AppStorage("trailersEnabled") private var trailersEnabled = true
    @AppStorage("youtubeTrailersEnabled") private var youtubeTrailersEnabled = true
    @State private var showTrailerPicker = false
    @State private var isLoading = true
    @State private var requestingSeerrItem: SeerrItem?
    @State private var playbackRequest: PlaybackRequest?
    #if os(iOS)
    @State private var seasonDownloadPreview: DownloadManager.DownloadPreview?
    @State private var isLoadingSeasonPreview = false
    /// Set when the target is already downloaded — offers a choice instead of always
    /// streaming, since previously Play/Resume ignored a local copy entirely.
    @State private var pendingPlaybackChoice: PlaybackChoice?
    @State private var offlinePlaybackTarget: DownloadedItem?
    @State private var offlineStartOverride: Int64?
    /// Surfaces a season download failure that would otherwise only show up as a raw
    /// NSURLError buried in per-episode state nobody's looking at during a bulk download.
    @State private var seasonDownloadErrorMessage: String?

    private struct PlaybackChoice: Identifiable {
        let id = UUID()
        let item: MediaItem
        let startTicks: Int64
        let isExplicitStartOver: Bool
    }
    #endif

    struct PlaybackRequest: Identifiable, Equatable {
        let id = UUID()
        let item: MediaItem
        let startTicks: Int64
    }

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
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? Color(hex: "EF4444") : .white)
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            if item.type == .movie || item.type == .episode {
                ToolbarItem(placement: .topBarTrailing) {
                    DownloadButton(item: item)
                }
            }
        }
        #elseif os(macOS)
        // Downloads are iOS-only (DownloadManager isn't wired up on macOS elsewhere in
        // the app), but Favorite has no other entry point here without this toolbar.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? Color(hex: "EF4444") : .white)
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
        }
        #endif
        .navigationDestination(item: $selectedEpisode) { ep in
#if os(tvOS)
            MediaDetailView(item: ep)
#else
            MediaDetailView(item: ep, zoomNamespace: zoomNamespace)
#endif
        }
        .navigationDestination(item: $selectedPerson) { person in
            PersonDetailView(person: person)
        }
        .sheet(item: $requestingSeerrItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingSeerrItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        #if os(iOS)
        .sheet(item: $seasonDownloadPreview) { preview in
            DownloadConfirmSheet(item: selectedSeason ?? item, preview: preview) { bitrateCap in
                downloadSeason(bitrateCap: bitrateCap)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "This is downloaded — play the offline copy or stream from the server?",
            isPresented: Binding(get: { pendingPlaybackChoice != nil }, set: { if !$0 { pendingPlaybackChoice = nil } }),
            titleVisibility: .visible
        ) {
            Button("Play Downloaded") {
                if let choice = pendingPlaybackChoice, let downloaded = fetchDownloadedItem(itemId: choice.item.id) {
                    offlineStartOverride = choice.isExplicitStartOver ? 0 : nil
                    offlinePlaybackTarget = downloaded
                }
                pendingPlaybackChoice = nil
            }
            Button("Stream Online") {
                if let choice = pendingPlaybackChoice {
                    playbackRequest = PlaybackRequest(item: choice.item, startTicks: choice.startTicks)
                }
                pendingPlaybackChoice = nil
            }
            Button("Cancel", role: .cancel) { pendingPlaybackChoice = nil }
        }
        .fullScreenCover(item: $offlinePlaybackTarget) { downloaded in
            OfflinePlayerView(downloadedItem: downloaded, startPositionOverride: offlineStartOverride)
        }
        .alert("Download Failed", isPresented: Binding(
            get: { seasonDownloadErrorMessage != nil }, set: { if !$0 { seasonDownloadErrorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(seasonDownloadErrorMessage ?? "")
        }
        .onChange(of: downloadManager.errors) { _, newErrors in
            guard seasonDownloadErrorMessage == nil else { return }
            for episode in episodes {
                if let raw = newErrors[episode.id] {
                    seasonDownloadErrorMessage = friendlyDownloadError(raw)
                    downloadManager.errors[episode.id] = nil
                    break
                }
            }
        }
        #endif
#if os(iOS)
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                playbackRequest = PlaybackRequest(item: next, startTicks: 0)
            }
        }
        .fullScreenCover(item: $youTubeTrailer) { trailer in
            if let videoID = trailer.youTubeVideoID {
                YouTubeTrailerPlayerView(videoID: videoID, title: trailer.name ?? item.name)
            }
        }
#elseif os(macOS)
        // A .sheet on macOS can't fill/fullscreen a window — PlayerView is rendered as a
        // full-window overlay by ContentView instead, driven by the shared PlaybackPresenter.
        // (YouTubeTrailerPlayerView itself is UIKit-only — the "Play Trailer" button for a
        // title with no local trailer, only a remote one, is a known gap on macOS until
        // that view grows an AppKit path.)
        .onChange(of: playbackRequest) { _, request in
            guard let request else { return }
            playbackPresenter.present(request.item, startTicks: request.startTicks)
            playbackRequest = nil
        }
#endif
        .task { await load() }
        .task(id: item.tmdbId) {
            guard let tmdbId = item.tmdbId else { return }
            awards = await WikidataAwardsClient.shared.awards(
                tmdbId: tmdbId, mediaType: item.type == .series ? .tv : .movie
            )
        }
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

    #if os(iOS)
    /// Every episode in the current season already downloaded — the "Download Season"
    /// button should be inert then, not just silently no-op every episode it loops over.
    private var isSeasonFullyDownloaded: Bool {
        !episodes.isEmpty && episodes.allSatisfy { downloadManager.isDownloaded($0.id) }
    }

    /// Fetches one representative preview (from the first not-yet-downloaded episode) to
    /// show real quality/size info in the confirm sheet, instead of the bare "Download all
    /// N episodes?" text alert that gave no size/quality info at all.
    private func loadSeasonPreview() {
        guard case .authenticated(let credential) = authManager.state else { return }
        let pending = episodes.filter { !downloadManager.isDownloaded($0.id) }
        guard let firstPending = pending.first else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        isLoadingSeasonPreview = true
        Task {
            let single = await downloadManager.preview(for: firstPending, credential: credential, authHeader: authHeader)
            isLoadingSeasonPreview = false
            let count = Int64(pending.count)
            // Scaled from one representative episode to the whole season's pending count —
            // an honest total rather than one episode's numbers presented for the whole
            // season, without needing a HEAD/playback-info round trip per episode.
            seasonDownloadPreview = DownloadManager.DownloadPreview(
                subtitleLanguages: single?.subtitleLanguages ?? [],
                audioLanguages: single?.audioLanguages ?? [],
                estimatedSizeBytes: single?.estimatedSizeBytes.map { $0 * count },
                estimatedSizeIsApproximate: true,
                willRemux: single?.willRemux ?? false,
                sourceBitrate: single?.sourceBitrate,
                runtimeTicks: single?.runtimeTicks.map { $0 * count },
                container: single?.container,
                videoCodec: single?.videoCodec,
                videoWidth: single?.videoWidth,
                videoHeight: single?.videoHeight,
                videoRange: single?.videoRange
            )
        }
    }

    private func downloadSeason(bitrateCap: Int?) {
        guard case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        for episode in episodes where !downloadManager.isDownloaded(episode.id) {
            Task { await downloadManager.startDownload(item: episode, credential: credential, authHeader: authHeader, bitrateCap: bitrateCap) }
        }
    }

    // MARK: - Play downloaded vs. stream

    private func requestPlayback(startTicks: Int64, isExplicitStartOver: Bool = false) {
        let target = playTargetItem
        if downloadManager.isDownloaded(target.id) {
            pendingPlaybackChoice = PlaybackChoice(item: target, startTicks: startTicks, isExplicitStartOver: isExplicitStartOver)
        } else {
            playbackRequest = PlaybackRequest(item: target, startTicks: startTicks)
        }
    }

    private func fetchDownloadedItem(itemId: String) -> DownloadedItem? {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        return try? modelContext.fetch(descriptor).first
    }

    /// The raw error DownloadManager surfaces per-item is a real but unhelpful string
    /// (e.g. "Download failed: The operation couldn't be completed. (NSURLErrorDomain
    /// error -1017.)") — translated into something a user can actually act on.
    private func friendlyDownloadError(_ raw: String) -> String {
        if raw.contains("-1017") {
            return "One of the episodes couldn't be downloaded because of a network hiccup mid-transfer. Try downloading it again — if it keeps happening, check your connection and available storage."
        }
        if raw.localizedCaseInsensitiveContains("permission") {
            return "One of the episodes couldn't be downloaded — this account doesn't have permission to download media. Ask your Jellyfin admin to enable it."
        }
        return "One of the episodes in this season failed to download: \(raw)"
    }
    #endif

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let cred = credential, let header = authHeader else { return }

        async let detailTask = client.getItemDetail(credential: cred, authHeader: header, itemId: item.id)
        trailers = []
        
        let fetchedDetail = try? await detailTask
        detail = fetchedDetail
        isFavorite = fetchedDetail?.item.userData?.isFavorite ?? item.userData?.isFavorite ?? false

        if let fetchedDetail, let mediaType = seerrMediaType(for: fetchedDetail.item),
           let tmdbId = fetchedDetail.item.tmdbId {
            seerrRelatedItems = await seerrRepo.relatedMedia(mediaType: mediaType, mediaId: tmdbId)
        }
        if seerrRelatedItems.isEmpty {
            similarItems = (try? await client.getSimilarItems(credential: cred, authHeader: header, itemId: item.id)) ?? []
        } else {
            similarItems = []
        }

        jellyfinRecommended = nil
        if seerrRelatedItems.isEmpty, item.type == .movie {
            let categories = (try? await client.getMovieRecommendations(credential: cred, authHeader: header)) ?? []
            jellyfinRecommended = categories.first {
                $0.baselineItemName?.caseInsensitiveCompare(item.name) == .orderedSame
            }
        }

        remoteTrailer = nil
        if trailersEnabled {
            Task {
                let fetchedTrailers = (try? await client.getTrailers(
                    credential: cred,
                    authHeader: header,
                    itemId: item.id,
                    limit: 6
                )) ?? []
                await MainActor.run {
                    trailers = fetchedTrailers
                    // Only fall back to a remote (YouTube) trailer once we know there's
                    // genuinely no local one — a local file always streams better than an
                    // embedded web player.
                    if fetchedTrailers.isEmpty, youtubeTrailersEnabled {
                        remoteTrailer = fetchedDetail?.remoteTrailers.first { $0.youTubeVideoID != nil }
                    }
                }
            }
        }

        if let seriesId = seasonSeriesId {
            seasons = (try? await client.getSeasons(credential: cred, authHeader: header, seriesId: seriesId)) ?? []
            if let first = seasons.first {
                var target = selectedSeasonForCurrentItem(from: seasons) ?? first
                // For a series entry point, ask the server which episode is next
                if item.type == .series,
                   let nextEp = try? await client.getNextEpisode(credential: cred, authHeader: header, seriesId: seriesId) {
                    nextEpisode = nextEp
                    if let seasonNum = nextEp.parentIndexNumber,
                       let matched = seasons.first(where: { $0.indexNumber == seasonNum }) {
                        target = matched
                    }
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
                RetryingAsyncImage(
                    url: url,
                    logCategory: "MediaDetailView",
                    logContext: "backdrop item=\(item.name)",
                    content: { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    },
                    placeholder: { fallbackHero }
                )
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
                RetryingAsyncImage(
                    url: url,
                    logCategory: "MediaDetailView",
                    logContext: "poster item=\(item.name)",
                    content: { img in img.resizable().scaledToFill() },
                    placeholder: { RoundedRectangle(cornerRadius: 10).fill(DT.Color.backgroundSecondary) }
                )
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
                    .font(.system(.title3, design: .default, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
                    .lineLimit(3)

                metaRow
                qualityRow
                if !awards.isEmpty { awardsRow }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, -50)
        .padding(.bottom, DT.Spacing.md)
    }

    private var metaRow: some View {
        // lineLimit(1) cascades to every Text child, giving HStack's layout room to
        // compress/truncate them when every optional field (year, rating, runtime,
        // community score) is present at once — without it, none of these Text views have
        // a defined minimum width, so HStack can't shrink them and the row overflows past
        // the screen edge instead.
        HStack(spacing: 6) {
            if let year = item.productionYear {
                Text(String(year))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = detail?.officialRating, !rating.isEmpty {
                Text("·").foregroundStyle(.white.opacity(0.2)).font(.system(.caption, design: .default))
                Text(rating)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(DT.Color.textSecondary.opacity(0.35), lineWidth: 1))
            }
            if let mins = detail?.runtimeMinutes {
                Text("·").foregroundStyle(.white.opacity(0.2)).font(.system(.caption, design: .default))
                Text("\(mins)m")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let endsAt = endTime {
                Text("·").foregroundStyle(.white.opacity(0.2)).font(.system(.caption, design: .default))
                Text("Ends \(endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = item.communityRating {
                Text("·").foregroundStyle(.white.opacity(0.2)).font(.system(.caption, design: .default))
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.accent)
                    Text(String(format: "%.1f", rating))
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundStyle(DT.Color.accent)
                }
            }
        }
        .lineLimit(1)
    }

    /// When playback started right now would finish, counting from the resume point if there
    /// is one — only meaningful for a single playable item, not a series or season.
    private var endTime: Date? {
        guard item.type == .movie || item.type == .episode,
              let total = detail?.runTimeTicks, total > 0
        else { return nil }
        let watched = isResumable ? (resumeUserData?.playbackPositionTicks ?? 0) : 0
        let remainingSeconds = Double(max(total - watched, 0)) / 10_000_000
        return Date().addingTimeInterval(remainingSeconds)
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

    /// One entry → that award's own name; a few → joined; many → just the count. Wikidata's
    /// P166 ("award received") statements are wins, not nominations, so "Won" is accurate.
    private var awardsRow: some View {
        let names = Array(Set(awards.map(\.name))).sorted()
        let label: String
        if names.count == 1 {
            label = "Won \(names[0])"
        } else if names.count <= 3 {
            label = "Won \(names.joined(separator: ", "))"
        } else {
            label = "Won \(names.count) Awards"
        }
        return HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.system(.caption2))
            Text(label)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color(hex: "f59e0b"))
    }

    private func qualityBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(.caption2, design: .default, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Play button

    /// A series itself isn't playable — Play/Resume on a series page actually starts
    /// whichever episode getNextEpisode() resolved to.
    private var playTargetItem: MediaItem {
        item.type == .series ? (nextEpisode ?? item) : (detail?.item ?? item)
    }

    private var resumeUserData: UserData? {
        playTargetItem.userData
    }

    private var isResumable: Bool {
        guard let ud = resumeUserData else { return false }
        return ud.playbackPositionTicks > 0 && !ud.played
    }

    /// "S2E5" for whichever episode Play/Resume is about to start — nil for a movie.
    private var playEpisodeLabel: String? {
        let target = playTargetItem
        guard target.type == .episode else { return nil }
        let s = target.parentIndexNumber.map { "S\($0)" }
        let e = target.indexNumber.map { "E\($0)" }
        return [s, e].compactMap { $0 }.joined().nilIfEmpty
    }

    private var resumeTimeLabel: String? {
        guard let ud = resumeUserData, ud.playbackPositionTicks > 0,
              let runTimeTicks = detail?.runTimeTicks, runTimeTicks > ud.playbackPositionTicks
        else { return nil }
        let remainingMinutes = Int(Double(runTimeTicks - ud.playbackPositionTicks) / 10_000_000 / 60)
        if remainingMinutes >= 60 { return "\(remainingMinutes / 60)h \(remainingMinutes % 60)m left" }
        return "\(remainingMinutes)m left"
    }

    private var playButton: some View {
#if os(tvOS)
        Button {} label: { TVPlayButtonLabel() }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.md)
#else
        HStack(spacing: 10) {
            Button {
                #if os(iOS)
                requestPlayback(startTicks: isResumable ? (resumeUserData?.playbackPositionTicks ?? 0) : 0)
                #else
                playbackRequest = PlaybackRequest(
                    item: playTargetItem,
                    startTicks: isResumable ? (resumeUserData?.playbackPositionTicks ?? 0) : 0
                )
                #endif
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(.subheadline))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(isResumable ? "Resume" : "Play")
                                .font(.system(.callout, design: .default, weight: .bold))
                            if let playEpisodeLabel {
                                Text(playEpisodeLabel)
                                    .font(.system(.caption2, design: .default, weight: .semibold))
                                    .opacity(0.85)
                            }
                        }
                        if let resumeTimeLabel {
                            Text(resumeTimeLabel)
                                .font(.system(.caption2, design: .default, weight: .medium))
                                .opacity(0.85)
                        }
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isResumable ? 10 : 14)
                .background(LinearGradient(
                    colors: [DT.Color.accentDeep, DT.Color.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .shadow(color: DT.Color.accent.opacity(0.35), radius: 12)
            }
            .buttonStyle(PressableButtonStyle())

            if isResumable {
                Button {
                    #if os(iOS)
                    requestPlayback(startTicks: 0, isExplicitStartOver: true)
                    #else
                    playbackRequest = PlaybackRequest(item: playTargetItem, startTicks: 0)
                    #endif
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(DT.Color.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                        .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.08), lineWidth: 1))
                }
                .accessibilityLabel("Start over")
                .buttonStyle(.plain)
                .accessibilityLabel("Start Over")
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
#endif
    }

    private var hasPlayableTrailer: Bool {
        guard trailersEnabled else { return false }
        return !trailers.isEmpty || (youtubeTrailersEnabled && remoteTrailer != nil)
    }

    @ViewBuilder
    private var trailerButton: some View {
#if !os(tvOS)
        if hasPlayableTrailer {
            Button {
                if trailers.count > 1 {
                    showTrailerPicker = true
                } else if let single = trailers.first {
                    playbackRequest = PlaybackRequest(item: single, startTicks: 0)
                } else if let remoteTrailer {
                    youTubeTrailer = remoteTrailer
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "film").font(.system(.subheadline))
                    Text("Play Trailer").font(.system(.subheadline, design: .default, weight: .semibold))
                }
                .foregroundStyle(DT.Color.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DT.Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.md)
            .confirmationDialog("Play Trailer", isPresented: $showTrailerPicker, titleVisibility: .visible) {
                ForEach(trailers) { trailer in
                    Button(trailer.name) { playbackRequest = PlaybackRequest(item: trailer, startTicks: 0) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
#endif
    }

    // MARK: - Loading skeleton

    private var loadingContent: some View {
        overviewSection("Loading overview text that fills a few lines of placeholder content.")
            .padding(.top, DT.Spacing.md)
            .redacted(reason: .placeholder)
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        playButton
        trailerButton

        // Genres
        if let d = detail, !d.genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(d.genres, id: \.self) { genre in
                        Text(genre)
                            .font(.system(.caption2, design: .default, weight: .medium))
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

        // Similar / recommended
        if !seerrRelatedItems.isEmpty {
            seerrRelatedSection
        } else if !similarItems.isEmpty {
            similarSection
        }
        if let jellyfinRecommended, !jellyfinRecommended.items.isEmpty {
            jellyfinRecommendedSection(jellyfinRecommended)
        }
    }

    // MARK: - Overview

    private func overviewSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Overview")
            Text(text)
                .font(.system(.footnote, design: .default))
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
                // Lazy: a plain HStack fired every cast member's AsyncImage request the
                // instant this section appeared — a large cast (20+ for some titles) could
                // saturate AsyncImage's shared URLSession all at once and fail the whole
                // burst together under any network degradation. See ShelfRow.swift for the
                // same fix applied to Home's shelves.
                LazyHStack(alignment: .top, spacing: 12) {
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
#if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
#else
                        .buttonStyle(.plain)
#endif
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
                .font(.system(.title2))
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
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(people.map { $0.name }.joined(separator: ", "))
                .font(.system(.caption, design: .default))
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
                            .font(.system(.callout, design: .default, weight: .bold))
                            .foregroundStyle(DT.Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(.caption2, weight: .semibold))
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

                Menu {
                    Button { markScopeWatched(.season, watched: true) } label: {
                        Label("Mark Season Watched", systemImage: "checkmark.circle")
                    }
                    Button { markScopeWatched(.season, watched: false) } label: {
                        Label("Mark Season Unwatched", systemImage: "circle")
                    }
                    Divider()
                    Button { markScopeWatched(.series, watched: true) } label: {
                        Label("Mark Series Watched", systemImage: "checkmark.circle.fill")
                    }
                    Button { markScopeWatched(.series, watched: false) } label: {
                        Label("Mark Series Unwatched", systemImage: "circle.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .accessibilityLabel("Mark watched options")
#if os(tvOS)
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: DT.Radius.pill)
#else
                .buttonStyle(.plain)
#endif

                Spacer()

                #if os(iOS)
                Button {
                    if isLoadingSeasonPreview { return }
                    loadSeasonPreview()
                } label: {
                    HStack(spacing: 5) {
                        if isLoadingSeasonPreview {
                            ProgressView().scaleEffect(0.7).tint(DT.Color.accent)
                        } else {
                            Image(systemName: isSeasonFullyDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        }
                        Text(isSeasonFullyDownloaded ? "Season Downloaded" : "Download Season")
                    }
                    .font(.system(.caption, design: .default, weight: .semibold))
                    // A hardcoded accent color didn't dim when disabled (episodes still
                    // loading, or the whole season already downloaded) — tapping it then
                    // did nothing with zero visual feedback, which read as "no confirm
                    // popup ever shows up". Tapping an already-fully-downloaded season's
                    // button was also what produced the -1017 "Download Failed" error.
                    .foregroundStyle(episodes.isEmpty || isSeasonFullyDownloaded ? DT.Color.accent.opacity(0.35) : DT.Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(episodes.isEmpty || isSeasonFullyDownloaded)
                #else
                Text("Episodes")
                    .font(.system(.footnote, design: .default, weight: .medium))
                    .foregroundStyle(DT.Color.textSecondary)
                #endif
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
                        .font(.system(.subheadline))
                        .foregroundStyle(DT.Color.accent)
                    Text(series.name)
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2))
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
                                .font(.system(.title2))
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
                                .font(.system(.caption2, design: .default, weight: .semibold))
                                .foregroundStyle(DT.Color.accent)
                        }
                        Text(ep.name)
                            .font(.system(.footnote, design: .default, weight: .semibold))
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    #if os(iOS)
                    DownloadButton(item: ep)
                    #endif
                }

                if let overview = ep.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(.caption2, design: .default))
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
        .contextMenu(menuItems: {
            Button {
                HapticManager.impact(.light)
                markEpisodeWatched(ep, watched: !isWatched)
            } label: {
                Label(isWatched ? "Mark as Unwatched" : "Mark as Watched",
                      systemImage: isWatched ? "eye.slash" : "checkmark")
            }
        }, preview: {
            episodeRowPreview(ep)
        })
    }

    private func episodeRowPreview(_ ep: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
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
            }
            .frame(width: 240, height: 135)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(ep.name)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 240, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }

    private var episodeThumbPlaceholder: some View {
        Rectangle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(
                Image(systemName: "play.rectangle")
                    .font(.system(.title3))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.3))
            )
    }

    private func toggleFavorite() {
        guard let cred = credential, let header = authHeader else { return }
        let newValue = !isFavorite
        isFavorite = newValue
        HapticManager.impact(.light)
        Task {
            try? await client.markFavorite(credential: cred, authHeader: header, itemId: item.id, favorite: newValue)
        }
    }

    private func markEpisodeWatched(_ ep: MediaItem, watched: Bool) {
        guard let cred = credential, let header = authHeader else { return }
        Task {
            try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
            if let idx = episodes.firstIndex(where: { $0.id == ep.id }) {
                episodes[idx] = withWatchedUserData(episodes[idx], watched: watched)
            }
        }
    }

    private func withWatchedUserData(_ item: MediaItem, watched: Bool) -> MediaItem {
        var updated = item
        let old = updated.userData ?? UserData()
        updated.userData = UserData(
            playbackPositionTicks: watched ? 0 : old.playbackPositionTicks,
            playCount: watched ? old.playCount + 1 : max(0, old.playCount - 1),
            isFavorite: old.isFavorite,
            played: watched,
            playedPercentage: watched ? nil : old.playedPercentage
        )
        return updated
    }

    // MARK: - Batch watched/unwatched

    private enum WatchScope { case season, series }

    /// Marks a whole season or series watched/unwatched by looping markWatched over the
    /// episode ids already available (current season) or fetched per-season (whole series).
    /// The visible `episodes` array is updated optimistically so watched indicators refresh
    /// without a manual pull-to-refresh, matching markEpisodeWatched's single-item approach.
    private func markScopeWatched(_ scope: WatchScope, watched: Bool) {
        guard let cred = credential, let header = authHeader, let seriesId = seasonSeriesId else { return }
        HapticManager.impact(.light)
        episodes = episodes.map { withWatchedUserData($0, watched: watched) }
        Task {
            switch scope {
            case .season:
                for ep in episodes {
                    try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
                }
            case .series:
                for season in seasons {
                    let seasonEpisodes = (try? await client.getEpisodes(
                        credential: cred, authHeader: header, seriesId: seriesId, seasonId: season.id
                    )) ?? []
                    for ep in seasonEpisodes {
                        try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
                    }
                }
            }
        }
    }

    // MARK: - Similar items

    private var similarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("More Like This").padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
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
                        .zoomTransitionSource(id: sim.id, in: zoomNamespace)
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

    private func jellyfinRecommendedSection(_ category: MovieRecommendationCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(category.title).padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(category.items) { rec in
                        NavigationLink(value: rec) {
                            PosterCard(
                                title: rec.name,
                                subtitle: rec.productionYear.map { String($0) },
                                imageURL: mediaRepo.imageURL(for: rec)
                            )
                        }
#if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
#else
                        .buttonStyle(.plain)
                        .zoomTransitionSource(id: rec.id, in: zoomNamespace)
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
                LazyHStack(spacing: 10) {
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
            .font(.system(.callout, design: .default, weight: .bold))
            .foregroundStyle(DT.Color.textPrimary)
            .tracking(-0.3)
    }
}

// MARK: - Cast card

struct CastPersonCard<Placeholder: View>: View {
    let imageURL: URL?
    let name: String
    let role: String?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let imageURL {
                    RetryingAsyncImage(
                        url: imageURL,
                        logCategory: "CastPersonCard",
                        logContext: "name=\(name)",
                        content: { img in img.resizable().scaledToFill() },
                        placeholder: { placeholder() }
                    )
                } else {
                    placeholder()
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(Circle().stroke(hovered ? DT.Color.accent.opacity(0.6) : Color.white.opacity(0.1), lineWidth: hovered ? 2 : 1))
            .scaleEffect(hovered ? 1.06 : 1)

            Text(name)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let role, !role.isEmpty {
                Text(role)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 70, alignment: .top)
        .animation(DT.Animation.fast, value: hovered)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
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
                .scaledFont(size: 14)
            Text("Play")
                .scaledFont(size: 16, weight: .bold)
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
