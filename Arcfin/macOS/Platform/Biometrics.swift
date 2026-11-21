// SPDX-License-Identifier: AGPL-3.0-or-later

import LocalAuthentication

@MainActor
enum Biometrics {
    /// Macs pair the same LAContext API with Touch ID. Worked out once rather than in a view's
    /// body, where it ran on every redraw (#689); canEvaluatePolicy has to run first for
    /// biometryType to be filled in.
    static let label: String = {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : "Face ID"
    }()

    static func confirm(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        guard let success = try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ), success else { return false }
        return true
    }
}
