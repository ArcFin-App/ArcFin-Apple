// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import SyncEngine
@testable import Arcfin

@MainActor
struct AppIntroductionTests {
    private let defaults: UserDefaults

    init() {
        let suite = "AppIntroductionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func freshInstallShowsTheTour() {
        #expect(AppIntroduction(defaults: defaults).presentation == .onboarding)
    }

    @Test func finishingTheTourAlsoCountsThisVersionsNewsAsSeen() {
        AppIntroduction(defaults: defaults).finishOnboarding()
        #expect(AppIntroduction(defaults: defaults).presentation == nil)
    }

    @Test func updatingFromBeforeTheTourShowsWhatsNew() {
        defaults.set(UUID().uuidString, forKey: "arcfin.activeProfileID")
        #expect(AppIntroduction(defaults: defaults).presentation == .whatsNew)
    }

    @Test func whatsNewStaysAwayOnceDismissed() {
        defaults.set(UUID().uuidString, forKey: "arcfin.activeProfileID")
        AppIntroduction(defaults: defaults).finishWhatsNew()
        #expect(AppIntroduction(defaults: defaults).presentation == nil)
    }

    @Test func raisingAVersionShowsItAgain() {
        defaults.set(AppIntroduction.onboardingVersion, forKey: AppIntroduction.onboardingKey)
        defaults.set(AppIntroduction.whatsNewVersion - 1, forKey: AppIntroduction.whatsNewKey)
        #expect(AppIntroduction(defaults: defaults).presentation == .whatsNew)

        defaults.set(AppIntroduction.onboardingVersion - 1, forKey: AppIntroduction.onboardingKey)
        #expect(AppIntroduction(defaults: defaults).presentation == .onboarding)
    }

    @Test func settingsCanShowEitherAgain() {
        let introduction = AppIntroduction(defaults: defaults)
        introduction.finishOnboarding()
        introduction.showWhatsNew()
        #expect(introduction.presentation == .whatsNew)
        introduction.showOnboarding()
        #expect(introduction.presentation == .onboarding)
    }

    @Test func seenFlagsStayOnThisDevice() {
        #expect(!SettingsSyncRegistry.allKeys.contains(AppIntroduction.onboardingKey))
        #expect(!SettingsSyncRegistry.allKeys.contains(AppIntroduction.whatsNewKey))
    }
}
