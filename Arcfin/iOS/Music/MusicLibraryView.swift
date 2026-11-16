// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A music library: Artists, Albums, Songs and Genres, then what was added lately.
struct MusicLibraryView: View {
    let library: JellyfinLibrary
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var recent: MusicPagedList<MusicAlbum>

    init(library: JellyfinLibrary) {
        self.library = library
        let id = library.id
        _recent = State(initialValue: MusicPagedList { _ in
            let page = try await MusicAPI.call {
                try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: id, sort: .dateAdded,
                                            ascending: false, limit: 40)
            }
            return (page.albums, page.albums.count)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                VStack(spacing: 0) {
                    row("Playlists", systemImage: "music.note.list", route: .playlists)
                    row("Artists", systemImage: "music.microphone", route: .artists(libraryID: library.id))
                    row("Albums", systemImage: "square.stack", route: .albums(libraryID: library.id, title: String(localized: "Albums")))
                    row("Songs", systemImage: "music.note", route: .songs(libraryID: library.id))
                    row("Genres", systemImage: "guitars", route: .genres(libraryID: library.id), isLast: true)
                }
                VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                    Text("Recently Added")
                        .font(DT.Font.sectionTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                    MusicListState(list: recent, empty: "No Albums")
                    LazyVGrid(columns: MusicGrid.columns(sizeClass), alignment: .leading, spacing: DT.Spacing.lg) {
                        ForEach(recent.items) { MusicAlbumCard(album: $0) }
                    }
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.xl)
        }
        .screenBackground()
        .navigationTitle(Text(verbatim: library.name))
        .task { await recent.loadIfNeeded() }
        .refreshable { await recent.reload() }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, route: MusicRoute, isLast: Bool = false) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 0) {
                HStack(spacing: DT.Spacing.md) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(DT.Color.accent)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.title3)
                        .foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 12)
                if !isLast {
                    Divider().padding(.leading, 46)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Every album, or a genre's, as a grid with a sort and a favourites filter.
struct MusicAlbumsView: View {
    let libraryID: String
    let title: String
    let genreID: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("music.albumSort") private var sort: MusicSort = .name
    @State private var favoritesOnly = false
    @State private var list: MusicPagedList<MusicAlbum>?

    var body: some View {
        ScrollView {
            if let list {
                MusicListState(list: list, empty: favoritesOnly ? "No Favorite Albums" : "No Albums")
                LazyVGrid(columns: MusicGrid.columns(sizeClass), alignment: .leading, spacing: DT.Spacing.lg) {
                    ForEach(list.items) { album in
                        MusicAlbumCard(album: album)
                            .task { await list.rowAppeared(album) }
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.xl)
            }
        }
        .screenBackground()
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        Text("Title").tag(MusicSort.name)
                        Text("Artist").tag(MusicSort.artist)
                        Text("Year").tag(MusicSort.year)
                        Text("Recently Added").tag(MusicSort.dateAdded)
                    }
                    Toggle("Favorites Only", systemImage: "star", isOn: $favoritesOnly)
                } label: {
                    Label("Sort and Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
        .task(id: "\(sort.rawValue)-\(favoritesOnly)") {
            let list = makeList()
            self.list = list
            await list.loadIfNeeded()
        }
    }

    private func makeList() -> MusicPagedList<MusicAlbum> {
        let filter = MusicFilter(favoritesOnly: favoritesOnly, genreId: genreID)
        let libraryID = libraryID, sort = sort
        return MusicPagedList { start in
            let page = try await MusicAPI.call {
                try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: libraryID, sort: sort,
                                            ascending: sort != .dateAdded && sort != .year, filter: filter,
                                            startIndex: start)
            }
            return (page.albums, page.total)
        }
    }
}
