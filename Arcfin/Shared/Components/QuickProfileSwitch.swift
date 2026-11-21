// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

/// A button whose tap runs `action` and whose long press lists the other profiles to switch
/// to; a PIN-locked one asks for its PIN first, as Switch Server does. With only one profile
/// it's a plain button.
struct QuickProfileSwitchButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Content

    @Environment(AuthManager.self) private var authManager
    @State private var pins = ProfilePINStates()
    @State private var switchTarget: ServerCredential?
    @State private var storedPIN: String?
    @State private var resetToken = 0
    @State private var pinError: String?

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
                        storedPIN: storedPIN,
                        resetToken: resetToken,
                        errorMessage: pinError,
                        onCancel: {
                            switchTarget = nil
                            pinError = nil
                        },
                        onComplete: { entered in
                            if entered == storedPIN {
                                authManager.switchTo(target)
                                switchTarget = nil
                                pinError = nil
                            } else {
                                pinError = String(localized: "Incorrect PIN")
                                resetToken += 1
                            }
                        }
                    )
                }
        }
    }

    private func choose(_ profile: ServerCredential) {
        HapticManager.impact(.light)
        if pins.hasPIN(profile.id) {
            pinError = nil
            resetToken = 0
            Task {
                storedPIN = await authManager.pin(for: profile.id)
                switchTarget = profile
            }
        } else {
            authManager.switchTo(profile)
        }
    }
}
