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
    private var isDeciding = false

    func hasPIN(_ profile: ServerCredential) -> Bool {
        pinStates[profile.id] == true
    }

    /// Decided from the PIN as read now, not from `pinStates`, which only draws the locks and
    /// may not have loaded yet.
    func select(_ profile: ServerCredential, authManager: AuthManager, onUnlock: @escaping () -> Void) {
        guard !isDeciding else { return }
        isDeciding = true
        HapticManager.impact(.light)
        Task {
            defer { isDeciding = false }
            let stored = await authManager.storedPIN(for: profile.id)
            guard stored != .none else {
                unlock(as: profile, authManager: authManager, onUnlock: onUnlock)
                return
            }
            errorMessage = AuthManager.PINCheck.message(opening: stored, for: profile.id)
            resetToken = 0
            pinTarget = profile
        }
    }

    func enter(_ entered: String, for target: ServerCredential, authManager: AuthManager, onUnlock: @escaping () -> Void) {
        Task {
            let result = await authManager.checkPIN(entered, for: target.id)
            guard pinTarget?.id == target.id else { return }
            guard result == .correct else {
                errorMessage = result.message
                resetToken += 1
                return
            }
            errorMessage = nil
            unlock(as: target, authManager: authManager, onUnlock: onUnlock)
        }
    }

    func cancelPIN() {
        pinTarget = nil
        errorMessage = nil
    }

    func unlock(as profile: ServerCredential, authManager: AuthManager, onUnlock: () -> Void) {
        PINAttempts.reset(for: profile.id)
        if profile.id != authManager.state.credential?.id {
            authManager.switchTo(profile)
        }
        onUnlock()
    }

    func loadPINStates(authManager: AuthManager) async {
        var states: [UUID: Bool] = [:]
        for profile in authManager.profiles {
            states[profile.id] = await authManager.storedPIN(for: profile.id) != .none
        }
        pinStates = states
    }
}
