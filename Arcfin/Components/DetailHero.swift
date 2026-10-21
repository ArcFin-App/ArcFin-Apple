// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The artwork across the top of a detail page, as on a title's page: full width, running up
/// under the status bar, softening into a blur toward the bottom and fading into whatever is
/// behind it (the artwork-tinted page background). Shared so collection, playlist and
/// download pages look like the rest.
struct DetailHeroBackdrop<Fallback: View>: View {
    let url: URL?
    var height: CGFloat = 260
    @ViewBuilder var fallback: Fallback

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }

            // Progressive blur: the material only shows toward the bottom edge.
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.35), .init(color: .black, location: 1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .frame(height: height)
        // Exactly the screen's width; a fill-scaled image sized by its own width pushes the
        // page past both edges on a narrow phone.
        .containerRelativeFrame(.horizontal)
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipped()
        .accessibilityHidden(true)
    }
}

extension DetailHeroBackdrop where Fallback == LinearGradient {
    init(url: URL?, height: CGFloat = 260) {
        self.init(url: url, height: height) {
            LinearGradient(colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Up to three posters fanned out, so a set (a collection, a playlist) reads as a set.
struct FannedPosters: View {
    let urls: [URL?]

    var body: some View {
        ZStack {
            ForEach(Array(urls.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: DT.Color.backgroundSecondary
                    }
                }
                .frame(width: 92, height: 138)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                .rotationEffect(.degrees(Double(index) * 6))
                .offset(x: CGFloat(index) * 14, y: CGFloat(index) * -4)
                .opacity(index == 0 ? 1 : 0.85)
            }
        }
        .frame(width: 118, height: 150, alignment: .bottomLeading)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The page background behind a DetailHeroBackdrop: the app background, washed from the
    /// top with the artwork's average colour once it's known.
    func detailPageBackground(tint: Color?) -> some View {
        background {
            ZStack {
                DT.Color.backgroundPrimary
                if let tint {
                    LinearGradient(colors: [tint.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: tint)
        }
    }
}
