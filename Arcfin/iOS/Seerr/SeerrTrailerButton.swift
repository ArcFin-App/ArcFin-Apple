// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Plays a Seerr title's YouTube trailer, under its main action.
struct SeerrTrailerButton: View {
    let videoID: String
    let title: String

    @State private var showTrailer = false

    var body: some View {
        Button {
            showTrailer = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "film").font(.system(.subheadline))
                Text("Play Trailer").font(.system(.subheadline, design: .default, weight: .semibold))
            }
            .foregroundStyle(DT.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DT.Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
        .fullScreenCover(isPresented: $showTrailer) {
            YouTubeTrailerPlayerView(videoID: videoID, title: title)
        }
    }
}
