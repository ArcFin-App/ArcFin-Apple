// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

// MARK: - Playlist dialogs

/// A playlist's page runs up under the status bar with an artwork-tinted background, like
/// a collection's; every other library keeps its plain background.
struct PlaylistPageStyle: ViewModifier {
    let isPlaylist: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if isPlaylist {
            content
                .detailPageBackground(tint: tint)
                .ignoresSafeArea(edges: .top)
        } else {
            content.screenBackground()
        }
    }
}

/// A playlist's choices and sheets, kept out of LibraryDetailView's already long chain.
struct PlaylistModifiers: ViewModifier {
    let isPlaylist: Bool
    @Binding var playback: MediaDetailView.PlaybackRequest?
    @Binding var showAddTitles: Bool
    @Binding var showRename: Bool
    @Binding var renameText: String
    @Binding var confirmDelete: Bool
    @Binding var error: String?
    let playlistId: String
    let playlistName: String
    let existingIds: Set<String>
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onChanged: () -> Void

    func body(content: Content) -> some View {
        if isPlaylist {
            content
                .appSheet(isPresented: $showAddTitles) {
                    AddTitlesToPlaylistSheet(playlistId: playlistId, existingIds: existingIds, onAdded: onChanged)
                }
                .alert("Rename Playlist", isPresented: $showRename) {
                    TextField("Name", text: $renameText)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") { onRename(renameText) }
                }
                .confirmationDialog("Delete \(playlistName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete Playlist", role: .destructive, action: onDelete)
                } message: {
                    Text("The titles stay in your library.")
                }
                .alert("Playlist", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(error ?? "")
                }
        } else {
            content
        }
    }
}

// MARK: - Grid states

/// An empty playlist, or a Playlists library with none yet: what to do next, and the button
/// that does it.
struct PlaylistEmptyState: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                title, systemImage: "list.and.film",
                description: Text(description))
            Button(action: action) {
                Label(buttonTitle, systemImage: "plus").font(.headline)
            }
            .buttonStyle(.glassProminent)
            .tint(DT.Color.accent)
            .foregroundStyle(DT.Color.onAccent)
            Spacer()
        }
        .screenBackground()
    }
}

/// A playlist's page opens like a collection's: the first title's artwork as the hero,
/// its first posters fanned out with the name and length, then Play and Shuffle.
struct PlaylistHeader: View {
    let heroURL: URL?
    let posterURLs: [URL?]
    let name: String
    let count: Int
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeroBackdrop(url: heroURL, height: 300)
                HStack(alignment: .bottom, spacing: 14) {
                    FannedPosters(urls: posterURLs)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PLAYLIST")
                            .font(.system(.caption2, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(DT.Color.accent)
                        Text(name)
                            .font(.system(.title2, weight: .heavy))
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                        Text(count == 1 ? "1 title" : "\(count) titles")
                            .font(.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, -96)
            }
            playlistButtons
        }
    }

    private var playlistButtons: some View {
        HStack(spacing: 12) {
            Button { play() } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(DT.Color.accent)
            .foregroundStyle(DT.Color.onAccent)
            Button { shuffle() } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.glass)
        }
        .controlSize(.large)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, DT.Spacing.sm)
    }
}

// MARK: - Menus

/// A playlist title's choices: play it (and on through the playlist) or open its page.
struct PlaylistItemActions: View {
    let item: MediaItem
    let model: LibraryDetailModel

    var body: some View {
        let resume = item.userData?.played == true ? 0 : (item.userData?.playbackPositionTicks ?? 0)
        if item.type == .movie || item.type == .episode {
            if resume > 0 {
                Button("Resume") { model.startPlaylistPlayback(from: item, startTicks: resume) }
                Button("Play from Beginning") { model.startPlaylistPlayback(from: item, startTicks: 0) }
            } else {
                Button("Play") { model.startPlaylistPlayback(from: item, startTicks: 0) }
            }
        }
        Button("Show Details") { model.randomPick = item }
    }
}

/// A playlist's run of episodes from one show: play on from the next one, or open the show.
struct PlaylistShowGroupActions: View {
    let episodes: [MediaItem]
    let model: LibraryDetailModel

    var body: some View {
        let next = episodes.first { $0.userData?.played != true } ?? episodes[0]
        let resume = next.userData?.played == true ? 0 : (next.userData?.playbackPositionTicks ?? 0)
        let code = [next.parentIndexNumber.map { "S\($0)" }, next.indexNumber.map { "E\($0)" }]
            .compactMap { $0 }.joined(separator: " ")
        Button(resume > 0 ? "Resume \(code)" : "Play \(code)") { model.startPlaylistPlayback(from: next, startTicks: resume) }
        if next != episodes[0] {
            Button("Play from the First Episode") { model.startPlaylistPlayback(from: episodes[0], startTicks: 0) }
        }
        if let seriesId = episodes[0].seriesId {
            Button("Show Details") {
                model.randomPick = MediaItem(id: seriesId, name: episodes[0].seriesName ?? episodes[0].name, type: .series,
                                             primaryImageTag: episodes[0].seriesPrimaryImageTag)
            }
        }
    }
}

/// A title's name, year and score at the end of its context menu.
struct LibraryQuickLookMenu: View {
    let item: MediaItem

    var body: some View {
        ItemQuickActions(item: item)
        Label(item.name, systemImage: item.type == .series ? "tv" : "film")
        if let year = item.productionYear {
            Label(String(year), systemImage: "calendar")
        }
        if let rating = item.communityRating {
            Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
        }
    }
}

struct LibraryItemPreview: View {
    let item: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: mediaRepo.imageURL(for: item)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: DT.Color.backgroundSecondary
                }
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(item.name)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }
}

// MARK: - Toolbar

/// Surprise me, filters, grid density and, for playlists, their edits, where the screen has a
/// toolbar.
struct LibraryDetailToolbar: ToolbarContent {
    let model: LibraryDetailModel
    @Binding var gridDensity: LibraryGridDensity
    @Binding var showFilterSheet: Bool
    let pickRandom: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { pickRandom() } label: {
                Image(systemName: "dice")
            }
            .disabled(model.isPickingRandom)
            .accessibilityLabel("Surprise me")
            .accessibilityHint(model.isCollections
                ? "Opens a random collection"
                : "Opens a random title from this library using the current filters")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showFilterSheet = true } label: {
                Image(systemName: model.filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter & Sort")
            .accessibilityValue(model.filtersActive ? "Filters on" : "")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Grid Density", selection: $gridDensity) {
                    ForEach(LibraryGridDensity.allCases) { density in
                        Label(density.label, systemImage: density.systemIcon).tag(density)
                    }
                }
            } label: {
                Image(systemName: gridDensity.systemIcon)
            }
            .accessibilityLabel("Grid density")
        }
        if model.isPlaylistsLibrary {
            ToolbarItem(placement: .primaryAction) {
                Button { model.showNewPlaylist = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Playlist")
            }
        }
        if model.playlist != nil {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { model.showAddTitles = true } label: { Label("Add Titles", systemImage: "plus") }
                    Button { model.renameText = model.playlistName ?? model.library.name; model.showRename = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) { model.confirmDeletePlaylist = true } label: {
                        Label("Delete Playlist", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Playlist options")
            }
        }
    }
}
