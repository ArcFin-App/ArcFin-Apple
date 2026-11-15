// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// A watchlist title's poster, name and year, with Remove from Watchlist in its context menu.
struct WatchlistCard: View {
    let item: SeerrItem
    /// A bookmark on the poster that removes the title.
    let showsRemoveButton: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let url = item.posterURL {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: DT.Color.backgroundSecondary
                        }
                    }
                    .clipped()
                } else {
                    DT.Color.backgroundSecondary
                }

                // A Button nested inside this card's own outer Button is undefined on touch
                // platforms and genuinely broken on tvOS, where interaction is focus-based —
                // two independently-focusable targets in the same region confuses the focus
                // engine. tvOS relies on the contextMenu below instead, already present.
                if showsRemoveButton {
                    Button(action: remove) {
                        Image(systemName: "bookmark.fill")
                            .contentFont(.caption2, weight: .semibold)
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.5))
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .frame(width: 44, height: 44, alignment: .topTrailing)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Remove from watchlist")
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
            .tvLabelFocusRing(cornerRadius: DT.Radius.card)
            .contextMenu(menuItems: {
                Button(role: .destructive, action: remove) {
                    Label("Remove from Watchlist", systemImage: "bookmark.slash")
                }
            }, preview: {
                preview
            })

            Text(item.title)
                .contentFont(.caption, design: .default, weight: .semibold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            if let year = item.year {
                Text(year)
                    .contentFont(.caption2, design: .default)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = item.posterURL {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: DT.Color.backgroundSecondary
                        }
                    }
                } else {
                    DT.Color.backgroundSecondary
                }
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(item.title)
                .contentFont(.footnote, design: .default, weight: .semibold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }
}
