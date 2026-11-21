// SPDX-License-Identifier: AGPL-3.0-or-later

/// The Mac has no audio session to change, and doesn't offer What's Playing?.
enum ListeningSession {
    static func begin() async throws {}
    static func end() async {}
}
