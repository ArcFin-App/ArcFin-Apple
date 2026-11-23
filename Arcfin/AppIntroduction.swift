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
    static let onboardingVersion = 1
    static let whatsNewVersion = 5

    enum Presentation: Equatable {
        case onboarding, whatsNew
    }

    /// What's showing, or waiting for the splash and the lock to finish.
    var presentation: Presentation?

    static let onboardingKey = "arcfin.introduction.onboardingSeen"
    static let whatsNewKey = "arcfin.introduction.whatsNewSeen"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
    func finishOnboarding() {
        defaults.set(Self.onboardingVersion, forKey: Self.onboardingKey)
        defaults.set(Self.whatsNewVersion, forKey: Self.whatsNewKey)
        presentation = nil
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
