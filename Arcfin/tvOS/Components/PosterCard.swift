// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct PosterCard: View {
    var title: String
    var subtitle: String? = nil
    var accentHue: Color = Color(hex: "24140F")
    var progress: Double? = nil
    var imageURL: URL? = nil
    var width: CGFloat = DT.Size.posterCard.width
    var height: CGFloat = DT.Size.posterCard.height

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageLayer
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3)
                )
                .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 10)
                .compositingGroup()
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
                if let subtitle {
                    Text(subtitle)
                        .scaledFont(size: 11, weight: .medium)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, height: 84, alignment: .topLeading)
        }
        // Clip the whole card+text column so no system focus transform bleeds outside
        .contentShape(Rectangle())
    }

    private var imageLayer: some View {
        PosterCardArtwork(title: title, imageURL: imageURL, accentHue: accentHue)
    }
}
