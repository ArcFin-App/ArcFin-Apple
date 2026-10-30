// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A poster card's artwork, or a gradient in the card's hue while there's none.
struct PosterCardArtwork: View {
    let title: String
    let imageURL: URL?
    let accentHue: Color

    var body: some View {
        Group {
            if let url = imageURL {
                RetryingAsyncImage(
                    url: url,
                    logCategory: "PosterCard",
                    logContext: "title=\(title)",
                    content: { img in img.resizable().scaledToFill() },
                    placeholder: { placeholderGradient }
                )
                .clipped()
            } else {
                placeholderGradient
            }
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [accentHue, DT.Color.backgroundPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

#Preview {
    HStack(spacing: 12) {
        PosterCard(title: "Dune: Part Two", subtitle: "2024", accentHue: Color(hex: "1a0a2e"), progress: 0.62)
        PosterCard(title: "Oppenheimer", subtitle: "S2 E7", accentHue: Color(hex: "1c0e00"))
    }
    .padding()
    .background(DT.Color.backgroundPrimary)
}
