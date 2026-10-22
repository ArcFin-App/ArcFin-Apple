// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(tvOS)
import SwiftUI
import SeerrAPI
import JellyfinAPI

struct TVSeerrView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var mediaType: RequestMediaType = .movie
    @State private var languageItems: [SeerrItem] = []

    private var trendingForType: [SeerrItem] {
        let trending = seerrRepo.trending.filter { $0.mediaType == mediaType }
        return trending.isEmpty ? (mediaType == .tv ? seerrRepo.popularTV : seerrRepo.popularMovies) : trending
    }

    private var showsTrending: Bool { seerrRepo.trending.contains { $0.mediaType == mediaType } }

    private var deviceLanguage: String? {
        guard let code = Locale.current.language.languageCode?.identifier, code != "en" else { return nil }
        return code
    }

    var body: some View {
        NavigationStack {
            Group {
                if !seerrRepo.isConfigured {
                    notConfiguredView
                } else if seerrRepo.authFailed {
                    authFailedView
                } else {
                    mainContent
                }
            }
            .screenBackground()
            .navigationDestination(for: SeerrItem.self) { TVSeerrItemDetailView(item: $0) }
            .navigationDestination(for: MediaItem.self) { TVMediaDetailView(item: $0) }
            .navigationDestination(for: SeerrGenre.self) { genre in
                TVSeerrGridView(title: genre.name) {
                    await seerrRepo.discoverByGenre(genre.id, mediaType: mediaType)
                }
            }
        }
        .task(id: seerrRepo.isConfigured) {
            guard seerrRepo.isConfigured else { return }
            async let discover: Void = seerrRepo.loadDiscover()
            async let genres: Void = seerrRepo.loadGenres()
            async let upcoming: Void = seerrRepo.loadUpcoming()
            async let watchlist: Void = seerrRepo.loadWatchlist()
            _ = await (discover, genres, upcoming, watchlist)
            await seerrRepo.loadRequests()
        }
        .task(id: mediaType) {
            guard let deviceLanguage else { return }
            languageItems = await seerrRepo.discoverByLanguage(deviceLanguage, mediaType: mediaType)
        }
    }

    // MARK: - Auth failed

    private var authFailedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(DT.Color.palette("EF4444"))
            Text("Authentication Failed")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Check your Seerr credentials in Settings → Plugins → Seerr.")
                .font(.system(size: 23))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            Button("Try Again") {
                seerrRepo.clearAuthFailure()
                Task { await seerrRepo.loadDiscover() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Not configured

    private var notConfiguredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill")
                .font(.system(size: 64))
                .foregroundStyle(DT.Color.accent)
            Text("Seerr Not Connected")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Add your Seerr server in Settings → Plugins → Seerr.")
                .font(.system(size: 23))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topRow
                    .padding(.horizontal, 80)
                    .padding(.bottom, 40)
                    .focusSection()

                if trendingForType.isEmpty, !seerrRepo.isLoadingDiscover, let error = seerrRepo.discoverError {
                    errorCard(error)
                        .padding(.horizontal, 80)
                        .padding(.bottom, 40)
                } else if !trendingForType.isEmpty {
                    tvShelf(title: showsTrending ? "Trending Now" : "Popular", items: trendingForType)
                }
                let upcoming = mediaType == .tv ? seerrRepo.upcomingTV : seerrRepo.upcomingMovies
                if !upcoming.isEmpty {
                    tvShelf(title: "Upcoming", items: upcoming)
                }
                let popular = mediaType == .tv ? seerrRepo.popularTV : seerrRepo.popularMovies
                if showsTrending, !popular.isEmpty {
                    tvShelf(title: mediaType == .tv ? "Popular Series" : "Popular Movies", items: popular)
                }
                if !languageItems.isEmpty, let deviceLanguage,
                   let name = Locale.current.localizedString(forLanguageCode: deviceLanguage) {
                    tvShelf(title: "Popular in \(name)", items: languageItems)
                }
                genreRow

                requestsSection
                    .padding(.top, 16)
            }
            .padding(.vertical, 48)
            .focusSection()
        }
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(spacing: 20) {
            Picker("Media Type", selection: $mediaType) {
                Text("Movies").tag(RequestMediaType.movie)
                Text("Series").tag(RequestMediaType.tv)
            }
            .pickerStyle(.segmented)
            .frame(width: 420)

            NavigationLink {
                TVSeerrSearchView()
            } label: {
                pillLabel("Search", systemImage: "magnifyingglass")
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .tvFocusRing(cornerRadius: DT.Radius.pill)

            NavigationLink {
                WatchlistView()
            } label: {
                pillLabel("Watchlist", systemImage: "bookmark.fill")
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .tvFocusRing(cornerRadius: DT.Radius.pill)
        }
    }

    private func pillLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 23, weight: .semibold))
        .foregroundStyle(DT.Color.textPrimary)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't load Discover from Seerr", systemImage: "exclamationmark.triangle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
            Text(message)
                .font(.system(size: 23))
                .foregroundStyle(DT.Color.textSecondary)
            Button("Try Again") {
                seerrRepo.clearAuthFailure()
                Task { await seerrRepo.loadDiscover() }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
    }

    // MARK: - Genres

    @ViewBuilder
    private var genreRow: some View {
        let genres = mediaType == .tv ? seerrRepo.tvGenres : seerrRepo.movieGenres
        if !genres.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Genres")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .padding(.horizontal, 80)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(genres) { genre in
                            NavigationLink(value: genre) {
                                pillLabel(genre.name, systemImage: "theatermasks")
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .tvFocusRing(cornerRadius: DT.Radius.pill)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 12)
                }
                .scrollClipDisabled()
            }
            .padding(.bottom, 40)
            .focusSection()
        }
    }

    // MARK: - Discover shelf

    private func tvShelf(title: String, items: [SeerrItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            TVSeerrCard(item: item)
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
        .padding(.bottom, 40)
        .focusSection()
    }

    // MARK: - My Requests

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My Requests")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                if seerrRepo.isLoadingRequests {
                    ProgressView().padding(.leading, 8)
                } else if !seerrRepo.requests.isEmpty {
                    Text("\(seerrRepo.requests.count)")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(DT.Color.accent.opacity(0.3)))
                        .overlay(Capsule().stroke(DT.Color.accent.opacity(0.5), lineWidth: 1))
                }
            }
            .padding(.horizontal, 80)

            if seerrRepo.requests.isEmpty && !seerrRepo.isLoadingRequests {
                ContentUnavailableView(
                    "No Requests",
                    systemImage: "clock",
                    description: Text("Your media requests will appear here.")
                )
                .frame(height: 260)
            } else {
                VStack(spacing: 12) {
                    ForEach(seerrRepo.requests) { req in
                        if let tmdbId = req.tmdbId {
                            NavigationLink(value: SeerrItem(
                                id: tmdbId, title: req.mediaTitle, mediaType: req.mediaType,
                                posterPath: req.posterPath, backdropPath: req.backdropPath,
                                availabilityStatus: req.mediaStatus)) {
                                TVRequestRow(req: req)
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                        } else {
                            TVRequestRow(req: req).focusable()
                        }
                    }
                }
                .padding(.horizontal, 80)
                .focusSection()
            }
        }
    }
}

