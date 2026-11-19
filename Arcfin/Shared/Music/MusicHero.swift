// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The top of an album or playlist page, laid out like a title's detail page: the artwork
/// across the whole width and the top of the screen, under the navigation bar, softening and
/// fading into the page at the bottom, with the names over that edge.
struct MusicHero<Art: View, Info: View>: View {
    @ViewBuilder let art: (CGSize) -> Art
    @ViewBuilder let info: () -> Info

    /// Album art is square, so a little taller than a title's backdrop keeps more of it.
    private let height: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            // Sized by the page, not the artwork: a fill-scaled image can't push the page wider.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    GeometryReader { proxy in
                        ZStack {
                            art(proxy.size)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                            // The image softens as it leaves the frame rather than ending in a band.
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .mask(LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black, location: 1)],
                                                     startPoint: .top, endPoint: .bottom))
                        }
                    }
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .clipped()
                .accessibilityHidden(true)
            info()
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, -56)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The page behind a hero: the background, tinted from the top with the artwork's colour.
struct MusicHeroBackground: ViewModifier {
    let artwork: URL?
    @State private var tint: Color?

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    DT.Color.backgroundPrimary
                    if let tint {
                        LinearGradient(colors: [tint.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                    }
                }
                .ignoresSafeArea()
                .animation(DT.Animation.motion(.easeInOut(duration: 0.4)), value: tint)
            }
            .task(id: artwork) {
                guard let artwork else { return }
                tint = await AverageColor.load(from: artwork)
            }
    }
}

extension View {
    func musicHeroBackground(_ artwork: URL?) -> some View { modifier(MusicHeroBackground(artwork: artwork)) }
}

/// Artwork filling the hero, cropped from the middle.
struct MusicHeroImage: View {
    let url: URL?

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                LinearGradient(colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}
