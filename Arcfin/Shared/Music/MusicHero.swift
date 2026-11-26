// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The top of an album, artist or playlist page: the whole square cover across the width from
/// the top of the screen, under the navigation bar, carrying on below as a blurred copy of
/// itself that fades into the page, as Now Playing does. Play and Shuffle sit at the foot of
/// the cover, and the names over the soft part below it.
struct MusicHero<Art: View, Info: View, Heading: View>: View {
    let play: () -> Void
    let shuffle: () -> Void
    var canPlay = true
    @ViewBuilder let art: (CGSize) -> Art
    /// Over the foot of the cover, just above Play and Shuffle.
    @ViewBuilder let heading: () -> Heading
    @ViewBuilder let info: () -> Info

    /// How far below the art the blurred copy reaches.
    private let extent: CGFloat = 1.16
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The whole square, or on a wide window a strip across it, as the title pages' backdrop
    /// is: on an iPad the square across the detail column was taller than the screen.
    private var maxArtHeight: CGFloat {
        sizeClass == .regular ? min(PlatformMetrics.musicHeroMaxHeight, 520) : PlatformMetrics.musicHeroMaxHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            // Square to the page's width up to the cap, then the full width at the cap, all in
            // one layout pass: a width read back into state moved the glass Shuffle button a
            // second time in the same frame.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: maxArtHeight)
                .frame(maxWidth: .infinity)
                // The blurred copy carries on below the cover, under the names and the songs,
                // instead of taking space of its own: the names sat a growing gap below Play.
                .overlay(alignment: .top) {
                    GeometryReader { proxy in
                        artwork(side: proxy.size.width, artHeight: proxy.size.height)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay {
                    GeometryReader { proxy in
                        VStack(spacing: 14) {
                            heading()
                            buttons
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DT.Spacing.pagePad)
                        .frame(height: max(proxy.size.height - 22, 0), alignment: .bottom)
                    }
                }
            info()
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Spacing.pagePad)
                // Over the soft foot of the cover, just below Play and Shuffle.
                .padding(.top, -6)
        }
        .frame(maxWidth: .infinity)
    }

    private func artwork(side: CGFloat, artHeight: CGFloat) -> some View {
        let height = artHeight * extent
        return ZStack(alignment: .top) {
            // Larger than the space, so the blur's soft edges fall outside it.
            art(CGSize(width: side, height: height))
                .frame(width: side, height: height)
                .scaleEffect(1.3)
                .blur(radius: 40)
                .frame(width: side, height: height)
                .clipped()
            art(CGSize(width: side, height: artHeight))
                .frame(width: side, height: artHeight)
                .clipped()
                // Darker toward the foot, so the buttons read on a light cover.
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.84),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .frame(width: side, height: height, alignment: .top)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                     .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
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

extension MusicHero where Heading == EmptyView {
    init(play: @escaping () -> Void, shuffle: @escaping () -> Void, canPlay: Bool = true,
         @ViewBuilder art: @escaping (CGSize) -> Art, @ViewBuilder info: @escaping () -> Info) {
        self.init(play: play, shuffle: shuffle, canPlay: canPlay, art: art, heading: { EmptyView() }, info: info)
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
