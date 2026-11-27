// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation

/// The welcome tour and the What's New card, and which of each this device has seen.
///
/// Each flag is a number rather than a yes/no, so a release can turn one back on. Raise
/// `onboardingVersion` when the tour changes enough that everyone should take it again; raise
/// `whatsNewVersion`, and rewrite `WhatsNew.items`, in a release that has news. Seen numbers
/// live in UserDefaults on purpose: per device, cleared with the app, and kept out of
/// SettingsSyncRegistry so another device can't mark them seen.
@MainActor
@Observable
final class AppIntroduction {
    static let onboardingVersion = 2
    static let whatsNewVersion = 10

    enum Presentation: Equatable {
        case onboarding, whatsNew
    }

    /// What's showing, or waiting for the splash and the lock to finish.
    var presentation: Presentation?

    static let onboardingKey = "arcfin.introduction.onboardingSeen"
    static let whatsNewKey = "arcfin.introduction.whatsNewSeen"

    private let defaults: UserDefaults
    /// Signed in or shown What's New before this launch: someone updating, who gets this
    /// version's news after the tour as well.
    private let isUpdating: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isUpdating = defaults.string(forKey: "arcfin.activeProfileID") != nil
            || defaults.object(forKey: Self.whatsNewKey) != nil
        // 0.2.0 and earlier had no tour. Someone who signed in on one of those is updating,
        // not new, so they get What's New instead of the welcome.
        if defaults.object(forKey: Self.onboardingKey) == nil,
           defaults.string(forKey: "arcfin.activeProfileID") != nil {
            defaults.set(Self.onboardingVersion, forKey: Self.onboardingKey)
        }
        if defaults.integer(forKey: Self.onboardingKey) < Self.onboardingVersion {
            presentation = .onboarding
        } else if defaults.integer(forKey: Self.whatsNewKey) < Self.whatsNewVersion {
            if WhatsNew.items.isEmpty {
                defaults.set(Self.whatsNewVersion, forKey: Self.whatsNewKey)
            } else {
                presentation = .whatsNew
            }
        }
    }

    /// Someone new has nothing to compare against, so this version's news counts as seen too.
    /// Someone updating gets What's New next, once the tour has gone: a second full-screen
    /// presentation started while the first is closing doesn't appear on Apple TV.
    func finishOnboarding() {
        defaults.set(Self.onboardingVersion, forKey: Self.onboardingKey)
        presentation = nil
        guard isUpdating, defaults.integer(forKey: Self.whatsNewKey) < Self.whatsNewVersion,
              !WhatsNew.items.isEmpty else {
            defaults.set(Self.whatsNewVersion, forKey: Self.whatsNewKey)
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.presentation == nil else { return }
            self.presentation = .whatsNew
        }
    }

    func finishWhatsNew() {
        defaults.set(Self.whatsNewVersion, forKey: Self.whatsNewKey)
        presentation = nil
    }

    func showOnboarding() {
        presentation = .onboarding
    }

    func showWhatsNew() {
        presentation = .whatsNew
    }
}
