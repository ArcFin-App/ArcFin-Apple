// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// The extra headers being edited in Custom Headers, saved to the Keychain.
@MainActor @Observable
final class CustomHeadersModel {
    var headers = CustomHTTPHeaders.all
    private(set) var errorMessage: String?

    func save() {
        let kept = headers.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || !$0.value.isEmpty }
        do {
            try CustomHTTPHeaders.save(kept)
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
