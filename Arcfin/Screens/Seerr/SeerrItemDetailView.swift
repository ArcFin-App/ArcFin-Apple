// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI
import JellyfinAPI

/// Full detail for a Discover item — tapping a poster used to do nothing at all (only the
/// small in-card Request button had any action). This is that missing destination: overview,
/// cast, seasons, availability, and Request/Watchlist actions, same data source
/// (SeerrRepository.mediaDetail) SeerrRequestDetailView already uses for an existing request.
struct SeerrItemDetailView: View {
    let item: SeerrItem

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    /// The server's own copy of this title, when it has one — drives the "View in Library"
    /// action that takes the place of Request once there's nothing left to request.
    @State private var libraryItem: MediaItem?
    @State private var openLibraryItem: MediaItem?
    @State private var detail: SeerrMediaDetail?
    @State private var isLoadingDetail = false
    @State private var requestingItem: SeerrItem? = nil
    @State private var requestBounceTrigger = 0
    #if os(iOS)
    // YouTubeTrailerPlayerView is UIKit-only — see MediaDetailView's own note on the same gap.
    @State private var showTrailer = false
    #endif

    private var alreadyRequested: Bool {
        seerrRepo.matchingRequest(for: item) != nil
    }

    /// A blunt title match above is all the detail screen's basic SeerrItem gives us for a
    /// movie, but a series' full detail (once loaded) carries real per-season status — this
    /// used to hide the Request button entirely the moment ANY request existed for the title,
    /// even if only one of several seasons had been asked for. Falls back to the title match
    /// before the detail fetch resolves, same as before this existed.
    private var hasRequestableContent: Bool {
        guard item.mediaType == .tv, let rows = detail?.seasonRows else { return !alreadyRequested }
        return !SeerrSeasonSelection.unrequested(rows).isEmpty
    }

    private var isAvailable: Bool { item.availabilityStatus == .available }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                titleBlock
                actionButtons
                trailerButton

