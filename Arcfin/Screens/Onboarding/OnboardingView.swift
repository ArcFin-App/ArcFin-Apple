// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

private struct OnboardingPage {
    enum Art {
        case logo
        case symbol(String)
    }

    let art: Art
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var highlights: [(icon: String, text: LocalizedStringResource)] = []
}

/// The welcome tour: on first launch before the server address, and again from Settings.
struct OnboardingView: View {
    /// Signed in already (taken again from Settings): the last page closes the tour rather
    /// than leading to the server address.
    let isSignedIn: Bool
    let onFinish: () -> Void

    @State private var index = 0
    @State private var movingForward = true

    #if os(tvOS)
    private enum Control: Hashable { case back, next, skip }
    @FocusState private var focus: Control?
    #elseif os(macOS)
    @FocusState private var pagerFocused: Bool
    #endif

    private var pages: [OnboardingPage] {
        var pages: [OnboardingPage] = []
        pages.append(OnboardingPage(
            art: .logo,
            title: "Welcome to Arcfin",
            message: "Your Jellyfin movies, shows and collections, in an app made for iPhone, iPad, Mac and Apple TV."
        ))
        pages.append(OnboardingPage(
            art: .symbol("house"),
            title: "Everything in One Place",
            message: "Home picks up where you left off and shows what's just arrived on your server.",
            highlights: [
                ("play.circle", "Continue Watching and Next Up, in step with your other devices"),
                ("square.grid.2x2", "Every library, with filters, sorting and collections"),
                ("magnifyingglass", "Search across your whole server"),
            ]
        ))
        var playback: [(icon: String, text: LocalizedStringResource)] = [
            ("forward.end", "Skip intros, recaps and credits"),
            ("captions.bubble", "Subtitles and audio tracks in your languages"),
        ]
        #if os(tvOS)
        playback.append(("hand.draw", "Scrub on the Siri Remote's touch surface"))
        #else
        playback.append(("pip", "Picture in Picture while you do something else"))
        #endif
        pages.append(OnboardingPage(
            art: .symbol("play.rectangle"),
            title: "Plays Almost Anything",
            message: "Arcfin picks the right player for each video. You can choose one yourself in Settings › Playback.",
            highlights: playback
        ))
        #if !os(tvOS)
        pages.append(OnboardingPage(
            art: .symbol("arrow.down.circle"),
            title: "Take It With You",
            message: "Download movies and episodes to watch without a connection. What you watch offline syncs back once you're online.",
            highlights: [
                ("wand.and.stars", "Smart Downloads keep the next episodes of a show ready"),
                ("airplane", "Turn on Offline Mode to see only what's on this device"),
            ]
        ))
        #endif
        var together: [(icon: String, text: LocalizedStringResource)] = [
            ("person.2", "SyncPlay with anyone on your server"),
        ]
        #if os(iOS)
        together.append(("shareplay", "SharePlay over FaceTime"))
        together.append(("tv.badge.wifi", "AirPlay and Chromecast to the big screen"))
        #elseif os(macOS)
        together.append(("shareplay", "SharePlay over FaceTime"))
        together.append(("airplay.video", "AirPlay to the big screen"))
        #endif
        pages.append(OnboardingPage(
            art: .symbol("person.2.wave.2"),
            title: "Watch Together",
            message: "Play in sync with friends and family, wherever they are.",
            highlights: together
        ))
        var discover: [(icon: String, text: LocalizedStringResource)] = [
            ("flame", "Trending, popular and upcoming titles"),
            ("bookmark", "A watchlist for what you want to see"),
        ]
        #if !os(tvOS)
        discover.append(("bell.badge", "A notification when a request is ready to watch"))
        #endif
        pages.append(OnboardingPage(
            art: .symbol("sparkle.magnifyingglass"),
            title: "Discover and Request",
            message: "Connect Seerr in Settings to find new movies and shows and ask for them on your server.",
            highlights: discover
        ))
        var profiles: [(icon: String, text: LocalizedStringResource)] = [
            ("server.rack", "Add more servers and switch between them"),
            ("lock", "Lock a profile with a PIN"),
            ("figure.and.child.holdinghands", "Your server's parental controls apply here too"),
        ]
        #if os(iOS)
        profiles[1] = ("faceid", "Lock a profile with a PIN or Face ID")
        #endif
        pages.append(OnboardingPage(
            art: .symbol("person.crop.circle.badge.checkmark"),
            title: "One App for the Whole Household",
            message: "Everyone signs in with their own Jellyfin account and gets their own Home and progress.",
            highlights: profiles
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
                message: "Next, enter your Jellyfin server's address and sign in. Servers on your network show up by themselves."
            ))
        }
        return pages
    }

    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        let pages = pages
        let page = pages[min(index, pages.count - 1)]
        #if os(tvOS)
        tvLayout(page: page, count: pages.count)
        #else
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.body.weight(.medium))
                    .foregroundStyle(DT.Color.textSecondary)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .keyboardShortcut(.cancelAction)
                    .shown(!isLast)
            }
            .padding(.horizontal, DT.Spacing.lg)

            // Centred when the page fits; scrolls at the largest text sizes.
            ViewThatFits(in: .vertical) {
                paged(page)
                ScrollView { paged(page) }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: .infinity)
            #if os(iOS)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            #endif

            VStack(spacing: DT.Spacing.lg) {
                PageDots(index: index, count: pages.count)
                HStack(spacing: DT.Spacing.sm) {
                    #if os(macOS)
                    if index > 0 {
                        Button("Back", action: back)
                            .controlSize(.large)
                            .buttonStyle(.glass)
                    }
                    #endif
                    LoginPrimaryButton(title: primaryTitle, action: next)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, DT.Spacing.md)
            .frame(maxWidth: 520)
        }
        .padding(.top, DT.Spacing.xs)
        .background {
            ZStack {
                DT.Color.backgroundPrimary
                IntroductionGlow(size: 640).offset(y: -180)
            }
            .ignoresSafeArea()
        }
        .animation(DT.Animation.standard, value: index)
        #if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .focused($pagerFocused)
        .onAppear { pagerFocused = true }
        .onKeyPress(.rightArrow) { next(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
        #endif
        #endif
    }

    // MARK: - Page

    private func paged(_ page: OnboardingPage) -> some View {
        pageContent(page)
            .id(index)
            .transition(pageTransition)
            .padding(.horizontal, 28)
            .padding(.vertical, DT.Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
    }

    private func pageContent(_ page: OnboardingPage) -> some View {
        VStack(spacing: DT.Spacing.lg) {
            PageArt(art: page.art)
            VStack(spacing: DT.Spacing.sm) {
                Text(page.title)
                    .scaledFont(size: 30, weight: .bold)
                    .foregroundStyle(DT.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(page.message)
                    .scaledFont(size: 17)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !page.highlights.isEmpty {
                VStack(alignment: .leading, spacing: DT.Spacing.md) {
                    ForEach(Array(page.highlights.enumerated()), id: \.offset) { _, highlight in
                        HStack(alignment: .firstTextBaseline, spacing: DT.Spacing.sm) {
                            Image(systemName: highlight.icon)
                                .foregroundStyle(DT.Color.accent)
                                .frame(width: 28 * DT.Scale.font)
                                .accessibilityHidden(true)
                            Text(highlight.text)
                                .foregroundStyle(DT.Color.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .scaledFont(size: 16)
                    }
                }
                .padding(DT.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.Color.backgroundSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
            }
        }
    }

    private var primaryTitle: String {
        guard isLast else { return String(localized: "Continue") }
        return isSignedIn ? String(localized: "Done") : String(localized: "Get Started")
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func next() {
        guard !isLast else { return onFinish() }
        movingForward = true
        index += 1
    }

    private func back() {
        guard index > 0 else { return }
        movingForward = false
        index -= 1
    }

    #if os(iOS)
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -60 {
                    if !isLast { next() }
                } else if value.translation.width > 60 {
                    back()
                }
            }
    }
    #endif

    // MARK: - Apple TV

    #if os(tvOS)
    private var tvPrimaryTitle: LocalizedStringKey {
        guard isLast else { return "Continue" }
        return isSignedIn ? "Done" : "Get Started"
    }

    private func tvLayout(page: OnboardingPage, count: Int) -> some View {
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
            .id(index)
            .transition(pageTransition)
            .frame(maxHeight: .infinity)

            ZStack {
                PageDots(index: index, count: count)
                HStack(spacing: 32) {
                    Button(action: back) {
                        TVHeroButtonLabel(icon: "chevron.left", text: "Back")
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .focused($focus, equals: .back)
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0 : 1)

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
                                          text: tvPrimaryTitle, isPrimary: true)
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
        .animation(DT.Animation.standard, value: index)
        .defaultFocus($focus, .next)
        // A button that disappears (Back on the first page, Skip on the last) can leave
        // nothing focused, so focus goes back to the main button on every page.
        .onChange(of: index) { focus = .next }
        // Menu steps back a page, and on the first page skips the tour.
        .onExitCommand(perform: index > 0 ? back : onFinish)
    }
    #endif
}

private struct PageArt: View {
    let art: OnboardingPage.Art
    var size: CGFloat = 132

    var body: some View {
        ZStack {
            IntroductionGlow(size: size * 2.2)
            switch art {
            case .logo:
                Image("ArcfinLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                    .shadow(color: DT.Color.accent.opacity(0.45), radius: 30)
                    .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: size, height: size)
                    .glassEffect(.regular.tint(DT.Color.accent.opacity(0.12)), in: .circle)
            }
        }
        .frame(height: size * 1.25)
        .accessibilityHidden(true)
    }
}

/// Where the reader is in the tour, read out as "Page 2 of 7".
private struct PageDots: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 8 * DT.Scale.font) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? DT.Color.accent : DT.Color.textPrimary.opacity(0.2))
                    .frame(width: (dot == index ? 22 : 8) * DT.Scale.font, height: 8 * DT.Scale.font)
            }
        }
        .animation(DT.Animation.fast, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
    }
}

#Preview {
    OnboardingView(isSignedIn: false, onFinish: {})
}