// MARK: - Search

/// Seerr's search, with the system's tvOS search keyboard.
struct TVSeerrSearchView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @State private var query = ""
    @State private var results: [SeerrItem] = []

    var body: some View {
        TVSeerrResultsGrid(items: results)
            .searchable(text: $query, prompt: "Movies and series")
            .screenBackground()
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let found = await seerrRepo.search(query: trimmed)
                guard !Task.isCancelled else { return }
                results = found
            }
    }
}

/// Titles from one Seerr list, in a grid — a genre, for now.
struct TVSeerrGridView: View {
    let title: String
    let load: () async -> [SeerrItem]
    @State private var items: [SeerrItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TVSeerrResultsGrid(items: items, title: title)
            }
        }
        .screenBackground()
        .task {
            items = await load()
            isLoading = false
        }
    }
}

private struct TVSeerrResultsGrid: View {
    let items: [SeerrItem]
    var title: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let title {
                    Text(title)
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(DT.Color.textPrimary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DT.Size.posterCard.width), spacing: 40)], spacing: 48) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            TVSeerrCard(item: item)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
            }
            .padding(80)
        }
    }
}

// MARK: - Seerr discover card

private struct TVSeerrCard: View {
    let item: SeerrItem
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.isFocused) private var isFocused

    // Matched by tmdbId, not title — see SeerrRepository.matchingRequest.
    private var matchingRequest: SeerrRequestItem? {
        item.availabilityStatus == .available ? nil : seerrRepo.matchingRequest(for: item)
    }

    private var badge: (label: String, colorHex: String)? {
        if item.availabilityStatus == .available { return ("Available", "10b981") }
        return matchingRequest?.displayStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                CachedAsyncImage(url: item.backdropURL ?? item.posterURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        LinearGradient(
                            colors: [DT.Color.accentDeep.opacity(0.4), DT.Color.backgroundSecondary],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(width: DT.Size.posterCard.width, height: DT.Size.posterCard.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3)
                )
                .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 10)
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)

                if let badge {
                    let color = Color(hex: badge.colorHex)
                    Text(badge.label)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(color.opacity(0.2))
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let year = item.year {
                    Text(year)
                        .scaledFont(size: 10, weight: .medium)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                Text(item.title)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
            }
            .frame(width: DT.Size.posterCard.width, height: 84, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Request row

private struct TVRequestRow: View {
    let req: SeerrRequestItem
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 20) {
            CachedAsyncImage(url: req.backdropURL ?? req.posterURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: DT.Radius.sm)
                        .fill(DT.Color.backgroundTertiary)
                }
            }
            .frame(width: 192, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))

            VStack(alignment: .leading, spacing: 8) {
                Text(req.mediaTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text(req.mediaType == .tv ? "Series" : "Movie")
                        .font(.system(size: 23))
                        .foregroundStyle(DT.Color.textSecondary)

                    Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.2))

                    Text(req.requestedAt, style: .date)
                        .font(.system(size: 23))
                        .foregroundStyle(DT.Color.textSecondary)

                    statusPill(req.status)
                    if let mediaStatus = req.mediaStatus {
                        mediaStatusPill(mediaStatus)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .fill(isFocused ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .stroke(isFocused ? DT.Color.accent.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }

    private func statusPill(_ status: RequestStatus) -> some View {
        let (label, hex): (String, String) = switch status {
        case .approved:  ("Approved",  "10b981")
        case .declined:  ("Declined",  "EF4444")
        case .pending:   ("Pending",   "f59e0b")
        }
        return pillView(label: label, hex: hex)
    }

    private func mediaStatusPill(_ status: SeerrAvailabilityStatus) -> some View {
        pillView(label: status.label, hex: status.colorHex)
    }

    private func pillView(label: String, hex: String) -> some View {
        Text(label)
            .font(.system(size: 23, weight: .bold))
            .foregroundStyle(DT.Color.palette(hex))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(DT.Color.palette(hex).opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DT.Color.palette(hex).opacity(0.3), lineWidth: 1))
    }
}
#endif
