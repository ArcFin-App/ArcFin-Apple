// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The welcome tour: on first launch before the server address, and again from Settings.
struct OnboardingView: View {
    /// Signed in already (taken again from Settings): the last page closes the tour rather
    /// than leading to the server address.
    let isSignedIn: Bool
    let onFinish: () -> Void

    @State private var model = OnboardingModel()

    private var pages: [OnboardingPage] {
        var pages: [OnboardingPage] = []
        pages.append(OnboardingPage(
            art: .logo,
            title: "Welcome to Arcfin",
            message: "Your Jellyfin movies, shows, music and collections, in an app made for iPhone, iPad, Mac and Apple TV."
        ))
        pages.append(OnboardingPage(
            art: .symbol("house"),
            title: "Everything in One Place",
            message: "Home picks up where you left off and shows what's just arrived on your server.",
            highlights: [
                ("play.circle", "Continue Watching and Next Up, in step with your other devices"),
                ("square.grid.2x2", "Every library, with filters, sorting and collections"),
                ("music.note", "Your music, by album, artist and playlist"),
                ("magnifyingglass", "Search across your whole server"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("play.rectangle"),
            title: "Plays Almost Anything",
            message: "Arcfin picks the right player for each video. You can choose one yourself in Settings › Playback.",
            highlights: [
                ("forward.end", "Skip intros, recaps and credits"),
                ("captions.bubble", "Subtitles and audio tracks in your languages"),
                ("pip", "Picture in Picture while you do something else"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("arrow.down.circle"),
            title: "Take It With You",
            message: "Download movies and episodes to watch without a connection. What you watch offline syncs back once you're online.",
            highlights: [
                ("wand.and.stars", "Smart Downloads keep the next episodes of a show ready"),
                ("airplane", "Turn on Offline Mode to see only what's on this device"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("person.2.wave.2"),
            title: "Watch Together",
            message: "Play in sync with friends and family, wherever they are.",
            highlights: [
                ("person.2", "SyncPlay with anyone on your server"),
                ("shareplay", "SharePlay over FaceTime"),
                ("tv.badge.wifi", "AirPlay and Chromecast to the big screen"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("sparkle.magnifyingglass"),
            title: "Discover and Request",
            message: "Connect Seerr in Settings to find new movies and shows and ask for them on your server.",
            highlights: [
                ("flame", "Trending, popular and upcoming titles"),
                ("bookmark", "A watchlist for what you want to see"),
                ("bell.badge", "A notification when a request is ready to watch"),
            ]
        ))
        pages.append(OnboardingPage(
            art: .symbol("person.crop.circle.badge.checkmark"),
            title: "One App for the Whole Household",
            message: "Everyone signs in with their own Jellyfin account and gets their own Home and progress.",
            highlights: [
                ("server.rack", "Add more servers and switch between them"),
                ("faceid", "Lock a profile with a PIN or Face ID"),
                ("figure.and.child.holdinghands", "Your server's parental controls apply here too"),
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
                message: "Next, enter your Jellyfin server's address and sign in. Servers on your network show up by themselves."
            ))
        }
        return pages
    }

    private var isLast: Bool { model.isLast(of: pages.count) }

    var body: some View {
        let pages = pages
        let page = pages[min(model.index, pages.count - 1)]
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
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)

            VStack(spacing: DT.Spacing.lg) {
                PageDots(index: model.index, count: pages.count)
                HStack(spacing: DT.Spacing.sm) {
                    // The swipe back isn't there for VoiceOver, Switch Control or a keyboard.
                    if model.index > 0 {
                        Button("Back", action: back)
                            .controlSize(.large)
                            .buttonStyle(.glass)
                    }
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
        .animation(DT.Animation.standard, value: model.index)
    }

    // MARK: - Page

    private func paged(_ page: OnboardingPage) -> some View {
        OnboardingPageContent(page: page)
            .id(model.index)
            .transition(model.pageTransition)
            .padding(.horizontal, 28)
            .padding(.vertical, DT.Spacing.lg)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
    }

    private var primaryTitle: String {
        guard isLast else { return String(localized: "Continue") }
        return isSignedIn ? String(localized: "Done") : String(localized: "Get Started")
    }

    private func next() {
        model.next(of: pages.count, finish: onFinish)
    }

    private func back() {
        model.back()
    }

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
}

#Preview {
    OnboardingView(isSignedIn: false, onFinish: {})
}
