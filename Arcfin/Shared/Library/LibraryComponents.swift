// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

// MARK: - Library card

struct LibraryCard: View {
    let library: JellyfinLibrary
    let imageURL: URL?

    @State private var hovered = false

    var body: some View {
        ZStack {
            background

            Rectangle()
                .fill(.black.opacity(0.35))

            VStack(spacing: 10) {
                Image(systemName: library.collectionType.systemIcon)
                    .font(.system(.title, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)

                Text(library.name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
            .padding(16)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(hovered ? DT.Color.accent.opacity(0.5) : Color(hex: library.collectionType.accentHex).opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .scaleEffect(hovered ? 1.02 : 1)
        .animation(DT.Animation.fast, value: hovered)
        .onPointerHover { hovered = $0 }
    }

    @ViewBuilder
    private var background: some View {
        if let imageURL {
            CachedAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill().blur(radius: 3)
                default: gradientFallback
                }
            }
            .clipped()
        } else {
            gradientFallback
        }
    }

    private var gradientFallback: some View {
        LinearGradient(
            colors: [
                Color(hex: library.collectionType.accentHex).opacity(0.25),
                DT.Color.backgroundSecondary,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Same tile treatment as LibraryCard (icon + centered label, gradient background, height
/// 110) so "Your Requests" reads as one more tile alongside the library ones, not a
/// differently-styled row.
struct RequestsCard: View {
    @State private var hovered = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DT.Color.accent.opacity(0.25), DT.Color.backgroundSecondary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(.title, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)

                Text("Requests")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
            .padding(16)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(hovered ? DT.Color.accent.opacity(0.5) : DT.Color.accent.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .scaleEffect(hovered ? 1.02 : 1)
        .animation(DT.Animation.fast, value: hovered)
        .onPointerHover { hovered = $0 }
    }
}

// MARK: - Library grid item card

struct LibraryItemCard: View {
    let imageURL: URL?
    let title: String
    let year: String?

    @State private var hovered = false

    var body: some View {
        // The card's shape comes from the grid, not the image: a square cover (a playlist's)
        // filled to the image's own size made the card wider than its column.
        Color.clear
            .aspectRatio(2/3, contentMode: .fit)
            .overlay {
                if let imageURL {
                    CachedAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color(DT.Color.backgroundSecondary)
                        }
                    }
                } else {
                    DT.Color.backgroundSecondary
                }
            }
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let year {
                            Text(year)
                                .font(.system(.caption2))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                        }
                    }
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hovered ? DT.Color.accent.opacity(0.4) : DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.03 : 1)
        .shadow(color: hovered ? DT.Color.accent.opacity(0.2) : .clear, radius: hovered ? 12 : 0)
        .animation(DT.Animation.fast, value: hovered)
        .onPointerHover { hovered = $0 }
        // Without this, a NavigationLink wrapping this ZStack has no explicit click
        // target, which AppKit's hit-testing is stricter about than UIKit's.
        .contentShape(Rectangle())
    }
}