                VStack(alignment: .leading, spacing: DT.Spacing.md) {
                    if let genres = detail?.genres, !genres.isEmpty {
                        Text(genres.joined(separator: " · "))
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    if let availabilityStatus = item.availabilityStatus {
                        availabilityRow(label: "Availability", status: (availabilityStatus.label, availabilityStatus.colorHex))
                    } else if let request = seerrRepo.matchingRequest(for: item) {
                        availabilityRow(label: "Request", status: request.displayStatus)
                    }

                    if isLoadingDetail {
                        ProgressView().frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let tagline = detail?.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.system(.caption, design: .default, weight: .medium))
                            .italic()
                            .foregroundStyle(DT.Color.accent)
                    }

                    if let overview = detail?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(.footnote))
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineSpacing(3)
                    }

                    if let seasons = detail?.seasons, !seasons.isEmpty {
                        seasonsRow(seasons)
                    }

                    if let cast = detail?.cast, !cast.isEmpty {
                        castRow(cast)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.md)

                Spacer().frame(height: DT.Size.tabBarHeight + 24)
            }
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .sheet(item: $requestingItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .navigationDestination(item: $openLibraryItem) { MediaDetailView(item: $0) }
        .task {
            isLoadingDetail = true
            detail = await seerrRepo.mediaDetail(mediaType: item.mediaType, tmdbId: item.id)
            isLoadingDetail = false
        }
        .task { await loadLibraryItem() }
    }

    private var statusPillText: String {
        if isAvailable { return "Available" }
        let status = item.availabilityStatus?.label ?? seerrRepo.matchingRequest(for: item)?.displayStatus.label
        return status.map { "Requested · \($0)" } ?? "Requested"
    }

    private func loadLibraryItem() async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        libraryItem = try? await JellyfinMediaClient().findItem(
            credential: cred, authHeader: header, tmdbId: item.id, isSeries: item.mediaType == .tv)
    }

    // MARK: - Actions (positioned and styled like MediaDetailView's playButton/trailerButton)

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if !isAvailable && hasRequestableContent {
                Button {
                    requestBounceTrigger += 1
                    requestingItem = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(.subheadline))
                            .symbolEffect(.bounce, value: requestBounceTrigger)
                        Text("Request")
                            .font(.system(.callout, design: .default, weight: .bold))
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
                .buttonStyle(PressableButtonStyle())
            } else if let libraryItem {
                Button {
                    openLibraryItem = libraryItem
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(.subheadline))
                        Text("View in Library")
                            .font(.system(.callout, design: .default, weight: .bold))
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
                .buttonStyle(PressableButtonStyle())
            } else {
                // Requested but not in the library yet (or not matchable): keep the row's
                // shape instead of leaving the bookmark button stranded on its own.
                HStack(spacing: 8) {
                    Image(systemName: isAvailable ? "checkmark.circle" : "clock")
                        .font(.system(.subheadline))
                    Text(statusPillText)
                        .font(.system(.callout, design: .default, weight: .semibold))
                }
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DT.Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.08), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }

            Button {
                toggleWatchlist()
            } label: {
                Image(systemName: seerrRepo.isInWatchlist(item) ? "bookmark.fill" : "bookmark")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(DT.Color.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.08), lineWidth: 1))
                    .symbolEffect(.bounce, value: seerrRepo.isInWatchlist(item))
            }
            .accessibilityLabel(seerrRepo.isInWatchlist(item) ? "Remove from watchlist" : "Add to watchlist")
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    @ViewBuilder
    private var trailerButton: some View {
        #if os(iOS)
        if let key = detail?.trailerYouTubeKey {
            Button {
                showTrailer = true
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
            .fullScreenCover(isPresented: $showTrailer) {
                YouTubeTrailerPlayerView(videoID: key, title: item.title)
            }
        }
        #endif
    }

    private func toggleWatchlist() {
        HapticManager.impact(.light)
        Task {
            if seerrRepo.isInWatchlist(item) {
                try? await seerrRepo.removeFromWatchlist(item)
            } else {
                try? await seerrRepo.addToWatchlist(item)
            }
        }
    }

    private func seasonsRow(_ seasons: [SeerrSeasonInfo]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Seasons")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        VStack(spacing: 2) {
                            Text(season.label)
                                .font(.system(.caption2, design: .default, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                            if let count = season.episodeCount {
                                Text("\(count) episodes")
                                    .font(.system(.caption2))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
                    }
                }
            }
        }
    }

    private func castRow(_ cast: [SeerrCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cast")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cast.prefix(12)) { member in
                        VStack(spacing: 4) {
                            AsyncImage(url: member.profileURL) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: DT.Color.backgroundSecondary
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())

                            Text(member.name)
                                .font(.system(.caption2, design: .default, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(1)
                            if let character = member.character {
                                Text(character)
                                    .font(.system(.caption2))
                                    .foregroundStyle(DT.Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 64)
                    }
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            if let url = item.backdropURL ?? item.posterURL {
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
            if let url = item.posterURL {
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
                Text(item.title)
                    .font(.system(.title3, design: .default, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text(item.mediaType == .tv ? "Series" : "Movie")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    if let year = item.year {
                        Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.2))
                        Text(year)
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    if let runtime = detail?.runtimeMinutes {
                        Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.2))
                        Text("\(runtime) min")
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    if let rating = detail?.voteAverage, rating > 0 {
                        Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.2))
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(.caption2))
                            Text(String(format: "%.1f", rating))
                        }
                        .font(.system(.caption2))
                        .foregroundStyle(Color(hex: "f59e0b"))
                    }
                }
                // Lets HStack compress/truncate these Text children when every optional
                // field is present at once, instead of overflowing past the screen edge —
                // same fix as MediaDetailView.metaRow.
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, -50)
        .padding(.bottom, DT.Spacing.md)
    }

    private func availabilityRow(label: String, status: (label: String, colorHex: String)) -> some View {
        HStack {
            Text(label)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
            Text(status.label)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(Color(hex: status.colorHex))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(hex: status.colorHex).opacity(0.15))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(hex: status.colorHex).opacity(0.3), lineWidth: 1))
        }
        .padding(12)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }
}
