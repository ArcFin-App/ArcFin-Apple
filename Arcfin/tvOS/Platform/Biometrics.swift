// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Apple TV has no Face ID or Touch ID: the PIN pad is the only way in.
@MainActor
enum Biometrics {
    static func confirm(reason: String) async -> Bool { false }
}
