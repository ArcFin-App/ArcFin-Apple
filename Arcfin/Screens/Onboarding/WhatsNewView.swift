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
        #if os(tvOS)
        items.append(WhatsNewItem(icon: "hand.draw",
                                  title: "Scrub with the Touch Surface",
                                  detail: "Glide across the Siri Remote's touch surface to move freely through a movie or episode, then click to jump there."))
        #endif
        items.append(WhatsNewItem(icon: "person.badge.key",
                                  title: "Signed Out? Sign Straight Back In",
                                  detail: "When your server stops accepting your sign-in, for example after a password change, Arcfin asks you to sign in again instead of showing empty pages."))
        items.append(WhatsNewItem(icon: "clock.arrow.circlepath",
                                  title: "Progress That Keeps Up",
                                  detail: "Title pages show where you stopped as soon as you close the player."))
        #if os(tvOS)
        items.append(WhatsNewItem(icon: "tv",
                                  title: "Tidier Apple TV Pages",
                                  detail: "Home stays on the featured title while it loads, and title, collection and Settings pages are evenly spaced and easier to read."))
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
