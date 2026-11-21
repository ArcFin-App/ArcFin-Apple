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
    @State private var switchStoredPIN: String? = nil
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
        SettingsForm {
            // ── Current profile ──────────────────────────────────────────
            if let active = activeProfile {
                Section {
                    NavigationLink {
                        ProfileDetailView(profile: active)
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
                        // onDelete below gives iOS its swipe gesture for free, but macOS has
                        // no swipe — a right-click is the only path to remove a profile there.
                        .contextMenu {
                            Button(role: .destructive) {
                                removeTarget = profile
                            } label: {
                                Label("Remove Profile", systemImage: "trash")
                            }
                        }
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
            Section {
                Toggle(isOn: $appLockUseFaceID) {
                    TVRowLabelText(title: "Use \(biometricLabel)", detail: "A faster unlock for a profile with a PIN, which Arcfin asks for on launch and when you come back. The PIN always works too.")
                }
            } header: {
                Text("App Lock")
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .tint(DT.Color.accent)
        .navigationTitle("Profiles")
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
                storedPIN: switchStoredPIN,
                resetToken: switchPINResetToken,
                errorMessage: switchPINError,
                onCancel: {
                    switchTarget = nil
                    switchPINError = nil
                },
                onComplete: { entered in
                    if entered == switchStoredPIN {
                        authManager.switchTo(target)
                        switchTarget = nil
                        switchPINError = nil
                        Task { await pins.load(authManager: authManager) }
                    } else {
                        switchPINError = String(localized: "Incorrect PIN")
                        switchPINResetToken += 1
                    }
                }
            )
        }
    }

    // MARK: - Actions

    private func handleTapOtherProfile(_ profile: ServerCredential) {
        guard pins.hasPIN(profile.id) else {
            authManager.switchTo(profile)
            Task { await pins.load(authManager: authManager) }
            return
        }
        switchPINError = nil
        switchPINResetToken = 0
        Task {
            switchStoredPIN = await authManager.pin(for: profile.id)
            // Explicitly switching to a specific profile from Settings (unlike the boot-time
            // lock screen) is a deliberate "become this person" action already gated behind
            // having the device unlocked — Face ID here just confirms the device owner again,
            // same as the PIN would, so it's offered first with the PIN as fallback instead
            // of skipping straight to the PIN pad.
            if appLockUseFaceID, await attemptBiometrics(for: profile) {
                authManager.switchTo(profile)
                await pins.load(authManager: authManager)
            } else {
                switchTarget = profile
            }
        }
    }

    // Face ID is the only biometry iOS/iPadOS devices in this fleet ship with, but Macs
    // pair the same LAContext API with Touch ID instead — asking canEvaluatePolicy first
    // populates biometryType so the toggle/footer name the capability actually on this Mac.
    private var biometricLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : "Face ID"
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
