// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore

struct SearchView: View {
    @Binding var query: String

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var jellyfinResults: [MediaItem] = []
    @State private var seerrResults: [SeerrItem] = []
    @State private var isSearchingLibrary = false
    @State private var isSearchingDiscover = false
    @State private var searchTask: Task<Void, Never>?
    @State private var requestingSeerrItem: SeerrItem?
    @AppStorage("recentSearches") private var recentSearchesData = Data()
    @AppStorage("saveSearchHistory") private var saveSearchHistory = true

    private static let maxRecentSearches = 8

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    private func saveRecentSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard saveSearchHistory, trimmed.count >= 2 else { return }
        var updated = recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        recentSearchesData = (try? JSONEncoder().encode(Array(updated.prefix(Self.maxRecentSearches)))) ?? Data()
    }

    private var recentSearchesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                HStack {
                    Text("Recent")
                        .font(DT.Font.cardTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Clear") { recentSearchesData = Data() }
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                }
                ForEach(recentSearches, id: \.self) { term in
                    Button { query = term } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(DT.Color.textSecondary)
                                .accessibilityHidden(true)
                            Text(term)
                                .font(.system(.body))
                                .foregroundStyle(DT.Color.textPrimary)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    #if os(tvOS)
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .tvFocusRing(cornerRadius: DT.Radius.md)
                    #else
                    .buttonStyle(.plain)
                    #endif
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 12)
        }
    }

    var body: some View {
        Group {
            if query.isEmpty, !recentSearches.isEmpty {
                recentSearchesList
            } else if query.isEmpty {
                ContentUnavailableView(
                    "Search",
                    systemImage: "magnifyingglass",
                    description: Text("Find movies, shows, and more.")
                )
            } else if !isSearchingLibrary && !isSearchingDiscover && jellyfinResults.isEmpty && seerrResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DT.Spacing.xl) {
                        if let top = jellyfinResults.first {
                            topResult(top)
                        } else if isSearchingLibrary {
                            searchingRow("Searching your library…")
                        }
                        ForEach(libraryGroups, id: \.title) { group in
                            libraryShelf(group)
                        }
                        if seerrRepo.isConfigured && (isSearchingDiscover || !seerrResults.isEmpty) {
                            discoverSection
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .animation(DT.Animation.fast, value: jellyfinResults)
                    .animation(DT.Animation.fast, value: seerrResults)
                }
            }
        }
        .screenBackground()
        .onChange(of: query) { _, newValue in
            performSearch(query: newValue)
        }
        .sheet(item: $requestingSeerrItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingSeerrItem)
                // presentationDetents is a portrait card-sheet concept sized for iPhone/iPad —
                // forcing it onto tvOS's differently shaped modal container clips the content
                // at both edges (see the same fix on the player's sheets). tvOS falls back to
                // its own default sheet presentation here.
                #if !os(tvOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                #endif
        }
    }

    private func searchingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .font(.system(.subheadline))
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(DT.Font.sectionTitle)
                .foregroundStyle(DT.Color.textPrimary)
            if let count {
                Text("\(count)")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    // MARK: - Library

    private struct LibraryGroup {
        let title: String
        let items: [MediaItem]
        let isLandscape: Bool
    }

    /// Everything after the top result, by kind, in the server's order of relevance.
    private var libraryGroups: [LibraryGroup] {
        let rest = Array(jellyfinResults.dropFirst())
        let groups = [
            LibraryGroup(title: "Movies", items: rest.filter { $0.type == .movie }, isLandscape: false),
            LibraryGroup(title: "Shows", items: rest.filter { $0.type == .series }, isLandscape: false),
            LibraryGroup(title: "Episodes", items: rest.filter { $0.type == .episode }, isLandscape: true),
            LibraryGroup(title: "Collections", items: rest.filter { ![.movie, .series, .episode].contains($0.type) }, isLandscape: false),
        ]
        return groups.filter { !$0.items.isEmpty }
    }

    private func kindLabel(_ item: MediaItem) -> String {
        switch item.type {
        case .movie: "Movie"
        case .series: "Show"
        case .episode: "Episode"
        case .boxSet: "Collection"
        default: "Title"
        }
    }

    private func episodeCode(_ item: MediaItem) -> String? {
        guard let s = item.parentIndexNumber, let e = item.indexNumber else { return nil }
        return "S\(s)E\(e)"
    }

    private func topResult(_ item: MediaItem) -> some View {
        let details = [kindLabel(item), item.seriesName, episodeCode(item), item.productionYear.map(String.init)].compactMap { $0 }
        return NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                RetryingAsyncImage(
                    url: mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1000) ?? posterImageURL(for: item),
                    logCategory: "SearchView", logContext: "top result item=\(item.name)",
                    content: { $0.resizable().scaledToFill() },
                    placeholder: { DT.Color.backgroundTertiary })
                .frame(maxWidth: .infinity)
                .frame(height: Self.topResultHeight)
                .clipped()
                .allowsHitTesting(false)

                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 4) {
                    Text("TOP RESULT")
                        .font(.system(.caption2, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(item.name)
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(details.joined(separator: " · "))
                        .font(.system(.footnote, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(DT.Spacing.md)
            }
            .frame(height: Self.topResultHeight)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Top result: \(item.name), \(details.joined(separator: ", "))")
        }
        .modifier(ResultButtonStyle())
        .simultaneousGesture(TapGesture().onEnded { saveRecentSearch(query) })
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private func libraryShelf(_ group: LibraryGroup) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            sectionHeader(group.title, count: group.items.count)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Self.shelfSpacing) {
                    ForEach(group.items) { item in
                        NavigationLink(value: item) {
                            if group.isLandscape {
                                SearchResultCard(title: item.name,
                                                 subtitle: [item.seriesName, episodeCode(item)].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                                                 imageURL: mediaRepo.episodeThumbnailURL(for: item, fillWidth: 480) ?? posterImageURL(for: item),
                                                 aspectRatio: 16 / 9)
                                    .frame(width: Self.landscapeWidth)
                            } else {
                                SearchResultCard(title: item.name, subtitle: item.productionYear.map { String($0) },
                                                 imageURL: posterImageURL(for: item))
                                    .frame(width: Self.posterWidth)
                            }
                        }
                        .modifier(ResultButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded { saveRecentSearch(query) })
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                #if os(tvOS)
                .padding(.vertical, 30)
                #endif
            }
            .shelfScrollButtons()
            #if os(tvOS)
            .scrollClipDisabled()
            #endif
        }
    }

    #if os(tvOS)
    private static let topResultHeight: CGFloat = 420
    private static let posterWidth: CGFloat = 220
    private static let landscapeWidth: CGFloat = 400
    private static let shelfSpacing: CGFloat = 40
    private static let discoverPosterWidth: CGFloat = 120
    #elseif os(macOS)
    private static let topResultHeight: CGFloat = 300
    private static let posterWidth: CGFloat = 150
    private static let landscapeWidth: CGFloat = 300
    private static let shelfSpacing: CGFloat = 16
    private static let discoverPosterWidth: CGFloat = 80
    #else
    private static let topResultHeight: CGFloat = 210
    private static let posterWidth: CGFloat = 112
    private static let landscapeWidth: CGFloat = 220
    private static let shelfSpacing: CGFloat = 12
    private static let discoverPosterWidth: CGFloat = 64
    #endif

    /// An episode's own Primary image is a landscape screenshot — forced into this grid's
    /// portrait 2:3 cards it rendered badly (cards visually collided). Episodes use their
    /// series' portrait poster here instead, same as any other result.
    private func posterImageURL(for item: MediaItem) -> URL? {
        guard item.type == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag,
              let base = mediaRepo.baseURL, let token = mediaRepo.accessToken
        else { return mediaRepo.imageURL(for: item) }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: seriesId, tag: tag, type: .primary, fillWidth: 300, token: token)
    }

    // MARK: - Discover (Seerr)

    /// What's already on the server last: those are mostly in the library results above.
    private var discoverResults: [SeerrItem] {
        seerrResults.filter { $0.availabilityStatus != .available } + seerrResults.filter { $0.availabilityStatus == .available }
    }

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(DT.Color.onAccent)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Discover")
                        .font(DT.Font.sectionTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("Not in your library yet · from Seerr")
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer(minLength: 0)
                if isSearchingDiscover { ProgressView() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(discoverResults.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(DT.Color.textPrimary.opacity(0.06))
                            .padding(.leading, Self.discoverPosterWidth + DT.Spacing.sm)
                    }
                    discoverRow(item)
                }
            }
        }
        .padding(DT.Spacing.md)
        .background(
            LinearGradient(colors: [DT.Color.accent.opacity(0.12), DT.Color.backgroundSecondary.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous)
            .stroke(DT.Color.accent.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    @ViewBuilder
    private func discoverRow(_ item: SeerrItem) -> some View {
        #if os(tvOS)
        NavigationLink(value: item) { discoverRowContent(item) }
            .modifier(ResultButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { saveRecentSearch(query) })
        #else
        Button {
            saveRecentSearch(query)
            requestingSeerrItem = item
        } label: { discoverRowContent(item) }
        .buttonStyle(PressableButtonStyle())
        #endif
    }

    private func discoverRowContent(_ item: SeerrItem) -> some View {
        HStack(alignment: .center, spacing: DT.Spacing.sm) {
            RetryingAsyncImage(
                url: item.posterURL, logCategory: "SearchView", logContext: "discover item=\(item.title)",
                content: { $0.resizable().scaledToFill() },
                placeholder: { DT.Color.backgroundTertiary })
            .frame(width: Self.discoverPosterWidth, height: Self.discoverPosterWidth * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                Text([item.mediaType == .movie ? "Movie" : "Show", item.year].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(DT.Color.textSecondary)
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            discoverStatus(item)
        }
        .padding(.vertical, DT.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.availabilityStatus == nil ? "Request from Seerr" : "")
    }

    /// Request for anything Seerr hasn't heard of; otherwise where it is.
    @ViewBuilder
    private func discoverStatus(_ item: SeerrItem) -> some View {
        if let status = item.availabilityStatus, status != .unknown {
            Text(status == .pending || status == .processing ? "Requested" : status.label)
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(DT.Color.palette(status.colorHex))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(DT.Color.palette(status.colorHex).opacity(0.15), in: Capsule())
        } else {
            Text("Request")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(DT.Color.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(DT.Color.accent, in: Capsule())
        }
    }

    /// Waits for a short pause in typing, and drops any search still running for an older
    /// query: every keystroke used to fire both servers, and a slow response for "the" could
    /// land after the one for "the office" and replace the right results with stale ones.
    private func performSearch(query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            jellyfinResults = []
            seerrResults = []
            isSearchingLibrary = false
            isSearchingDiscover = false
            return
        }
        isSearchingLibrary = true
        isSearchingDiscover = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            // Each server's results show as they arrive, so a slow one doesn't hold up the other.
            await withDiscardingTaskGroup { group in
                group.addTask { @MainActor in
                    let jellyfin = await mediaRepo.searchIfAuthenticated(
                        query: query,
                        authState: authManager.state,
                        authClient: authManager.authClient
                    )
                    guard !Task.isCancelled else { return }
                    jellyfinResults = jellyfin
                    isSearchingLibrary = false
                }
                group.addTask { @MainActor in
                    let seerr = await seerrRepo.search(query: query)
                    guard !Task.isCancelled else { return }
                    seerrResults = seerr
                    isSearchingDiscover = false
                }
            }
        }
    }
}

// MARK: - Grid card

private struct SearchResultCard: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    var aspectRatio: CGFloat = 2 / 3

    @State private var hovered = false
    @Environment(\.isFocused) private var isFocused

    private var highlighted: Bool { hovered || isFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RetryingAsyncImage(
                    url: imageURL, logCategory: "SearchView", logContext: "result item=\(title)",
                    content: { $0.resizable().scaledToFill() },
                    placeholder: { DT.Color.backgroundSecondary })
                .clipped()
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .stroke(isFocused ? DT.Color.accent : (hovered ? DT.Color.accent.opacity(0.35) : DT.Color.textPrimary.opacity(0.06)),
                            lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? 1.06 : (hovered ? 1.03 : 1))
            .shadow(color: highlighted ? DT.Color.accent.opacity(isFocused ? 0.4 : 0.2) : .clear, radius: highlighted ? 12 : 0)

            Text(title)
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .animation(DT.Animation.fast, value: highlighted)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
    }
}

/// Pressable on touch and pointer, a focus card on tvOS.
private struct ResultButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
        #else
        content.buttonStyle(PressableButtonStyle())
        #endif
    }
}
