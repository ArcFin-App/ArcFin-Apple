// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// An artist's logo where the server has one, otherwise their name.
struct MusicArtistTitle: View {
    let artist: MusicArtist
    var logoSize = CGSize(width: 300, height: 110)
    var alignment: Alignment = .center

    var body: some View {
        if let url = MusicAPI.logoURL(artist) {
            CachedAsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                        .frame(maxWidth: logoSize.width, maxHeight: logoSize.height, alignment: alignment)
                        .shadow(color: .black.opacity(0.35), radius: 8)
                } else if case .empty = phase {
                    // Its space kept while it loads, so the name doesn't flash up first.
                    Color.clear.frame(height: logoSize.height)
                } else {
                    name
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: artist.name))
            .accessibilityAddTraits(.isHeader)
        } else {
            name
        }
    }

    private var name: some View {
        Text(verbatim: artist.name)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(DT.Color.textPrimary)
    }
}
