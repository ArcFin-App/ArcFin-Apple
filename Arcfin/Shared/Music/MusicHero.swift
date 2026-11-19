// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The top of an album, artist or playlist page: the whole square cover across the width from
/// the top of the screen, under the navigation bar, carrying on below as a blurred copy of
/// itself that fades into the page, as Now Playing does. Play and Shuffle sit at the foot of
/// the cover, and the names over the soft part below it.
struct MusicHero<Art: View, Info: View>: View {
    let play: () -> Void
    let shuffle: () -> Void
    var canPlay = true
    @ViewBuilder let art: (CGSize) -> Art
    @ViewBuilder let info: () -> Info

    /// How much taller than wide: the blurred part below the square.
    private let extent: CGFloat = 1.16

    var body: some View {
        VStack(spacing: 0) {
            // Sized by the page, so the art can't push it wider.
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(1 / extent, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        let side = proxy.size.width
                        ZStack(alignment: .top) {
                            // Larger than the space, so the blur's soft edges fall outside it.
                            art(proxy.size)
                                .frame(width: side, height: proxy.size.height)
                                .scaleEffect(1.3)
                                .blur(radius: 40)
                                .frame(width: side, height: proxy.size.height)
                                .clipped()
                            art(CGSize(width: side, height: side))
                                .frame(width: side, height: side)
                                .clipped()
                                // Darker toward the foot, so the buttons read on a light cover.
                                .overlay {
                                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                                }
                                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.84),
                                                             .init(color: .clear, location: 1)],
                                                     startPoint: .top, endPoint: .bottom))
                        }
                        .frame(width: side, height: proxy.size.height, alignment: .top)
                    }
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
                .overlay(alignment: .top) {
                    GeometryReader { proxy in
                        buttons
                            .frame(width: proxy.size.width)
                            .position(x: proxy.size.width / 2, y: proxy.size.width - 47)
                    }
                }
            info()
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Spacing.pagePad)
                // Over the soft part below the cover.
                .padding(.top, -36)
        }
        .frame(maxWidth: .infinity)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .frame(height: 50)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: shuffle) {
                Image(systemName: "shuffle")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shuffle")
        }
        .disabled(!canPlay)
        .opacity(canPlay ? 1 : 0.5)
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
