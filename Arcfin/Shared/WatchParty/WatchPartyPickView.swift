// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// "Start a Watch Party" beside a title's Play and Trailer buttons.
struct WatchPartyDetailButton: View {
    var action: () -> Void

    @MainActor
    static func isAvailable(_ authManager: AuthManager) -> Bool {
        authManager.arcfinSyncStatus?.isOn("watchParty") == true && ProfileRules.shared.canUseSyncPlay
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.wave.2").contentFont(.subheadline)
                Text("Start a Watch Party").contentFont(.subheadline, design: .default, weight: .semibold)
            }
            .foregroundStyle(DT.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DT.Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }
}

/// Picking what to watch together: a movie or a show, by search or from what's new.
struct WatchPartyPickView: View {
    var picked: (MediaItem) -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false

    private var suggestions: [MediaItem] {
        var seen = Set<String>()
        return (mediaRepo.continueWatching + mediaRepo.recentlyAddedMovies + mediaRepo.recentlyAddedShows)
            .map { $0.type == .episode ? nil : $0 }
            .compactMap(\.self)
            .filter { [.movie, .series].contains($0.type) && seen.insert($0.id).inserted }
    }

    var body: some View {
        List {
            let shown = query.isEmpty ? suggestions : results
            Section {
                ForEach(shown) { item in
                    Button { picked(item) } label: { PickRow(item: item) }
                        .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
                }
            } header: {
                if query.isEmpty, !shown.isEmpty { Text("Suggestions") }
            }
            if !query.isEmpty, results.isEmpty, !isSearching {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
        .overlay { if isSearching && results.isEmpty { ProgressView() } }
        .watchPartySearchable(text: $query, prompt: "Movies and Shows")
        .task(id: query) { await search() }
        .navigationTitle("Pick a Title")
        .inlineNavigationTitle()
        .partyListBackground()
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, let credential = authManager.state.credential else { results = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let found = (try? await JellyfinMediaClient().search(credential: credential, authHeader: header, query: term, limit: 40)) ?? []
        guard !Task.isCancelled else { return }
        results = found.filter { [.movie, .series].contains($0.type) }
    }
}

private struct PickRow: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager

    private var imageURL: URL? {
        guard let credential = authManager.state.credential else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: item.id, tag: item.primaryImageTag ?? "",
                                            type: .primary, fillWidth: 120, token: credential.accessToken)
    }

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            RetryingAsyncImage(url: imageURL, logCategory: "WatchParty") { image in
                image.resizable().scaledToFill()
            } placeholder: {
                DT.Color.backgroundTertiary
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(DT.Font.body)
                    .foregroundStyle(DT.Color.textPrimary)
                Text([item.type == .series ? String(localized: "Show") : String(localized: "Movie"),
                      item.productionYear.map(String.init)].compactMap(\.self).joined(separator: " · "))
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// A show's season, then its episode: the next one to watch to begin with.
struct WatchPartyEpisodePicker: View {
    let series: MediaItem
    var picked: (MediaItem) -> Void

    @Environment(AuthManager.self) private var authManager
    @State private var seasons: [MediaItem] = []
    @State private var season: String?
    @State private var episodes: [MediaItem] = []
    @State private var upNext: MediaItem?
    @State private var isLoading = true

    var body: some View {
        List {
            if seasons.count > 1 {
                Section {
                    Picker("Season", selection: $season) {
                        ForEach(seasons) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section {
                ForEach(episodes) { episode in
                    Button { picked(episode) } label: {
                        EpisodePickRow(episode: episode, isUpNext: episode.id == upNext?.id)
                    }
                    .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
                }
            } header: {
                Text(series.name)
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .partyListBackground()
        .navigationTitle("Pick an Episode")
        .inlineNavigationTitle()
        .task { await loadSeasons() }
        .task(id: season) { await loadEpisodes() }
    }

    private func auth() -> (ServerCredential, String)? {
        guard let credential = authManager.state.credential else { return nil }
        return (credential, authManager.authClient.authHeader(token: credential.accessToken))
    }

    private func loadSeasons() async {
        guard seasons.isEmpty, let (credential, header) = auth() else { return }
        let client = JellyfinMediaClient()
        async let seasonList = client.getSeasons(credential: credential, authHeader: header, seriesId: series.id)
        async let next = client.getNextEpisode(credential: credential, authHeader: header, seriesId: series.id)
        seasons = (try? await seasonList) ?? []
        upNext = (try? await next) ?? nil
        let nextSeason = upNext.flatMap { next in seasons.first { $0.indexNumber == next.parentIndexNumber } }
        season = (nextSeason ?? seasons.first(where: { ($0.indexNumber ?? 0) > 0 }) ?? seasons.first)?.id
        if season == nil { isLoading = false }
    }

    private func loadEpisodes() async {
        guard let season, let (credential, header) = auth() else { return }
        isLoading = true
        defer { isLoading = false }
        episodes = (try? await JellyfinMediaClient().getEpisodes(credential: credential, authHeader: header,
                                                                  seriesId: series.id, seasonId: season)) ?? []
    }
}

private struct EpisodePickRow: View {
    let episode: MediaItem
    let isUpNext: Bool

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.indexNumber.map { String(localized: "Episode \($0)") } ?? "")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                Text(episode.name)
                    .font(DT.Font.body)
                    .foregroundStyle(DT.Color.textPrimary)
            }
            Spacer()
            if isUpNext {
                Text("Up Next")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.accent)
            } else if episode.userData?.played == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DT.Color.textSecondary)
                    .accessibilityLabel("Watched")
            }
        }
        .contentShape(Rectangle())
    }
}
