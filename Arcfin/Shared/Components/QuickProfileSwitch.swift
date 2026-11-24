// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

/// A button whose tap runs `action` and whose long press lists the other profiles to switch
/// to; a PIN-locked one asks for Face ID or Touch ID when that's on, then its PIN, as Settings ›
/// Profiles does. With only one profile it's a plain button.
struct QuickProfileSwitchButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Content

    @Environment(AuthManager.self) private var authManager
    @State private var pins = ProfilePINStates()
    @State private var switchTarget: ServerCredential?
    @State private var resetToken = 0
    @State private var pinError: String?
    @AppStorage("appLockUseFaceID") private var appLockUseFaceID = true

    private var others: [ServerCredential] {
        authManager.profiles.filter { $0.id != authManager.state.credential?.id }
    }

    /// Server names only when the profiles are on more than one server.
    private var showsServer: Bool {
        Set(authManager.profiles.map { $0.baseURL.host ?? $0.baseURL.absoluteString }).count > 1
    }

    var body: some View {
        if others.isEmpty {
            Button(action: action, label: label)
        } else {
            Menu {
                    Section("Switch Profile") {
                        ForEach(others) { profile in
                            Button { choose(profile) } label: {
                                Label {
                                    Text(profile.displayName)
                                    if showsServer, let host = profile.baseURL.host { Text(host) }
                                } icon: {
                                    Image(systemName: pins.hasPIN(profile.id) ? "lock.fill" : "person.crop.circle")
                                }
                            }
                        }
                    }
            } label: {
                label()
            } primaryAction: {
                action()
            }
            .menuIndicator(.hidden)
                .task { await pins.load(authManager: authManager) }
                .appSheet(item: $switchTarget) { target in
                    PINEntrySheet(
                        title: String(localized: "Switch to \(target.displayName)"),
                        subtitle: target.baseURL.host,
                        pinLength: PINLength.stored(target.id),
                        resetToken: resetToken,
                        errorMessage: pinError,
                        onCancel: {
                            switchTarget = nil
                            pinError = nil
                        },
                        onComplete: { entered in
                            Task {
                                let result = await authManager.checkPIN(entered, for: target.id)
                                guard switchTarget?.id == target.id else { return }
                                if result == .correct {
                                    authManager.switchTo(target)
                                    switchTarget = nil
                                    pinError = nil
                                } else {
                                    pinError = result.message
                                    resetToken += 1
                                }
                            }
                        }
                    )
                }
        }
    }

    /// Decided from the PIN as read now; `pins` only draws the locks and may not have loaded.
    private func choose(_ profile: ServerCredential) {
        HapticManager.impact(.light)
        Task {
            let stored = await authManager.storedPIN(for: profile.id)
            guard stored != .none else {
                authManager.switchTo(profile)
                return
            }
            // As in Settings › Profiles: Face ID or Touch ID first, the PIN pad if it fails.
            if appLockUseFaceID, await Biometrics.confirm(reason: String(localized: "Switch to \(profile.displayName)")) {
                PINAttempts.reset(for: profile.id)
                authManager.switchTo(profile)
                return
            }
            pinError = AuthManager.PINCheck.message(opening: stored, for: profile.id)
            resetToken = 0
            switchTarget = profile
        }
    }
}
