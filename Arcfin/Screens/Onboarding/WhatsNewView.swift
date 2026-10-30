// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct WhatsNewItem {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
}

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        var items: [WhatsNewItem] = []
        items.append(WhatsNewItem(icon: "forward.end",
                                  title: "Skip Intros in Downloads",
                                  detail: "Downloaded movies and episodes now offer to skip the recap, intro, credits and preview, just like streaming, and skip them for you if you've turned that on."))
        #if os(tvOS)
        items.append(WhatsNewItem(icon: "play.tv",
                                  title: "Trailers on Home",
                                  detail: "The featured title's trailer now plays all the way through while the details fade away. For sound, turn on Hero Trailer Sound in Settings › Appearance."))
        items.append(WhatsNewItem(icon: "textformat.abc",
                                  title: "Jump to a Letter",
                                  detail: "In a library sorted by name, pick a letter under Filter & Sort to jump straight to it."))
        #else
        items.append(WhatsNewItem(icon: "textformat.abc",
                                  title: "Jump to a Letter",
                                  detail: "In a library sorted by name, use the A to Z index at the edge to jump straight to a letter."))
        #endif
        items.append(WhatsNewItem(icon: "wand.and.rays",
                                  title: "Help for Videos That Won't Play",
                                  detail: "If a video won't play, or HDR or Dolby Vision looks dim or off-colour, new switches in Settings › Playback › Codec Compatibility have your server convert it."))
        items.append(WhatsNewItem(icon: "checkmark.circle",
                                  title: "Already in Your Library",
                                  detail: "Discover, Search and Seerr pages show which titles you already have, so you won't request them twice."))
        #if os(tvOS)
        items.append(WhatsNewItem(icon: "hand.draw",
                                  title: "Scrub with the Touch Surface",
                                  detail: "Glide across the Siri Remote's touch surface to move freely through a movie or episode, then click to jump there."))
        #endif
        items.append(WhatsNewItem(icon: "person.badge.key",
                                  title: "Signing In and Out",
                                  detail: "If your server stops accepting your sign-in, Arcfin asks you to sign in again instead of showing empty pages. Signing out of your last profile asks first and removes your sign-ins from this device. Downloads stay."))
        items.append(WhatsNewItem(icon: "server.rack",
                                  title: "Clearer Server Setup",
                                  detail: "When an address doesn't work, setup tells you why, and servers that redirect to another address now play reliably."))
        items.append(WhatsNewItem(icon: "clock.arrow.circlepath",
                                  title: "Progress That Keeps Up",
                                  detail: "Title pages show where you stopped as soon as you close the player."))
        #if os(tvOS)
        items.append(WhatsNewItem(icon: "tv",
                                  title: "Tidier Apple TV Pages",
                                  detail: "Home, title pages, Stats and Settings are evenly spaced, easier to read and simpler to get around with the remote."))
        #endif
        items.append(WhatsNewItem(icon: "sparkles",
                                  title: "A Tour of Arcfin",
                                  detail: "New to Arcfin, or want a refresher? Take the tour any time from Settings."))
        return items
    }
}

/// The card that says what changed in this version: once after an update, and from Settings.
struct WhatsNewView: View {
    let onDone: () -> Void

    #if os(tvOS)
    @FocusState private var continueFocused: Bool
    #endif

    var body: some View {
        #if os(tvOS)
        tvBody
        #else
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DT.Spacing.xl) {
                    header
                    VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                        ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { _, item in
                            IntroductionFeatureRow(icon: item.icon, title: item.title, detail: item.detail)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, DT.Spacing.lg)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            LoginPrimaryButton(title: String(localized: "Continue"), action: onDone)
                .keyboardShortcut(.defaultAction)
                .padding(.horizontal, 28)
                .padding(.vertical, DT.Spacing.md)
                .frame(maxWidth: 520)
        }
        .screenBackground()
        #endif
    }

    private var header: some View {
        VStack(spacing: DT.Spacing.sm) {
            Image("ArcfinLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 64 * 0.225, style: .continuous))
                .shadow(color: DT.Color.accent.opacity(0.35), radius: 18)
                .accessibilityHidden(true)
            Text("What's New in Arcfin")
                .font(.largeTitle.bold())
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    #if os(tvOS)
    private var tvBody: some View {
        HStack(alignment: .center, spacing: 120) {
            VStack(spacing: DT.Spacing.lg) {
                header
                Button(action: onDone) {
                    TVHeroButtonLabel(icon: "checkmark", text: "Continue", isPrimary: true)
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .focused($continueFocused)
            }
            .frame(width: 560)

            VStack(alignment: .leading, spacing: 44) {
                ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { _, item in
                    IntroductionFeatureRow(icon: item.icon, title: item.title, detail: item.detail)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                DT.Color.backgroundPrimary
                IntroductionGlow().offset(x: -520, y: -120)
            }
            .ignoresSafeArea()
        }
        .defaultFocus($continueFocused, true)
    }
    #endif
}

/// An accent-tinted symbol beside a title and a sentence, as in Apple's own What's New cards.
struct IntroductionFeatureRow: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: DT.Spacing.md) {
            Image(systemName: icon)
                .scaledFont(size: 26, weight: .medium)
                .foregroundStyle(DT.Color.accent)
                .frame(width: 44 * DT.Scale.font)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(DT.Color.textPrimary)
                Text(detail)
                    .scaledFont(size: 15)
                    .foregroundStyle(DT.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The soft cyan light the splash screen glows with, behind the tour and the card.
struct IntroductionGlow: View {
    var size: CGFloat = 560

    var body: some View {
        RadialGradient(
            colors: [DT.Color.accent.opacity(0.28), DT.Color.accentDeep.opacity(0.08), .clear],
            center: .center, startRadius: 0, endRadius: size / 2
        )
        .frame(width: size, height: size)
        .blur(radius: 30)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    WhatsNewView(onDone: {})
}
