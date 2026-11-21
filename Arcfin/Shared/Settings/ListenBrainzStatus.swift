// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

/// Under the ListenBrainz page's test button: a refused token, or listens still to send.
struct ListenBrainzStatusFooter: View {
    let model: ListenBrainzTokenModel

    var body: some View {
        if model.isRefused {
            Text("ListenBrainz turned this token down. Nothing is sent until you save a new one.")
                .font(.caption)
                .foregroundStyle(DT.Color.palette("F43F5E"))
        } else if model.pendingCount > 0, !model.savedToken.isEmpty {
            Text("Listens waiting to be sent: \(model.pendingCount)")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }
}

/// Goes up whenever a profile's token is saved or removed, or ListenBrainz refuses it, so
/// what shows its status updates, wherever the change came from.
@MainActor @Observable
final class ListenBrainzState {
    static let shared = ListenBrainzState()
    private(set) var revision = 0
    func changed() { revision += 1 }
}

/// The ListenBrainz row's status in Integrations, like TMDB's and Seerr's.
struct ListenBrainzStatusPill: View {
    let profile: UUID?

    var body: some View {
        let _ = ListenBrainzState.shared.revision
        if let profile, ListenBrainzCredential.load(profile: profile) != nil {
            if MusicScrobbler.isRefused(profile) {
                Text("Token Refused").font(.caption2).foregroundStyle(DT.Color.palette("F43F5E"))
            } else {
                Text("Connected").font(.caption2).foregroundStyle(DT.Color.palette("10b981"))
            }
        }
    }
}
