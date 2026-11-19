// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A smart playlist's tile: its colour, symbol and name.
struct MusicSmartPlaylistTile: View {
    let playlist: MusicSmartPlaylist
    let libraryID: String
    var width: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MusicSmartPlaylistArt(playlist: playlist, libraryID: libraryID, side: width) {
                MusicArtwork(url: $0, cornerRadius: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
            Text(playlist.detail)
                .font(.footnote)
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(playlist.title))
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A smart playlist's songs, with Play and Shuffle.
struct MusicSmartPlaylistView: View {
    let playlist: MusicSmartPlaylist
    let libraryID: String
    @State private var songs: [MusicSong]?

    var body: some View {
        List {
            MusicPlayShuffleButtons(play: { MusicActions.play(songs ?? []) }, shuffle: { MusicActions.shuffle(songs ?? []) })
                .disabled(songs?.isEmpty != false)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if let songs {
                if songs.isEmpty {
                    ContentUnavailableView("No Songs", systemImage: playlist.systemImage)
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    MusicSongRow(song: song) { MusicActions.play(songs, from: index) }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(playlist.title)
        .task { songs = await playlist.songs(libraryID: libraryID) }
        .refreshable { songs = await playlist.songs(libraryID: libraryID) }
    }
}

/// The library's row of smart playlists.
struct MusicSmartPlaylistShelf: View {
    let libraryID: String

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            Text("Made for You")
                .font(DT.Font.sectionTitle)
                .foregroundStyle(DT.Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DT.Spacing.md) {
                    ForEach(MusicSmartPlaylist.allCases) { playlist in
                        NavigationLink { MusicSmartPlaylistView(playlist: playlist, libraryID: libraryID) } label: {
                            MusicSmartPlaylistTile(playlist: playlist, libraryID: libraryID)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .shelfScrollButtons()
            .padding(.horizontal, -DT.Spacing.pagePad)
            .contentMargins(.horizontal, DT.Spacing.pagePad, for: .scrollContent)
        }
    }
}
