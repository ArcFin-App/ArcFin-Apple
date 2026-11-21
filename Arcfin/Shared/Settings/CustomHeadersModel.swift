// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// The extra headers being edited in Custom Headers, saved to the Keychain for one server:
/// the address being signed in to, or else the server of the profile in use.
@MainActor @Observable
final class CustomHeadersModel {
    var headers: [CustomHTTPHeaders.Header]
    private(set) var errorMessage: String?
    private let scope: CustomHTTPHeaders.Scope

    init(serverAddress: String? = nil) {
        if let serverAddress {
            scope = .address(serverAddress)
        } else if let credential = AppServices.authManager.state.credential {
            scope = .server(credential)
        } else {
            scope = .unassigned
        }
        headers = CustomHTTPHeaders.headers(in: scope)
    }

    /// Opened from sign-in before an address was entered: there's no server to send them to yet.
    var needsAddress: Bool {
        switch scope {
        case .server: false
        case .address(let address): address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .unassigned: true
        }
    }

    func save() {
        let kept = headers.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || !$0.value.isEmpty }
        do {
            try CustomHTTPHeaders.save(kept, in: scope)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't save the headers: \(error.localizedDescription)")
        }
    }

    func remove(_ id: CustomHTTPHeaders.Header.ID) {
        headers.removeAll { $0.id == id }
        save()
    }
}
