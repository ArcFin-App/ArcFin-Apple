// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import OSLog

public enum Telemetry: Sendable {

    static let subsystem = "com.psmattas.arcfin"

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// An error for a public log line: its domain, code and message. A URL error's full
    /// description has the address it failed on, query (and token) and all.
    public static func summary(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
