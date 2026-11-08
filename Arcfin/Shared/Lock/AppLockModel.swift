// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// Which profiles have a PIN, the one being unlocked and what was typed, shared by every
/// platform's `AppLockView`.
@MainActor @Observable
final class AppLockModel {
    private(set) var pinStates: [UUID: Bool] = [:]
    private(set) var pinTarget: ServerCredential?
    private(set) var errorMessage: String?
    private(set) var resetToken = 0
    private var storedPIN: String?

    func hasPIN(_ profile: ServerCredential) -> Bool {
        pinStates[profile.id] == true
    }

    func select(_ profile: ServerCredential, authManager: AuthManager, onUnlock: () -> Void) {
        HapticManager.impact(.light)
        guard pinStates[profile.id] == true else {
            unlock(as: profile, authManager: authManager, onUnlock: onUnlock)
            return
        }
        errorMessage = nil
        resetToken = 0
        Task {
            storedPIN = await authManager.pin(for: profile.id)
            pinTarget = profile
        }
    }

    func enter(_ entered: String, for target: ServerCredential, authManager: AuthManager, onUnlock: () -> Void) {
        guard entered == storedPIN else {
            errorMessage = String(localized: "Incorrect PIN")
            resetToken += 1
            return
        }
        errorMessage = nil
        unlock(as: target, authManager: authManager, onUnlock: onUnlock)
    }

    func cancelPIN() {
        pinTarget = nil
        errorMessage = nil
    }

    func unlock(as profile: ServerCredential, authManager: AuthManager, onUnlock: () -> Void) {
        if profile.id != authManager.state.credential?.id {
            authManager.switchTo(profile)
        }
        onUnlock()
    }

    func loadPINStates(authManager: AuthManager) async {
        var states: [UUID: Bool] = [:]
        for profile in authManager.profiles {
            states[profile.id] = await authManager.pin(for: profile.id) != nil
        }
        pinStates = states
    }
}
