// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

struct LibraryDetailView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var model: LibraryDetailModel
    @State private var scrolledItemID: MediaItem.ID? = nil
    @FocusState private var focusedItemID: MediaItem.ID?
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

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: DT.Spacing.shelfGap)]

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
                // The action row stays, so Filter & Sort can still be reached to undo filters
                // that match nothing: the empty state alone left nothing to focus.
                VStack(spacing: 0) {
                    tvActionRow
                    LibraryEmptyResults(model: model, retry: reload)
                        .focusSection()
                }
                .screenBackground()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        if model.playlist != nil { playlistHeader }
                        tvActionRow
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
                        // Room for the A–Z column.
                        .padding(.trailing, model.showsLetterIndex ? 64 : 0)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("library.grid")
                        .focusSection()
                        .scrollClipDisabled()
                    }
                    .scrollPosition(id: $scrolledItemID)
                    .overlay(alignment: .trailing) {
                        if model.showsLetterIndex { tvLetterColumn }
                    }
                    .modifier(PlaylistPageStyle(isPlaylist: model.playlist != nil, tint: model.playlistTint))
                    .onChange(of: model.jumpTarget) { _, target in
                        guard let target else { return }
                        proxy.scrollTo(target, anchor: .top)
                        focusedItemID = target
                        model.jumpTarget = nil
                    }
                }
            }
        }
        .navigationTitle("")
        .appSheet(isPresented: $showFilterSheet, title: "Filter & Sort", systemImage: "line.3.horizontal.decrease.circle") {
            LibraryFilterSheet(
                availableGenres: model.availableGenres, availableYears: model.availableYears, availableRatings: model.availableRatings, availableTags: model.availableTags,
                selectedGenres: $model.selectedGenres, selectedYears: $model.selectedYears,
                watchedFilter: $model.watchedFilter, favoritesOnly: $model.favoritesOnly, sortOption: $model.sortOption,
                extraFilters: $model.extraFilters, sortOptions: model.sortOptions
            )
        }
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
        .fullScreenCover(item: $model.playlistPlayback, onDismiss: {
            PlayQueue.clear()
            reload()
        }) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                PlayerView.keepOrientationOnNextDisappear = true
                model.playlistPlayback = MediaDetailView.PlaybackRequest(item: next, startTicks: 0)
            }
            .id(request.item.id)
        }
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

    /// What the toolbar holds elsewhere; tvOS screens have no toolbar.
    private var tvActionRow: some View {
        HStack(spacing: 20) {
            if model.playlist != nil {
                Button { model.showAddTitles = true } label: { tvActionLabel("Add Titles", systemImage: "plus") }
                Button { model.renameText = model.playlistName ?? model.library.name; model.showRename = true } label: {
                    tvActionLabel("Rename", systemImage: "pencil")
                }
                Button { model.confirmDeletePlaylist = true } label: { tvActionLabel("Delete", systemImage: "trash") }
            } else if model.isPlaylistsLibrary {
                Button { model.showNewPlaylist = true } label: { tvActionLabel("New Playlist", systemImage: "plus") }
            }
            Button { showFilterSheet = true } label: {
                tvActionLabel("Filter & Sort", systemImage: model.filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            if model.playlist == nil {
                Button { Task { await model.pickRandom(authManager: authManager) } } label: { tvActionLabel("Surprise Me", systemImage: "dice") }
                    .disabled(model.isPickingRandom)
            }
            Spacer()
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, DT.Spacing.md)
        .focusSection()
    }

    /// The A–Z index down the trailing edge, as on the other platforms.
    private var tvLetterColumn: some View {
        VStack(spacing: 0) {
            ForEach(LibraryLetterIndex.letters, id: \.self) { letter in
                Button { Task { await model.jump(to: letter, authManager: authManager) } } label: {
                    TVLetterLabel(letter: letter)
                }
                .accessibilityLabel(Text("Jump to \(letter)"))
            }
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .padding(.trailing, DT.Spacing.md)
        .focusSection()
    }

    private func tvActionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        TVHeroButtonLabel(icon: systemImage, text: title)
            .background(Capsule().fill(DT.Color.textPrimary.opacity(0.06)))
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
            NavigationLink(value: model.navTarget(for: item)) { label() }
        }
    }

    private func itemCell(_ item: MediaItem) -> some View {
        gridLink(for: item) {
            PosterCard(
                title: LibraryItemText.title(item),
                subtitle: LibraryItemText.subtitle(item),
                imageURL: LibraryItemText.posterURL(item, in: mediaRepo),
                width: 200,
                height: 356
            )
            .unwatchedBadge(item)
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .focused($focusedItemID, equals: item.id)
        .contextMenu(menuItems: { libraryMenu(item) }, preview: { LibraryItemPreview(item: item, imageURL: mediaRepo.imageURL(for: item)) })
    }

    private func showGroupCell(_ episodes: [MediaItem]) -> some View {
        let first = episodes[0]
        let subtitle = LibraryItemText.showGroupSubtitle(episodes)
        return Menu {
            PlaylistShowGroupActions(episodes: episodes, model: model)
        } label: {
            PosterCard(title: first.seriesName ?? first.name, subtitle: subtitle,
                       imageURL: LibraryItemText.posterURL(first, in: mediaRepo), width: 200, height: 356)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
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
        LibraryQuickLookMenu(item: item) { model.replace($0) }
    }
}
