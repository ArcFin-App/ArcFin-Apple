// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The welcome tour: on first launch before the server address, and again from Settings.
struct OnboardingView: View {
    /// Signed in already (taken again from Settings): the last page closes the tour rather
    /// than leading to the server address.
    let isSignedIn: Bool
    let onFinish: () -> Void

    @State private var model = OnboardingModel()

    private enum Control: Hashable { case back, next, skip }
    @FocusState private var focus: Control?

    private var pages: [OnboardingPage] {
        var pages: [OnboardingPage] = []
        pages.append(OnboardingPage(
            art: .logo,
            title: "Welcome to Arcfin",
            message: "Your Jellyfin movies, shows, music and Live TV, in an app made for iPhone, iPad, Mac, Apple TV and Apple Watch."
        ))
        pages.append(OnboardingPage(
            art: .symbol("house"),
            title: "Everything in One Place",
            message: "Home picks up where you left off and shows what's just arrived on your server.",
            highlights: [
                ("play.circle", "Continue Watching and Next Up, in step with your other devices"),
                ("square.grid.2x2", "Every library, with filters, sorting and collections"),
                ("magnifyingglass", "Search across your whole server, or inside a library"),
                ("chart.bar", "Stats for what you watch and listen to"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("music.note"),
            title: "All Your Music",
            message: "Your music library on the big screen: albums, artists, playlists and Made for You.",
            highlights: [
                ("quote.bubble", "Lyrics alongside Now Playing"),
                ("play.circle", "A Now Playing tab while music plays"),
                ("mic", "Ask Siri to \"Play … in Arcfin\" from the remote"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("tv"),
            title: "Live TV",
            message: "If your server has Live TV, watch it here with the guide, recordings and reminders.",
            highlights: [
                ("gobackward", "Pause and rewind a channel"),
                ("record.circle", "Record a programme or a whole series"),
                ("rectangle.on.rectangle", "Your favourite channels in the Top Shelf"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("play.rectangle"),
            title: "Plays Almost Anything",
            message: "Arcfin picks the right player for each video. You can choose one yourself in Settings › Playback.",
            highlights: [
                ("forward.end", "Skip intros, recaps and credits"),
                ("captions.bubble", "Subtitles and audio tracks in your languages"),
                ("hand.draw", "Scrub on the Siri Remote's touch surface"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("person.2.wave.2"),
            title: "Watch Together",
            message: "Play in sync with friends and family, wherever they are.",
            highlights: [
                ("person.2", "SyncPlay with anyone on your server"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("sparkle.magnifyingglass"),
            title: "Discover and Request",
            message: "Connect Seerr in Settings to find new movies and shows and ask for them on your server.",
            highlights: [
                ("flame", "Trending, popular and upcoming titles"),
                ("bookmark", "A watchlist for what you want to see"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("person.crop.circle.badge.checkmark"),
            title: "One App for the Whole Household",
            message: "Everyone signs in with their own Jellyfin account and gets their own Home and progress.",
            highlights: [
                ("server.rack", "Add more servers and switch between them"),
                ("lock", "Lock a profile with a PIN"),
                ("figure.and.child.holdinghands", "Your server's parental controls apply here too"),
                ("person.2", "Always Ask Who's Watching, when Apple TV opens"),
            ]
        ))
        if isSignedIn {
            pages.append(OnboardingPage(
                art: .symbol("checkmark.circle"),
                title: "You're All Set",
                message: "Find this tour and what's new in each version in Settings, under About."
            ))
        } else {
            pages.append(OnboardingPage(
                art: .symbol("server.rack"),
                title: "Connect Your Server",
                message: "Next, enter your Jellyfin server's address and sign in, or set this Apple TV up from your iPhone or iPad. Servers on your network show up by themselves."
            ))
        }
        return pages
    }

    private var isLast: Bool { model.isLast(of: pages.count) }

    private var primaryTitle: LocalizedStringKey {
        guard isLast else { return "Continue" }
        return isSignedIn ? "Done" : "Get Started"
    }

    var body: some View {
        let pages = pages
        let page = pages[min(model.index, pages.count - 1)]
        VStack(spacing: 0) {
            HStack(spacing: 120) {
                PageArt(art: page.art, size: 340)
                    .frame(width: 520)
                VStack(alignment: .leading, spacing: 36) {
                    Text(page.title)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(page.message)
                        .font(.title3)
                        .foregroundStyle(DT.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !page.highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(Array(page.highlights.enumerated()), id: \.offset) { _, highlight in
                                HStack(spacing: 24) {
                                    Image(systemName: highlight.icon)
                                        .foregroundStyle(DT.Color.accent)
                                        .frame(width: 56)
                                        .accessibilityHidden(true)
                                    Text(highlight.text)
                                        .foregroundStyle(DT.Color.textPrimary)
                                }
                                .font(.headline)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: 960, alignment: .leading)
            }
            .id(model.index)
            .transition(model.pageTransition)
            .frame(maxHeight: .infinity)

            ZStack {
                PageDots(index: model.index, count: pages.count)
                HStack(spacing: 32) {
                    Button(action: back) {
                        TVHeroButtonLabel(icon: "chevron.left", text: "Back")
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .focused($focus, equals: .back)
                    .disabled(model.index == 0)
                    .opacity(model.index == 0 ? 0 : 1)

                    Spacer()

                    if !isLast {
                        Button(action: onFinish) {
                            TVHeroButtonLabel(icon: "forward.end", text: "Skip")
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .focused($focus, equals: .skip)
                    }

                    Button(action: next) {
                        TVHeroButtonLabel(icon: isLast ? "checkmark" : "chevron.right",
                                          text: primaryTitle, isPrimary: true)
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .focused($focus, equals: .next)
                }
            }
            .padding(.top, 40)
        }
        .padding(.horizontal, 100)
        .padding(.vertical, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                DT.Color.backgroundPrimary
                IntroductionGlow(size: 900).offset(x: -560, y: -60)
            }
            .ignoresSafeArea()
        }
        .animation(DT.Animation.standard, value: model.index)
        .defaultFocus($focus, .next)
        // A button that disappears (Back on the first page, Skip on the last) can leave
        // nothing focused, so focus goes back to the main button on every page.
        .onChange(of: model.index) { focus = .next }
        // Menu steps back a page, and on the first page skips the tour.
        .onExitCommand(perform: model.index > 0 ? back : onFinish)
    }

    private func next() {
        model.next(of: pages.count, finish: onFinish)
    }

    private func back() {
        model.back()
    }
}

#Preview {
    OnboardingView(isSignedIn: false, onFinish: {})
}
