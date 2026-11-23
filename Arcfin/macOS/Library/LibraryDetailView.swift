// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

struct LibraryDetailView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(PlaybackPresenter.self) private var playbackPresenter
    @Environment(\.dismiss) private var dismiss
    @AppStorage("libraryGridDensity") private var gridDensity = LibraryGridDensity.normal

    @State private var model: LibraryDetailModel
    @State private var scrolledItemID: MediaItem.ID? = nil
    @State private var trailerLaunchItem: MediaItem?
    @State private var quickPlayRequest: PlaybackRequest?
    @State private var showFilterSheet = false

    init(library: JellyfinLibrary, playlist: MediaPlaylist? = nil, startsAddingTitles: Bool = false) {
        _model = State(initialValue: LibraryDetailModel(library: library, playlist: playlist, startsAddingTitles: startsAddingTitles))
    }

    /// A playlist picked from the Playlists library.
    init(playlistItem item: MediaItem, startsAddingTitles: Bool = false) {
        self.init(
            library: JellyfinLibrary(id: item.id, name: item.name, collectionType: .playlists),
            playlist: MediaPlaylist(id: item.id, name: item.name, itemCount: 0, primaryImageTag: item.primaryImageTag),
            startsAddingTitles: startsAddingTitles)
    }

    private var columns: [GridItem] {
        // A fixed column count leaves a resizable Mac window either cramped or with
        // cards stretched absurdly wide — adaptive reflows as the window resizes,
        // with density still controlling how small a card can get first.
        [GridItem(.adaptive(minimum: gridDensity.adaptiveMinimumWidth), spacing: 12)]
    }

    var body: some View {
        Group {
            if model.isLoading && model.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .screenBackground()
            } else if model.items.isEmpty, model.playlist != nil, !model.filtersActive, !model.isSearching, !model.loadFailed {
                PlaylistEmptyState(
                    title: "Empty Playlist",
                    description: "Add movies, shows and episodes, or long-press any title and choose Add to Playlist.",
                    buttonTitle: "Add Titles"
                ) { model.showAddTitles = true }
            } else if model.items.isEmpty, model.isPlaylistsLibrary, !model.filtersActive, !model.isSearching, !model.loadFailed {
                PlaylistEmptyState(
                    title: "No Playlists",
                    description: "Make a playlist, then add movies, shows and episodes to it.",
                    buttonTitle: "New Playlist"
                ) { model.showNewPlaylist = true }
            } else if model.items.isEmpty {
                LibraryEmptyResults(model: model, retry: reload)
                    .screenBackground()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        if model.playlist != nil { playlistHeader }
                        LazyVGrid(columns: columns, spacing: DT.Spacing.shelfGap) {
                            ForEach(model.gridEntries) { entry in
                                Group {
                                    if entry.items.count > 1 {
                                        showGroupCell(entry.items)
                                    } else {
                                        itemCell(entry.items[0])
                                    }
                                }
                                .onAppear {
                                    if let last = entry.items.last, model.shouldLoadMore(after: last) {
                                        Task { await model.loadMore(authManager: authManager) }
                                    }
                                }
                            }

                            if model.isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else if model.loadMoreFailed {
                                Button("Try Again") { Task { await model.loadMore(authManager: authManager) } }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                        }
                        .padding(DT.Spacing.pagePad)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("library.grid")
                    }
                    .scrollPosition(id: $scrolledItemID)
                    .modifier(PlaylistPageStyle(isPlaylist: model.playlist != nil, tint: model.playlistTint))
                    .overlay {
                        if model.showsLetterIndex {
                            LetterIndexBar { letter in Task { await model.jump(to: letter, authManager: authManager) } }
                        }
                    }
                    .onChange(of: model.jumpTarget) { _, target in
                        guard let target else { return }
                        proxy.scrollTo(target, anchor: .top)
                        model.jumpTarget = nil
                    }
                }
            }
        }
        .navigationTitle(model.playlistName ?? model.library.name)
        .toolbar {
            LibraryDetailToolbar(model: model, authManager: authManager, gridDensity: $gridDensity, showFilterSheet: $showFilterSheet) {
                Task { await model.pickRandom(authManager: authManager) }
            }
        }
        // .sheet doesn't reliably render its content on macOS here (same class of issue as
        // PlayerView's track/chapter menus) — rendered as a plain in-place overlay instead.
        .overlay {
            if showFilterSheet {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { showFilterSheet = false }
                        .accessibilityHidden(true)
                    VStack(spacing: 0) {
                        HStack {
                            Text("Filter & Sort").contentFont(.subheadline, design: .default, weight: .semibold)
                            Spacer()
                            Button("Done") { showFilterSheet = false }
                                .keyboardShortcut(.defaultAction)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        Divider()
                        LibraryFilterList(
                            availableGenres: model.availableGenres, availableYears: model.availableYears, availableRatings: model.availableRatings, availableTags: model.availableTags,
                            selectedGenres: $model.selectedGenres, selectedYears: $model.selectedYears,
                            watchedFilter: $model.watchedFilter, favoritesOnly: $model.favoritesOnly, sortOption: $model.sortOption,
                            extraFilters: $model.extraFilters, sortOptions: model.sortOptions
                        )
                    }
                    .frame(width: 380, height: 480)
                    // The hand-built panel lost a sheet's keyboard handling: Esc closes it, and
                    // keyboard focus stays inside it rather than reaching the grid behind.
                    .onExitCommand { showFilterSheet = false }
                    .focusSection()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(DT.Color.textPrimary.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 30)
                }
                .transition(.opacity)
            }
        }
        .animation(DT.Animation.motion(.easeInOut(duration: 0.15)), value: showFilterSheet)
        .confirmationDialog(
            Text("Remove \(model.pendingGroupRemoval?.count ?? 0) Episodes from Playlist"),
            isPresented: Binding(get: { model.pendingGroupRemoval != nil },
                                 set: { if !$0 { model.pendingGroupRemoval = nil } }),
            titleVisibility: .visible,
            presenting: model.pendingGroupRemoval
        ) { episodes in
            Button("Remove", role: .destructive) {
                model.removeFromPlaylist(episodes, authManager: authManager, mediaRepo: mediaRepo)
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: model.selectedGenres) { _, _ in model.filtersChanged(authManager: authManager, mediaRepo: mediaRepo) }
        .onChange(of: model.selectedYears) { _, _ in model.filtersChanged(authManager: authManager, mediaRepo: mediaRepo) }
        .onChange(of: model.extraFilters) { _, _ in model.filtersChanged(authManager: authManager, mediaRepo: mediaRepo) }
        .onChange(of: model.watchedFilter) { _, _ in model.filtersChanged(authManager: authManager, mediaRepo: mediaRepo) }
        .onChange(of: model.favoritesOnly) { _, _ in model.filtersChanged(authManager: authManager, mediaRepo: mediaRepo) }
        .modifier(LibrarySearchModifier(model: model, authManager: authManager, mediaRepo: mediaRepo))
        .quickPlayback($quickPlayRequest, trailer: $trailerLaunchItem)
        .navigationDestination(item: $model.randomPick) { pick in
            if pick.type == .boxSet {
                CollectionDetailView(collection: pick)
            } else if pick.type == .playlist {
                LibraryDetailView(playlistItem: pick)
            } else {
                MediaDetailView(item: pick)
            }
        }
        .onChange(of: model.sortOption) { _, _ in
            model.sortChanged(authManager: authManager, mediaRepo: mediaRepo)
        }
        .modifier(PlaylistModifiers(
            isPlaylist: model.playlist != nil || model.isPlaylistsLibrary,
            playback: $model.playlistPlayback,
            showAddTitles: $model.showAddTitles,
            showRename: $model.showRename,
            renameText: $model.renameText,
            confirmDelete: $model.confirmDeletePlaylist,
            error: $model.playlistError,
            playlistId: model.playlist?.id ?? "",
            playlistName: model.playlistName ?? model.library.name,
            existingIds: Set(model.items.map(\.id)),
            onRename: { model.renamePlaylist($0, authManager: authManager) },
            onDelete: { model.deletePlaylist(authManager: authManager) { dismiss() } },
            onChanged: { reload() }
        ))
        .onChange(of: model.playlistPlayback) { _, request in
            guard let request else { return }
            playbackPresenter.present(request.item, startTicks: request.startTicks)
            model.playlistPlayback = nil
        }
        .onChange(of: playbackPresenter.request == nil) { _, closed in
            if closed, model.playlist != nil { PlayQueue.clear(); reload() }
        }
        .alert("New Playlist", isPresented: $model.showNewPlaylist) {
            TextField("Name", text: $model.newPlaylistName)
            Button("Cancel", role: .cancel) { model.newPlaylistName = "" }
            Button("Create") { model.createPlaylist(authManager: authManager, mediaRepo: mediaRepo) }
        }
        .navigationDestination(item: $model.createdPlaylist) { created in
            LibraryDetailView(
                library: JellyfinLibrary(id: created.id, name: created.name, collectionType: .playlists),
                playlist: created, startsAddingTitles: true)
        }
        .task { await model.load(authManager: authManager, mediaRepo: mediaRepo) }
        .task { await model.loadFilterOptions(authManager: authManager) }
        .task(id: model.playlistHeroURL(in: mediaRepo)) {
            await model.loadPlaylistTint(mediaRepo: mediaRepo)
        }
    }

    private func reload() {
        Task { await model.reload(authManager: authManager, mediaRepo: mediaRepo) }
    }

    private var playlistHeader: some View {
        PlaylistHeader(
            heroURL: model.playlistHeroURL(in: mediaRepo),
            posterURLs: model.items.prefix(3).map { LibraryItemText.posterURL($0, in: mediaRepo) },
            name: model.playlistName ?? model.library.name,
            count: model.items.count,
            play: { model.playAllFromStart() },
            shuffle: { model.shufflePlaylist() })
    }

    /// A playlist's titles open a Play / Show Details choice instead of their page.
    @ViewBuilder
    private func gridLink<Content: View>(for item: MediaItem, @ViewBuilder label: () -> Content) -> some View {
        if model.playlist != nil {
            // A menu opens the same way from every card; a confirmation dialog switched
            // between a popover and a full sheet depending on the room around the card.
            Menu { PlaylistItemActions(item: item, model: model) } label: { label() }
                .menuStyle(.button)
                .menuIndicator(.hidden)
        } else {
            // On the Mac a NavigationLink(value:) can't find Browse's destination.
            Button { model.randomPick = item } label: { label() }
        }
    }

    private func itemCell(_ item: MediaItem) -> some View {
        gridLink(for: item) {
            LibraryItemCard(
                imageURL: LibraryItemText.posterURL(item, in: mediaRepo),
                title: LibraryItemText.title(item),
                year: LibraryItemText.subtitle(item)
            )
            .unwatchedBadge(item)
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu(menuItems: { libraryMenu(item) }, preview: { LibraryItemPreview(item: item, imageURL: mediaRepo.imageURL(for: item)) })
    }

    private func showGroupCell(_ episodes: [MediaItem]) -> some View {
        let first = episodes[0]
        let subtitle = LibraryItemText.showGroupSubtitle(episodes)
        return Menu {
            PlaylistShowGroupActions(episodes: episodes, model: model)
        } label: {
            LibraryItemCard(imageURL: LibraryItemText.posterURL(first, in: mediaRepo), title: first.seriesName ?? first.name, year: subtitle)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            Button(role: .destructive) { model.pendingGroupRemoval = episodes } label: {
                Label("Remove \(episodes.count) Episodes from Playlist", systemImage: "minus.circle")
            }
        }
    }

    @ViewBuilder
    private func libraryMenu(_ item: MediaItem) -> some View {
        if model.playlist != nil, model.entryIds[item.id] != nil {
            Button(role: .destructive) { model.removeFromPlaylist(item, authManager: authManager, mediaRepo: mediaRepo) } label: {
                Label("Remove from Playlist", systemImage: "minus.circle")
            }
        }
        if item.type == .movie || item.type == .episode {
            let ticks = (item.userData?.played == true) ? 0 : (item.userData?.playbackPositionTicks ?? 0)
            Button { quickPlayRequest = PlaybackRequest(item: item, startTicks: ticks) } label: {
                Label(ticks > 0 ? "Resume" : "Play", systemImage: "play.fill")
            }
        }
        Button { trailerLaunchItem = item } label: {
            Label("Play Trailer", systemImage: "play.rectangle")
        }
        LibraryQuickLookMenu(item: item) { model.replace($0) }
    }
}
