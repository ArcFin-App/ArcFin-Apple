// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import LocalAuthentication
import AuthCore

struct UsersView: View {
    var onExpand: (() -> Void)? = nil

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var pins = ProfilePINStates()
    @State private var switchTarget: ServerCredential? = nil
    @State private var switchPINResetToken = 0
    @State private var switchPINError: String? = nil
    @State private var showAddProfile = false
    @State private var removeTarget: ServerCredential?
    @AppStorage("appLockUseFaceID") private var appLockUseFaceID = true

    private var activeID: UUID? { authManager.state.credential?.id }

    private var activeProfile: ServerCredential? {
        authManager.profiles.first { $0.id == activeID }
    }

    private var otherProfiles: [ServerCredential] {
        authManager.profiles.filter { $0.id != activeID }
    }

    var body: some View {
        List {
            // ── Current profile ──────────────────────────────────────────
            if let active = activeProfile {
                Section {
                    NavigationLink {
                        ProfileDetailView(profile: active)
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        ProfileRowContent(
                            profile: active,
                            isActive: true,
                            hasPIN: pins.hasPIN(active.id)
                        )
                    }
                } header: { Text("Current Profile") }
            }

            // ── Other profiles ───────────────────────────────────────────
            if !otherProfiles.isEmpty {
                Section {
                    ForEach(otherProfiles) { profile in
                        Button {
                            handleTapOtherProfile(profile)
                        } label: {
                            ProfileRowContent(
                                profile: profile,
                                isActive: false,
                                hasPIN: pins.hasPIN(profile.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indices in
                        removeTarget = indices.first.map { otherProfiles[$0] }
                    }
                } header: { Text("Switch To") }
            }

            // ── Add profile ───────────────────────────────────────────────
            Section {
                Button("Add Profile", systemImage: "plus") {
                    onExpand?()
                    showAddProfile = true
                }
                .navigationDestination(isPresented: $showAddProfile) {
                    AddProfileFlowView()
                }
            }

            // ── App Lock ─────────────────────────────────────────────────
            if let biometricLabel {
                Section {
                    Toggle(isOn: $appLockUseFaceID) {
                        TVRowLabelText(title: "Use \(biometricLabel)", detail: "A faster unlock for a profile with a PIN, which Arcfin asks for on launch and when you come back. The PIN always works too.")
                    }
                } header: {
                    Text("App Lock")
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .tint(DT.Color.accent)
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await pins.load(authManager: authManager) }
        .onChange(of: authManager.profiles) { _, _ in Task { await pins.load(authManager: authManager) } }
        .confirmingProfileRemoval($removeTarget, signingOut: false, isLastProfile: false) { target in
            authManager.removeProfile(id: target.id)
        }
        // PIN entry sheet for switching to a protected profile
        .sheet(item: $switchTarget) { target in
            PINEntrySheet(
                title: String(localized: "Switch to \(target.displayName)"),
                subtitle: target.baseURL.host,
                resetToken: switchPINResetToken,
                errorMessage: switchPINError,
                onCancel: {
                    switchTarget = nil
                    switchPINError = nil
                },
                onComplete: { entered in
                    Task {
                        let result = await authManager.checkPIN(entered, for: target.id)
                        guard switchTarget?.id == target.id else { return }
                        if result == .correct {
                            authManager.switchTo(target)
                            switchTarget = nil
                            switchPINError = nil
                            await pins.load(authManager: authManager)
                        } else {
                            switchPINError = result.message
                            switchPINResetToken += 1
                        }
                    }
                }
            )
        }
    }

    // MARK: - Actions

    /// Decided from the PIN as read now; `pins` only draws the locks and may not have loaded.
    private func handleTapOtherProfile(_ profile: ServerCredential) {
        Task {
            let stored = await authManager.storedPIN(for: profile.id)
            guard stored != .none else {
                authManager.switchTo(profile)
                await pins.load(authManager: authManager)
                return
            }
            // Explicitly switching to a specific profile from Settings (unlike the boot-time
            // lock screen) is a deliberate "become this person" action already gated behind
            // having the device unlocked — Face ID here just confirms the device owner again,
            // same as the PIN would, so it's offered first with the PIN as fallback instead
            // of skipping straight to the PIN pad.
            if appLockUseFaceID, await attemptBiometrics(for: profile) {
                PINAttempts.reset(for: profile.id)
                authManager.switchTo(profile)
                await pins.load(authManager: authManager)
            } else {
                switchPINError = AuthManager.PINCheck.message(opening: stored, for: profile.id)
                switchPINResetToken = 0
                switchTarget = profile
            }
        }
    }

    /// Face ID or Touch ID (iPad Air, iPad mini, iPad and iPhone SE), or nil with neither.
    /// canEvaluatePolicy has to run first for biometryType to be filled in.
    private var biometricLabel: String? {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return nil
        }
    }

    private func attemptBiometrics(for profile: ServerCredential) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        guard let success = try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: String(localized: "Switch to \(profile.displayName)")
        ), success else { return false }
        return true
    }
}
