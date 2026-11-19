// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The top of an album or playlist page, like a title's detail page: its artwork blown up and
/// blurred behind, fading into the page, with the cover in front. The cover is full size while
/// this album or playlist plays and settles back smaller when it's paused, as in Now Playing.
struct MusicHero<Cover: View, Info: View>: View {
    let backdrop: URL?
    let isPlaying: Bool
    @ViewBuilder let cover: () -> Cover
    @ViewBuilder let info: () -> Info
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let backdropHeight: CGFloat = 440
    private let coverSide: CGFloat = 260

    var body: some View {
        VStack(spacing: DT.Spacing.md) {
            cover()
                .frame(width: coverSide, height: coverSide)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                .scaleEffect(isPlaying || reduceMotion ? 1 : 0.86)
                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: isPlaying)
                .padding(.top, 96)
            info()
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Spacing.pagePad)
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { backdropView }
    }

    /// Sized by the page, not the artwork, so the fill-scaled image can't push the page wider.
    private var backdropView: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: backdropHeight)
            .overlay {
                ZStack {
                    CachedAsyncImage(url: backdrop) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill().blur(radius: 36).saturation(1.2)
                        }
                    }
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                }
            }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .clipped()
            .accessibilityHidden(true)
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
