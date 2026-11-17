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

/// The ListenBrainz row's status in Integrations.
struct ListenBrainzStatusPill: View {
    let profile: UUID?
    @State private var status: Status = .off

    private enum Status { case off, connected, refused }

    var body: some View {
        Group {
            switch status {
            case .off: EmptyView()
            case .connected: Text("Connected").foregroundStyle(DT.Color.palette("10b981"))
            case .refused: Text("Token Refused").foregroundStyle(DT.Color.palette("F43F5E"))
            }
        }
        .font(.caption2)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        guard let profile, ListenBrainzCredential.load(profile: profile) != nil else {
            status = .off
            return
        }
        status = MusicScrobbler.isRefused(profile) ? .refused : .connected
    }
}
