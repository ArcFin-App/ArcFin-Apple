// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var model = AppRootModel()
    @AppStorage("appLockUseFaceID") private var appLockUseFaceID = true

    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    @AppStorage("libraryScreensaverEnabled") private var screensaverEnabled = true
    @AppStorage("libraryScreensaverMinutes") private var screensaverMinutes = 3
    @State private var showScreensaver = false
    @State private var idleTask: Task<Void, Never>?

    private var phase: AppPhase {
        model.phase(offlineModeEnabled: offlineModeEnabled)
    }

    // Extracted out of body — one giant ZStack combining this switch, the overlay ifs
    // below, and body's own long modifier chain made the whole expression too much for
    // the type checker to resolve in reasonable time. Splitting it into its own
    // @ViewBuilder gives the compiler a much smaller expression to solve on its own.
    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .splash:
            SplashView(isLoading: model.authManager.isChecking) { model.splashDone = true }
                .transition(.opacity)
        case .login:
            LoginRootView()
                .transition(.opacity)
        case .main:
            ScheduleGate(onSwitchProfile: { model.switchProfileFromSchedule() })
                .transition(.opacity)
        case .offline:
            NavigationStack {
                DownloadsView(goBackOnline: { offlineModeEnabled = false })
            }
            .transition(.opacity)
        }
    }

    var body: some View {
        ZStack {
            if model.showsContent(phase) {
                phaseContent
            } else {
                DT.Color.backgroundPrimary.ignoresSafeArea()
            }

            if model.isAppLocked {
                AppLockView(useFaceID: appLockUseFaceID) { model.unlock() }
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(DT.Animation.standard, value: phase)
        .animation(DT.Animation.standard, value: model.isAppLocked)
        .animation(DT.Animation.standard, value: model.introduction.presentation)
        // A cover, not an overlay: focus can't wander to the screen underneath.
        .fullScreenCover(isPresented: model.introductionBinding(.onboarding, phase: phase)) {
            OnboardingView(isSignedIn: phase == .main) { model.introduction.finishOnboarding() }
        }
        .fullScreenCover(isPresented: model.introductionBinding(.whatsNew, phase: phase)) {
            WhatsNewView { model.introduction.finishWhatsNew() }
        }
        .focusEffectDisabled()
        // Apple TV stays dark: its screens are full-bleed artwork, like the system TV app.
        .preferredColorScheme(.dark)
        // Focus moving is the remote being used; there's no other app-wide signal for it.
        .onReceive(NotificationCenter.default.publisher(for: UIFocusSystem.didUpdateNotification)) { _ in
            restartIdleTimer()
        }
        .onChange(of: showScreensaver) { _, shown in if !shown { restartIdleTimer() } }
        .onChange(of: screensaverEnabled) { restartIdleTimer() }
        .onChange(of: screensaverMinutes) { restartIdleTimer() }
        .fullScreenCover(isPresented: $showScreensaver) {
            LibraryScreensaverView { showScreensaver = false }
                .environment(model.mediaRepo)
        }
        .modifier(AppRootLifecycle(model: model) { newPhase in
            if newPhase == .active { restartIdleTimer() } else { idleTask?.cancel() }
        })
    }

    /// Settings › Appearance › Screensaver: shown after the chosen idle minutes anywhere but
    /// the player, the lock screen and sign-in.
    private func restartIdleTimer() {
        idleTask?.cancel()
        guard screensaverEnabled, !showScreensaver else { return }
        idleTask = Task {
            try? await Task.sleep(for: .seconds(screensaverMinutes * 60))
            guard !Task.isCancelled, phase == .main, !model.isAppLocked, scenePhase == .active,
                  ScreensaverHold.count == 0, model.mediaRepo.hasAnyContent else { return }
            showScreensaver = true
        }
    }
}

#Preview {
    ContentView()
}

/// The profile's access schedule, checked each minute. A task rather than a TimelineView: on
/// Apple TV a TimelineView could start redrawing everything under it every frame, as one did
/// on a title's page.
private struct ScheduleGate: View {
    let onSwitchProfile: () -> Void
    @State private var tick = Date()

    var body: some View {
        Group {
            // tick only drives the minute-by-minute check; the time compared is the trusted one.
            if tick > .distantPast, ProfileRules.shared.isWithinSchedule() {
                MainTabView()
            } else {
                AccessScheduleView(onSwitchProfile: onSwitchProfile)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                tick = .now
            }
        }
    }
}
