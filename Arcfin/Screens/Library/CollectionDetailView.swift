// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// A Jellyfin BoxSet (Collection): a tall tinted hero, play-through and shuffle for the
/// whole collection, how much of it has been watched, and its titles in release order as a
/// numbered list (or a poster grid), sortable.
struct CollectionDetailView: View {
    let collection: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(PlaybackPresenter.self) private var playbackPresenter

    @State private var detail: MediaItemDetail?
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedItem: MediaItem?
    @State private var selectedPerson: MediaPerson?
    @State private var heroTint: Color?
    @State private var playbackRequest: MediaDetailView.PlaybackRequest?
    @AppStorage("collectionSort") private var sort = CollectionSort.release
    @AppStorage("collectionShowsGrid") private var showsGrid = false
    #if !os(tvOS)
    @Namespace private var zoomNamespace
    #endif

    private let client = JellyfinMediaClient()

    enum CollectionSort: String, CaseIterable, Identifiable {
        case release = "Release Order", title = "Title", rating = "Rating"
        var id: String { rawValue }
    }

    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    private var sortedItems: [MediaItem] {
        switch sort {
        case .release:
            items.sorted { ($0.premiereDate ?? .distantFuture, $0.productionYear ?? .max) < ($1.premiereDate ?? .distantFuture, $1.productionYear ?? .max) }
        case .title:
            items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .rating:
            items.sorted { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        }
    }

    /// Movies and episodes can be played straight through; a series in a collection opens instead.
    private var playable: [MediaItem] {
        sortedItems.filter { $0.type == .movie || $0.type == .episode }
    }

    private var watchedCount: Int { items.filter { $0.userData?.played == true }.count }

    private var yearSpan: String? {
        let years = items.compactMap(\.productionYear)
        guard let first = years.min(), let last = years.max() else { return nil }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }

    private var columns: [GridItem] {
#if os(macOS)
        [GridItem(.adaptive(minimum: 130), spacing: 12)]
#else
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
#endif
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection

                if isLoading {
                    ProgressView()
                        .tint(DT.Color.accent)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                        actionRow
                        if !items.isEmpty { progressSection }
                        if let overview = detail?.item.overview ?? collection.overview, !overview.isEmpty {
                            Text(overview)
                                .font(.system(.footnote))
                                .foregroundStyle(DT.Color.textPrimary.opacity(0.8))
                                .lineSpacing(4)
                                .lineLimit(5)
                                .padding(.horizontal, DT.Spacing.pagePad)
                        }
                        if !items.isEmpty { titlesSection }
                        if let people = detail?.people, !people.isEmpty { castSection(people) }
                    }
                    .padding(.top, DT.Spacing.md)
                }

                Spacer().frame(height: DT.Size.tabBarHeight + 24)
            }
        }
        .detailPageBackground(tint: heroTint)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(item: $selectedItem) { item in
#if os(tvOS)
            MediaDetailView(item: item)
#else
            MediaDetailView(item: item, zoomNamespace: zoomNamespace)
                .zoomNavigationTransition(id: item.id, in: zoomNamespace)
#endif
        }
        .navigationDestination(item: $selectedPerson) { person in
            PersonDetailView(person: person)
        }
        .task { await load() }
        .task(id: collection.id) {
            guard let url = mediaRepo.imageURL(for: collection, type: .backdrop, fillWidth: 120) else { return }
            heroTint = await AverageColor.load(from: url)
        }
        #if os(macOS)
        .onChange(of: playbackRequest) { _, request in
            guard let request else { return }
            playbackPresenter.present(request.item, startTicks: request.startTicks)
            playbackRequest = nil
        }
        .onChange(of: playbackPresenter.request == nil) { _, closed in
            if closed { PlayQueue.clear(); Task { await load() } }
        }
        #else
        .fullScreenCover(item: $playbackRequest, onDismiss: {
            PlayQueue.clear()
            Task { await load() }
        }) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                PlayerView.keepOrientationOnNextDisappear = true
                playbackRequest = MediaDetailView.PlaybackRequest(item: next, startTicks: 0)
            }
            .id(request.item.id)
        }
        #endif
    }

    // MARK: - Hero

    /// The same hero as a title's page, with the fanned posters and title over its fade.
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeroBackdrop(url: mediaRepo.imageURL(for: collection, type: .backdrop, fillWidth: 1200), height: 300)

            HStack(alignment: .bottom, spacing: 14) {
                posterStack
                VStack(alignment: .leading, spacing: 6) {
                    Text("COLLECTION")
                        .font(.system(.caption2, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(DT.Color.accent)
                    Text(collection.name)
                        .font(.system(.title2, design: .default, weight: .heavy))
                        .foregroundStyle(DT.Color.textPrimary)
                        .tracking(-0.5)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Text(metaLine)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, -96)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !items.isEmpty { parts.append("\(items.count) title\(items.count == 1 ? "" : "s")") }
        if let yearSpan { parts.append(yearSpan) }
        if let rating = collection.communityRating { parts.append("★ \(String(format: "%.1f", rating))") }
        return parts.joined(separator: " · ")
    }

    /// The first few posters fanned out, so the collection reads as a set at a glance.
    private var posterStack: some View {
        let fan = Array(sortedItems.prefix(3))
        return FannedPosters(urls: fan.isEmpty
            ? [mediaRepo.imageURL(for: collection, type: .primary, fillWidth: 240)]
            : fan.map { mediaRepo.imageURL(for: $0, type: .primary, fillWidth: 240) })
    }

    // MARK: - Actions & progress

    private var nextToPlay: MediaItem? {
        playable.first { $0.userData?.played != true }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button { playThrough() } label: {
                Label(playLabel, systemImage: "play.fill")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(.white, in: RoundedRectangle(cornerRadius: DT.Radius.md))
            }
            .buttonStyle(PressableButtonStyle())
            Button { shuffle() } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: DT.Radius.md))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .disabled(playable.isEmpty)
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private var playLabel: String {
        guard let next = nextToPlay else { return "Play from Start" }
        if (next.userData?.playbackPositionTicks ?? 0) > 0 { return "Resume \(next.name)" }
        return watchedCount == 0 ? "Play" : "Continue with \(next.name)"
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(watchedCount == items.count ? "All watched" : "\(watchedCount) of \(items.count) watched")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DT.Color.progressTrack)
                    Capsule().fill(DT.Color.accent)
                        .frame(width: geo.size.width * CGFloat(watchedCount) / CGFloat(max(items.count, 1)))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Titles

    private var titlesSection: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack {
                Text("Titles")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CollectionSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Sort by \(sort.rawValue)")
                Button {
                    withAnimation(DT.Animation.fast) { showsGrid.toggle() }
                } label: {
                    Image(systemName: showsGrid ? "list.bullet" : "square.grid.3x2")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(showsGrid ? "Show as list" : "Show as grid")
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            if showsGrid {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sortedItems) { item in
                        Button { selectedItem = item } label: {
                            PosterCard(
                                title: item.name,
                                subtitle: item.productionYear.map { String($0) },
                                progress: item.userData?.playedPercentage.map { $0 / 100 },
                                imageURL: mediaRepo.imageURL(for: item)
                            )
                            .overlay(alignment: .topTrailing) { watchedBadge(item) }
                        }
                        .modifier(CardButtonStyle(id: item.id, namespace: namespace))
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                        Button { selectedItem = item } label: { titleRow(item, number: index + 1) }
                            .modifier(CardButtonStyle(id: item.id, namespace: namespace))
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
    }

    private var namespace: Namespace.ID? {
        #if os(tvOS)
        nil
        #else
        zoomNamespace
        #endif
    }

    private func titleRow(_ item: MediaItem, number: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if sort == .release {
                Text("\(number)")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.6))
                    .frame(width: 26, alignment: .trailing)
                    .padding(.top, 22)
            }
            CachedAsyncImage(url: mediaRepo.imageURL(for: item, type: .thumb, fillWidth: 360)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: DT.Color.backgroundSecondary
                }
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                if let pct = item.userData?.playedPercentage, pct > 0, pct < 100 {
                    GeometryReader { geo in
                        Capsule().fill(DT.Color.accent)
                            .frame(width: geo.size.width * pct / 100, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) { watchedBadge(item) }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let year = item.productionYear { Text(String(year)) }
                    if let rating = item.communityRating {
                        Text("★ \(String(format: "%.1f", rating))").foregroundStyle(DT.Color.accent)
                    }
                }
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func watchedBadge(_ item: MediaItem) -> some View {
        if item.userData?.played == true {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.footnote))
                .foregroundStyle(.white, DT.Color.accent)
                .padding(5)
                .accessibilityLabel("Watched")
        }
    }

    // MARK: - Cast

    private func castSection(_ people: [MediaPerson]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(people) { person in
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
    }

    private var personPlaceholder: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .font(.system(.title2))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
    }

    // MARK: - Playback

    private func playThrough() {
        guard let start = nextToPlay ?? playable.first, let index = playable.firstIndex(of: start) else { return }
        PlayQueue.start(Array(playable[index...]))
        let resume = start.userData?.played == true ? 0 : (start.userData?.playbackPositionTicks ?? 0)
        playbackRequest = MediaDetailView.PlaybackRequest(item: start, startTicks: resume)
    }

    private func shuffle() {
        let shuffled = playable.shuffled()
        guard let first = shuffled.first else { return }
        PlayQueue.start(shuffled)
        playbackRequest = MediaDetailView.PlaybackRequest(item: first, startTicks: 0)
    }

    // MARK: - Load

    private func load() async {
        guard let cred = credential, let header = authHeader else {
            isLoading = false
            return
        }
        async let fetchedDetail = client.getItemDetail(credential: cred, authHeader: header, itemId: collection.id)
        async let fetchedItems = client.getLibraryItems(
            credential: cred, authHeader: header, libraryId: collection.id, limit: 200,
            recursive: false, sortBy: "PremiereDate,ProductionYear,SortName"
        )
        detail = try? await fetchedDetail
        if let fetched = try? await fetchedItems { items = fetched.items }
        isLoading = false
    }
}

/// Pressable on iOS/macOS with the zoom transition source; the focus card style on tvOS.
private struct CardButtonStyle: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
#if os(tvOS)
        content
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
#else
        if let namespace {
            content
                .buttonStyle(PressableButtonStyle())
                .zoomTransitionSource(id: id, in: namespace)
        } else {
            content.buttonStyle(PressableButtonStyle())
        }
#endif
    }
}
