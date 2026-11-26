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
        // Sized by the page, not the artwork: a fill-scaled backdrop is wider than its column,
        // and as an overlay it can't push the page out past the edges or make the page's
        // width depend on the window's.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay {
                GeometryReader { proxy in
                    ZStack(alignment: .top) {
                        fallback
                        if let url {
                            // Sharp over the top three quarters, its end dissolving into a
                            // blurred copy of itself that carries on below, as a title's page does.
                            image(url)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .scaleEffect(1.35)
                                .blur(radius: 40)
                            image(url)
                                .frame(width: proxy.size.width, height: proxy.size.height * 0.78)
                                .clipped()
                                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                                             .init(color: .clear, location: 1)],
                                                     startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.68),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipped()
        .accessibilityHidden(true)
    }

    private func image(_ url: URL) -> some View {
        CachedAsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
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

/// The top of a title's page, as Home's hero and an artist's page open: the artwork across the
/// whole width from the top of the screen (the poster, standing, on a phone; the backdrops,
/// one after another, on a wider screen), with the logo or name, details and badges at its
/// foot over a dark scrim, fading into the page.
struct ShowcaseHero<Fallback: View, Content: View>: View {
    let urls: [URL]
    var portrait = false
    var landscapeHeight: CGFloat = 420
    /// Where the crop holds the artwork: the top keeps a face in a person's photo.
    var focus: Alignment = .center
    @ViewBuilder var fallback: Fallback
    @ViewBuilder var content: Content

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Sized by the page, not the artwork: a fill-scaled image is wider than its column,
        // and as an overlay it can't push the page past the edges (#325, #345).
        sized
            .frame(maxWidth: .infinity)
            // The blur carries on below the hero's own space, under whatever the page shows
            // next, instead of pushing it down.
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    artwork.frame(width: proxy.size.width, height: proxy.size.height * extent)
                }
                .allowsHitTesting(false)
            }
            .overlay {
                GeometryReader { proxy in
                    VStack(spacing: 10) { content }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, DT.Spacing.pagePad)
                        .padding(.bottom, proxy.size.height * 0.04)
                        .frame(height: proxy.size.height, alignment: .bottom)
                }
                // White over the scrim in light mode too.
                .environment(\.colorScheme, .dark)
            }
            .task(id: urls) { await rotate() }
    }

    /// How far the blurred copy carries on below the artwork's end, as an artist's page does,
    /// so the artwork's own edge is never seen.
    private let extent: CGFloat = 1.3

    @ViewBuilder
    private var sized: some View {
        if portrait {
            Color.clear.aspectRatio(0.72, contentMode: .fit).frame(maxHeight: 640)
        } else {
            Color.clear.frame(height: landscapeHeight)
        }
    }

    /// The artwork sharp at the top, its end dissolving into a blurred copy of itself that
    /// carries on below it and fades into the page, as an artist's page and Now Playing do.
    private var artwork: some View {
        GeometryReader { proxy in
            let artHeight = proxy.size.height / extent
            ZStack(alignment: .top) {
                fallback
                if urls.indices.contains(index) {
                    let url = urls[index]
                    ZStack(alignment: .top) {
                        image(url)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.35)
                            .blur(radius: 44)
                        image(url)
                            .frame(width: proxy.size.width, height: artHeight)
                            .clipped()
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                                         .init(color: .clear, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    .id(url)
                    .transition(.opacity)
                }
                // Enough to read white text on a light image, without hiding the blur.
                LinearGradient(stops: [.init(color: .clear, location: 0.35),
                                       .init(color: .black.opacity(0.35), location: 0.68),
                                       .init(color: .black.opacity(0.5), location: 0.88)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72),
                                     .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .clipped()
        .accessibilityHidden(true)
    }

    private func image(_ url: URL) -> some View {
        CachedAsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: focus)
            } else {
                // Something to hang the load on: an empty view never starts it.
                Color.clear
            }
        }
    }

    /// One backdrop after another while there are several, unless motion is reduced.
    private func rotate() async {
        index = 0
        guard urls.count > 1, !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(DT.Animation.motion(.easeInOut(duration: 1))) { index = (index + 1) % urls.count }
        }
    }
}

extension ShowcaseHero where Fallback == LinearGradient {
    init(urls: [URL], portrait: Bool = false, landscapeHeight: CGFloat = 420, @ViewBuilder content: () -> Content) {
        self.init(urls: urls, portrait: portrait, landscapeHeight: landscapeHeight, fallback: {
            LinearGradient(colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }, content: content)
    }
}

/// A title's logo where the server has one, otherwise its name, in white over artwork.
struct ShowcaseTitle: View {
    let logoURL: URL?
    let name: String
    var logoSize = CGSize(width: 280, height: 100)
    var nameStyle: Font.TextStyle = .largeTitle

    var body: some View {
        Group {
            if let logoURL {
                CachedAsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .frame(maxWidth: logoSize.width, maxHeight: logoSize.height)
                            .shadow(color: .black.opacity(0.5), radius: 10)
                    case .empty:
                        // Its space kept while it loads, so the name doesn't flash up first.
                        Color.clear.frame(height: logoSize.height)
                    default:
                        nameText
                    }
                }
            } else {
                nameText
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(.isHeader)
    }

    private var nameText: some View {
        Text(verbatim: name)
            .font(.system(nameStyle, weight: .heavy))
            .foregroundStyle(.white)
            .tracking(-0.5)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
            .shadow(color: .black.opacity(0.6), radius: 10)
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.textPrimary.opacity(0.12), lineWidth: 1))
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
            .animation(DT.Animation.motion(.easeInOut(duration: 0.4)), value: tint)
        }
    }
}
