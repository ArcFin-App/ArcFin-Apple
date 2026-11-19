// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The top of an album or playlist page: the whole square cover across the width from the
/// top of the screen, under the navigation bar, with Play and Shuffle at its foot and only its
/// last edge fading into the page; the names follow below.
struct MusicHero<Art: View, Info: View>: View {
    let play: () -> Void
    let shuffle: () -> Void
    var canPlay = true
    @ViewBuilder let art: (CGSize) -> Art
    @ViewBuilder let info: () -> Info

    var body: some View {
        VStack(spacing: DT.Spacing.sm) {
            // Square to the page's width; sized by the page, so the art can't push it wider.
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        art(proxy.size)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                }
                // Darker toward the foot, so the buttons read on a light cover.
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
                .overlay(alignment: .bottom) { buttons.padding(.bottom, 22) }
            info()
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Spacing.pagePad)
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
