// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var model = AppRootModel()
    @AppStorage("appLockUseFaceID") private var appLockUseFaceID = true
    @State private var showOfflineDocPicker = false
    @State private var offlinePickedURL: URL?
    @State private var navigateToOfflineLocalPlayer = false
    @State private var bypassSessionCheck = false

    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false

    private var phase: AppPhase {
        model.phase(offlineModeEnabled: offlineModeEnabled, bypassSessionCheck: bypassSessionCheck)
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
        case .checkingSession:
            SessionCheckingView(
                onSignInManually: { bypassSessionCheck = true },
                onGoOffline: { offlineModeEnabled = true }
            )
            .transition(.opacity)
        case .main:
            // The profile's access schedule, checked every minute.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                // context.date only drives the minute-by-minute check; the time compared is
                // the trusted one.
                if context.date > .distantPast, ProfileRules.shared.isWithinSchedule() {
                    MainTabView()
                } else {
                    AccessScheduleView(onSwitchProfile: { model.switchProfileFromSchedule() })
                }
            }
            .transition(.opacity)
        case .offline:
            NavigationStack {
                DownloadsView(goBackOnline: { offlineModeEnabled = false })
                    // Offline mode replaces the whole app with DownloadsView, which
                    // previously had no way to reach "On This Device" — the only local
                    // playback option left offline was Jellyfin downloads themselves.
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showOfflineDocPicker = true } label: {
                                Image(systemName: "folder")
                            }
                            .accessibilityLabel("Open local file")
                        }
                    }
                    .sheet(isPresented: $showOfflineDocPicker) {
                        DocumentPickerView { url in
                            offlinePickedURL = url
                            navigateToOfflineLocalPlayer = true
                        }
                    }
                    .navigationDestination(isPresented: $navigateToOfflineLocalPlayer) {
                        if let url = offlinePickedURL {
                            LocalPlayerView(url: url)
                                .toolbar(.hidden, for: .tabBar)
                        }
                    }
            }
            .transition(.opacity)
        }
    }

    var body: some View {
        ZStack {
            phaseContent

            if model.isShowing(.onboarding, phase: phase) {
                OnboardingView(isSignedIn: phase == .main) { model.introduction.finishOnboarding() }
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                    .zIndex(5)
            }

            if model.isAppLocked {
                AppLockView(useFaceID: appLockUseFaceID) { model.unlock() }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(DT.Animation.standard, value: phase)
        .animation(DT.Animation.standard, value: model.isAppLocked)
        .animation(DT.Animation.standard, value: model.introduction.presentation)
        .sheet(isPresented: model.introductionBinding(.whatsNew, phase: phase)) {
            WhatsNewView { model.introduction.finishWhatsNew() }
        }
        .modifier(AppRootLifecycle(model: model) { model.refreshOnForeground($0, modelContext: modelContext) })
    }
}

#Preview {
    ContentView()
}
