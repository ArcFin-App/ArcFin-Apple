// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// Which profiles on this device have a PIN, for the lists of profiles and servers.
@MainActor @Observable
final class ProfilePINStates {
    private(set) var states: [UUID: Bool] = [:]

    func hasPIN(_ profileID: UUID) -> Bool {
        states[profileID] == true
    }

    func load(authManager: AuthManager) async {
        var states: [UUID: Bool] = [:]
        for profile in authManager.profiles {
            states[profile.id] = await authManager.pin(for: profile.id) != nil
        }
        self.states = states
    }
}
