// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Music in Browse search, below the library's results: artists, albums, then songs.
struct MusicSearchSection: View {
    let results: MusicSearchResults

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xl) {
            if !results.artists.isEmpty {
                shelf(String(localized: "Artists"), count: results.artists.count) {
                    ForEach(results.artists) { artist in
                        NavigationLink(value: MusicRoute.artist(artist, libraryID: nil)) {
                            VStack(spacing: DT.Spacing.xs) {
                                MusicArtwork(url: MusicAPI.artworkURL(artist, width: 240), isCircle: true)
                                    .frame(width: 100, height: 100)
                                Text(verbatim: artist.name)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(DT.Color.textPrimary)
                                    .lineLimit(1)
                            }
                            .frame(width: 100)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.albums.isEmpty {
                shelf(String(localized: "Albums"), count: results.albums.count) {
                    ForEach(results.albums) { album in
                        MusicAlbumCard(album: album).frame(width: 140)
                    }
                }
            }
            if !results.songs.isEmpty {
                VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                    SearchSectionHeader(title: String(localized: "Songs"), count: results.songs.count)
                        .padding(.horizontal, DT.Spacing.pagePad)
                    VStack(spacing: 0) {
                        ForEach(Array(results.songs.prefix(8).enumerated()), id: \.element.id) { index, song in
                            MusicSongRow(song: song) { MusicActions.play(results.songs, from: index) }
                                .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                }
            }
        }
    }

    private func shelf<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            SearchSectionHeader(title: title, count: count)
                .padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DT.Spacing.md) { content() }
                    .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
    }
}
