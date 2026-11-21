// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI
import JellyfinAPI

struct SeerrView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var model = SeerrDiscoverModel()
    @State private var review = SeerrRequestReview()

    private var trendingForType: [SeerrItem] { model.trending(in: seerrRepo) }

    private var showsTrending: Bool { model.showsTrending(in: seerrRepo) }

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
            .seerrRequestReview(review)
            .navigationDestination(for: SeerrItem.self) { SeerrItemDetailView(item: $0) }
            .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
            .navigationDestination(for: SeerrGenre.self) { genre in
                TVSeerrGridView(title: genre.name) {
                    await seerrRepo.discoverByGenre(genre.id, mediaType: model.mediaType)
                }
            }
        }
        .task(id: seerrRepo.isConfigured) {
            guard seerrRepo.isConfigured else { return }
            await model.load(seerrRepo: seerrRepo)
            await seerrRepo.loadRequests()
        }
        .task(id: model.mediaType) { await model.loadLanguageItems(seerrRepo: seerrRepo) }
    }

    @ViewBuilder
    private func requestMenu(_ req: SeerrRequestItem) -> some View {
        SeerrRequestReviewMenu(request: req, review: review)
        if seerrRepo.canRemove(req) {
            Button(role: .destructive) { review.removing = req } label: {
                Label("Remove Request", systemImage: "trash")
            }
        }
    }

    // MARK: - Auth failed

    private var authFailedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(DT.Color.palette("F43F5E"))
            Text("Authentication Failed")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            SeerrSettingsHint.signInFailed
                .font(.system(size: 23))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            Button("Try Again") {
                Task { await seerrRepo.retrySignIn() }
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
            Text("Add your Seerr server in Settings › Plugins › Seerr.")
                .font(.system(size: 23))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Something has to take focus, or it falls to the tab bar, where Back leaves the app.
        .focusable()
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
                    tvShelf(title: showsTrending ? String(localized: "Trending Now") : String(localized: "Popular"), items: trendingForType)
                }
                let upcoming = model.upcoming(in: seerrRepo)
                if !upcoming.isEmpty {
                    tvShelf(title: String(localized: "Upcoming"), items: upcoming)
                }
                let popular = model.popular(in: seerrRepo)
                if showsTrending, !popular.isEmpty {
                    tvShelf(title: model.mediaType == .tv ? String(localized: "Popular Series") : String(localized: "Popular Movies"), items: popular)
                }
                if !model.languageItems.isEmpty, let name = model.languageName {
                    tvShelf(title: String(localized: "Popular in \(name)"), items: model.languageItems)
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
            Picker("Media Type", selection: $model.mediaType) {
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
                Task { await seerrRepo.retrySignIn() }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
    }

    // MARK: - Genres

    @ViewBuilder
    private var genreRow: some View {
        let genres = model.genres(in: seerrRepo)
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
                Text(seerrRepo.canManageRequests ? "Requests" : "My Requests")
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
                                TVRequestRow(req: req, requester: seerrRepo.requesterName(of: req))
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            // Press and hold to approve, decline or remove.
                            .contextMenu { requestMenu(req) }
                        } else {
                            TVRequestRow(req: req, requester: seerrRepo.requesterName(of: req))
                                .focusable()
                                .contextMenu { requestMenu(req) }
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
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.isFocused) private var isFocused

    // Matched by tmdbId, not title — see SeerrRepository.matchingRequest.
    private var matchingRequest: SeerrRequestItem? {
        mediaRepo.hasInLibrary(item) ? nil : seerrRepo.matchingRequest(for: item)
    }

    private var badge: (label: String, colorHex: String)? {
        if mediaRepo.hasInLibrary(item) { return (String(localized: "Available"), "10b981") }
        return matchingRequest?.localizedDisplayStatus
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
    var requester: String?
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
                if let requester {
                    Label("Requested by \(requester)", systemImage: "person")
                        .font(.system(size: 21))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
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
        let hex = switch status {
        case .approved, .completed: "10b981"
        case .declined, .failed: "F43F5E"
        case .pending: "f59e0b"
        }
        return pillView(label: status.localizedLabel, hex: hex)
    }

    private func mediaStatusPill(_ status: SeerrAvailabilityStatus) -> some View {
        pillView(label: status.localizedLabel, hex: status.colorHex)
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
