// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI
import JellyfinAPI
import AuthCore

/// A Seerr or TMDB title on tvOS, laid out like a library title's page: the artwork across
/// the screen with the title's actions, then scores, where to watch, cast and related titles.
struct TVSeerrItemDetailView: View {
    let item: SeerrItem

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    @State private var libraryItem: MediaItem?
    @State private var openLibraryItem: MediaItem?
    @State private var detail: SeerrMediaDetail?
    @State private var certification: String?
    @State private var moreLikeThis: [SeerrItem] = []
    @State private var companyRow: (name: String, items: [SeerrItem])?
    @State private var keywordRow: (name: String, items: [SeerrItem])?
    @State private var openSeerrItem: SeerrItem?
    @State private var requestingItem: SeerrItem?
    @State private var showFullDescription = false
    @Namespace private var focusNamespace

    private var hasRequestableContent: Bool {
        guard item.mediaType == .tv, let rows = detail?.seasonRows else { return seerrRepo.matchingRequest(for: item) == nil }
        return !SeerrSeasonSelection.unrequested(rows).isEmpty
    }

    private var canRequest: Bool {
        seerrRepo.isConfigured && item.availabilityStatus != .available
            && !(item.mediaType == .movie && libraryItem != nil) && hasRequestableContent
    }

    private var statusLabel: (label: String, colorHex: String)? {
        if let status = item.availabilityStatus { return (status.label, status.colorHex) }
        return seerrRepo.matchingRequest(for: item)?.displayStatus
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    showcase(screenW: proxy.size.width)
                        .frame(height: proxy.size.height * 0.88)
                    belowFold
                        .padding(.vertical, 72)
                }
                .focusSection()
            }
            .focusScope(focusNamespace)
            .ignoresSafeArea()
        }
        .screenBackground()
        .navigationDestination(item: $openLibraryItem) { MediaDetailView(item: $0) }
        .navigationDestination(item: $openSeerrItem) { TVSeerrItemDetailView(item: $0) }
        .sheet(item: $requestingItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingItem)
        }
        .fullScreenCover(isPresented: $showFullDescription) { fullDescription }
        .task(id: item.id) {
            detail = await seerrRepo.mediaDetail(mediaType: item.mediaType, tmdbId: item.id)
        }
        .task(id: item.id) { await loadDiscovery() }
        .task(id: item.id) { await loadLibraryItem() }
        .task(id: item.id) { certification = await seerrRepo.certification(for: item) }
    }

    // MARK: - Showcase

    private func showcase(screenW: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            CachedAsyncImage(url: item.backdropURL ?? item.posterURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    LinearGradient(colors: [DT.Color.accentDeep.opacity(0.4), DT.Color.backgroundPrimary],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.5),
                .init(color: DT.Color.backgroundPrimary, location: 1),
            ], startPoint: .top, endPoint: .bottom)

            HStack(spacing: 0) {
                LinearGradient(colors: [DT.Color.backgroundPrimary.opacity(0.85), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: screenW * 0.65)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 28) {
                Text(item.title)
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.9), radius: 12)
                    .lineLimit(2)
                metaRow
                HStack(alignment: .top, spacing: 40) {
                    actions.frame(width: 300)
                    description
                    infoColumn.frame(width: 260)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 80)
        }
        .focusSection()
    }

    private var metaRow: some View {
        HStack(spacing: 12) {
            Text(item.mediaType == .tv ? "Series" : "Movie")
            if let year = item.year {
                dot
                Text(year)
            }
            if let certification, !certification.isEmpty {
                dot
                Text(certification)
                    .font(.system(size: 23, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.3), lineWidth: 1))
                    .accessibilityLabel("Rated \(certification)")
            }
            if let runtime = detail?.runtimeMinutes {
                dot
                Text("\(runtime)m")
            }
            if let rating = detail?.voteAverage, rating > 0 {
                dot
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.system(size: 16))
                    Text(String(format: "%.1f", rating)).font(.system(size: 23, weight: .bold))
                }
                .foregroundStyle(DT.Color.palette("f59e0b"))
            }
            if let statusLabel {
                Text(statusLabel.label)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(Color(hex: statusLabel.colorHex))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color(hex: statusLabel.colorHex).opacity(0.15), in: Capsule())
            }
        }
        .font(.system(size: 23))
        .foregroundStyle(.white.opacity(0.7))
    }

    private var dot: some View {
        Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3))
    }

    private var actions: some View {
        VStack(spacing: 14) {
            if canRequest {
                Button { requestingItem = item } label: {
                    TVDetailButtonLabel(icon: "plus.circle.fill", text: "Request", isPrimary: true)
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .prefersDefaultFocus(true, in: focusNamespace)
            } else if let libraryItem {
                Button { openLibraryItem = libraryItem } label: {
                    TVDetailButtonLabel(icon: "play.rectangle.fill", text: "View in Library", isPrimary: true)
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .prefersDefaultFocus(true, in: focusNamespace)
            }
            if seerrRepo.isConfigured {
                let inWatchlist = seerrRepo.isInWatchlist(item)
                Button { toggleWatchlist() } label: {
                    TVDetailButtonLabel(icon: inWatchlist ? "bookmark.fill" : "bookmark",
                                        text: inWatchlist ? "On Watchlist" : "Watchlist")
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
            }
        }
    }

    @ViewBuilder
    private var description: some View {
        if let overview = detail?.overview, !overview.isEmpty {
            Button { showFullDescription = true } label: {
                TVDescriptionLabel(text: overview)
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
        } else {
            Spacer()
        }
    }

    @ViewBuilder
    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let genres = detail?.genres, !genres.isEmpty {
                infoRow("Genre", genres.prefix(2).joined(separator: ", "))
            }
            if let cast = detail?.cast, !cast.isEmpty {
                infoRow("Starring", cast.prefix(3).map(\.name).joined(separator: ", "))
            }
            if let tagline = detail?.tagline, !tagline.isEmpty {
                infoRow("Tagline", tagline)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
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

    private var belowFold: some View {
        VStack(alignment: .leading, spacing: 56) {
            TitleInsights(tmdbId: item.id, mediaType: item.mediaType, part: .ratings)
                .padding(.horizontal, 80)
                .focusSection()
            if let seasons = detail?.seasons, !seasons.isEmpty { seasonsRow(seasons) }
            if let cast = detail?.cast, !cast.isEmpty { castRow(cast) }
            if !moreLikeThis.isEmpty { discoveryRow("More Like This", moreLikeThis) }
            if let companyRow { discoveryRow("More from \(companyRow.name)", companyRow.items) }
            if let keywordRow { discoveryRow("More About \(keywordRow.name.capitalized)", keywordRow.items) }
            TitleInsights(tmdbId: item.id, mediaType: item.mediaType, part: .details)
                .padding(.horizontal, 80)
                .focusSection()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(DT.Color.textPrimary)
            .padding(.horizontal, 80)
    }

    private func seasonsRow(_ seasons: [SeerrSeasonInfo]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Seasons")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(seasons) { season in
                        VStack(spacing: 4) {
                            Text(season.label).font(.system(size: 23, weight: .semibold))
                            if let count = season.episodeCount {
                                Text("\(count) episodes").font(.system(size: 23)).foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        .foregroundStyle(DT.Color.textPrimary)
                        .padding(.horizontal, 24).padding(.vertical, 14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DT.Radius.md))
                        .focusable()
                        .tvFocusRing(cornerRadius: DT.Radius.md)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }

    private func castRow(_ cast: [SeerrCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Cast")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(cast.prefix(20)) { member in
                        VStack(spacing: 8) {
                            CachedAsyncImage(url: member.profileURL) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: DT.Color.backgroundSecondary
                                }
                            }
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                            Text(member.name)
                                .font(.system(size: 23, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            if let character = member.character {
                                Text(character)
                                    .font(.system(size: 23))
                                    .foregroundStyle(DT.Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 150)
                        .focusable()
                        .tvFocusRing(cornerRadius: DT.Radius.md)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }

    private func discoveryRow(_ title: String, _ items: [SeerrItem]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { related in
                        Button { openSeerrItem = related } label: {
                            PosterCard(title: related.title, subtitle: related.year,
                                       imageURL: related.backdropURL ?? related.posterURL)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 20)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }

    private var fullDescription: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(item.title)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(detail?.overview ?? "")
                        .font(.system(size: 26))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineSpacing(8)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Close") { showFullDescription = false }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .tvFocusRing(cornerRadius: DT.Radius.md)
                }
                .padding(80)
            }
        }
    }

    // MARK: - Load

    private func toggleWatchlist() {
        Task {
            if seerrRepo.isInWatchlist(item) {
                try? await seerrRepo.removeFromWatchlist(item)
            } else {
                try? await seerrRepo.addToWatchlist(item)
            }
        }
    }

    private func loadLibraryItem() async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        libraryItem = try? await JellyfinMediaClient().findItem(
            credential: cred, authHeader: header, tmdbId: item.id, isSeries: item.mediaType == .tv,
            title: item.title, year: item.year.flatMap { Int($0.prefix(4)) })
    }

    private func loadDiscovery() async {
        async let related = seerrRepo.relatedMedia(mediaType: item.mediaType, mediaId: item.id)
        async let info = seerrRepo.relatedInfo(mediaType: item.mediaType, tmdbId: item.id)
        moreLikeThis = Array(await related.filter { $0.id != item.id }.prefix(20))
        guard let info = await info else { return }
        if let company = info.companies.first {
            let items = await seerrRepo.discoverByCompany(company.id, mediaType: item.mediaType).filter { $0.id != item.id }
            if items.count >= 3 { companyRow = (company.name, Array(items.prefix(20))) }
        }
        if item.mediaType == .movie, let keyword = info.keywords.first {
            let items = await seerrRepo.discoverByKeyword(keyword.id).filter { $0.id != item.id }
            if items.count >= 3 { keywordRow = (keyword.name, Array(items.prefix(20))) }
        }
    }
}
