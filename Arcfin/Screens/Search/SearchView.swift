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
    @State private var isSearching = false
    @State private var requestingSeerrItem: SeerrItem?
    @AppStorage("recentSearches") private var recentSearchesData = Data()

    private static let maxRecentSearches = 8

    private var recentSearches: [String] {
        (try? JSONDecoder().decode([String].self, from: recentSearchesData)) ?? []
    }

    private func saveRecentSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 12)
        }
    }

    private var columns: [GridItem] {
#if os(macOS)
        // Fixed 3-up leaves a resizable Mac window either cramped or with cards
        // stretched absurdly wide — adaptive reflows the grid as the window resizes.
        [GridItem(.adaptive(minimum: 130), spacing: 12)]
#else
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
#endif
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
            } else if !isSearching && jellyfinResults.isEmpty && seerrResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DT.Spacing.xl) {
                        // ── Library section ──────────────────────────────────
                        if !jellyfinResults.isEmpty {
                            librarySection
                        }

                        // ── Discover section ─────────────────────────────────
                        if seerrRepo.isConfigured && !seerrResults.isEmpty {
                            discoverSection
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(DT.Color.backgroundPrimary)
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

    // MARK: - Library section

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sectionGap) {
            Text("Library")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(jellyfinResults) { item in
                    NavigationLink(value: item) {
                        SearchResultCard(title: item.name, subtitle: item.productionYear.map { String($0) },
                                          imageURL: posterImageURL(for: item))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .simultaneousGesture(TapGesture().onEnded { saveRecentSearch(query) })
                }
            }
        }
    }

    /// An episode's own Primary image is a landscape screenshot — forced into this grid's
    /// portrait 2:3 cards it rendered badly (cards visually collided). Episodes use their
    /// series' portrait poster here instead, same as any other result.
    private func posterImageURL(for item: MediaItem) -> URL? {
        guard item.type == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag,
              let base = mediaRepo.baseURL, let token = mediaRepo.accessToken
        else { return mediaRepo.imageURL(for: item) }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: seriesId, tag: tag, type: .primary, fillWidth: 300, token: token)
    }

    // MARK: - Discover section

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sectionGap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                Text("Discover")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
            }
            Text("Not in your library — tap to request")
                .font(.system(.caption2))
                .foregroundStyle(DT.Color.textSecondary)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(seerrResults) { item in
                    Button {
                        saveRecentSearch(query)
                        requestingSeerrItem = item
                    } label: {
                        SearchResultCard(title: item.title, subtitle: item.year, imageURL: item.posterURL)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .padding(DT.Spacing.sm)
        .background(DT.Color.backgroundSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .stroke(DT.Color.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            jellyfinResults = []
            seerrResults = []
            return
        }
        isSearching = true
        Task {
            async let jellyTask: [MediaItem] = mediaRepo.searchIfAuthenticated(
                query: query,
                authState: authManager.state,
                authClient: authManager.authClient
            )
            async let seerrTask = seerrRepo.search(query: query)

            jellyfinResults = await jellyTask
            seerrResults    = await seerrTask
            isSearching = false
        }
    }
}

// MARK: - Grid card

private struct SearchResultCard: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: DT.Color.backgroundSecondary
                        }
                    }
                    .clipped()
                } else {
                    DT.Color.backgroundSecondary
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .stroke(hovered ? DT.Color.accent.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(hovered ? 1.03 : 1)
            .shadow(color: hovered ? DT.Color.accent.opacity(0.2) : .clear, radius: hovered ? 12 : 0)

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
        .animation(DT.Animation.fast, value: hovered)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
    }
}
