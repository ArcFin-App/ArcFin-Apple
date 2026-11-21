// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore
import JellyfinAPI

/// The ListenBrainz token being typed in Settings, the profile's saved one, and checking it.
@MainActor @Observable
final class ListenBrainzTokenModel {
    var token: String
    private(set) var savedToken: String
    var testResult: String?
    private(set) var isTesting = false
    private(set) var pendingCount: Int
    private let profile: UUID?

    init(profile: UUID?) {
        self.profile = profile
        let saved = profile.flatMap(ListenBrainzCredential.load(profile:)) ?? ""
        token = saved
        savedToken = saved
        pendingCount = profile.map { MusicScrobbler.pending($0).count } ?? 0
    }

    /// ListenBrainz turned the saved token down, here or while music played.
    var isRefused: Bool {
        _ = ListenBrainzState.shared.revision
        return profile.map(MusicScrobbler.isRefused) ?? false
    }

    var isTokenEmpty: Bool { token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func save() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile, trimmed != savedToken else { return }
        try? ListenBrainzCredential.save(trimmed, profile: profile)
        savedToken = trimmed
        MusicScrobbler.setRefused(false, profile: profile)
        AppServices.music.scrobbler.flush()
    }

    func remove() {
        token = ""
        testResult = nil
        save()
    }

    func testConnection() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        isTesting = true
        testResult = nil
        Task {
            do {
                if let name = try await ListenBrainzClient(token: trimmed, clientVersion: "").validate() {
                    testResult = String(localized: "✓ Connected as \(name)")
                    save()
                } else {
                    testResult = String(localized: "✗ ListenBrainz doesn't know this token.")
                }
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
