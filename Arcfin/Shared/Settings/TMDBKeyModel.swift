// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore
import SeerrAPI

/// The TMDB key being typed in Settings, the one saved in the Keychain, and testing it.
@MainActor @Observable
final class TMDBKeyModel {
    var key = TMDBCredential.load() ?? ""
    private(set) var savedKey = TMDBCredential.load() ?? ""
    var testResult: String?
    private(set) var isTesting = false

    func save(seerrRepo: SeerrRepository) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != savedKey else { return }
        try? TMDBCredential.save(trimmed)
        savedKey = trimmed
        seerrRepo.reloadTMDB()
        if !trimmed.isEmpty { Task { await seerrRepo.loadDiscover() } }
    }

    func testConnection(seerrRepo: SeerrRepository) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        isTesting = true
        testResult = nil
        Task {
            do {
                _ = try await TMDBClient(key: trimmed).trending()
                testResult = "✓ " + String(localized: "Connected to TMDB")
                save(seerrRepo: seerrRepo)
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
