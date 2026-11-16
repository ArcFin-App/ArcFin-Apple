// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Security
import WatchConnectivity

/// The iPhone's active profile, as the iPhone sends it: the server and the header it signs its
/// own requests with, so the watch acts as the phone toward Jellyfin. Sent again on a profile
/// change, and cleared on sign-out.
struct WatchCredential: Codable, Equatable {
    var serverURL: URL
    var authHeader: String
    var userID: String
    var accessToken: String
}

@MainActor @Observable
final class WatchSignIn: NSObject {
    static let shared = WatchSignIn()

    private(set) var credential: WatchCredential? = Keychain.load()

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func apply(_ context: [String: Any]) {
        if context["signedOut"] as? Bool == true {
            credential = nil
            Keychain.save(nil)
            return
        }
        guard let server = (context["serverURL"] as? String).flatMap(URL.init(string:)),
              let header = context["authHeader"] as? String,
              let user = context["userID"] as? String,
              let token = context["accessToken"] as? String else { return }
        let received = WatchCredential(serverURL: server, authHeader: header, userID: user, accessToken: token)
        guard received != credential else { return }
        credential = received
        Keychain.save(received)
    }
}

extension WatchSignIn: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let context = session.receivedApplicationContext
        guard !context.isEmpty, let data = try? JSONSerialization.data(withJSONObject: context) else { return }
        Task { @MainActor in WatchSignIn.shared.apply(Self.decode(data)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: applicationContext) else { return }
        Task { @MainActor in WatchSignIn.shared.apply(Self.decode(data)) }
    }

    // The dictionary isn't Sendable, so it crosses to the main actor as JSON.
    nonisolated private static func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

/// The token is a password to the server, so it's kept in the keychain, not in defaults.
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.psmattas.Arcfin.watch",
        kSecAttrAccount as String: "credential",
    ]

    static func load() -> WatchCredential? {
        var search = query
        search[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WatchCredential.self, from: data)
    }

    static func save(_ credential: WatchCredential?) {
        SecItemDelete(query as CFDictionary)
        guard let credential, let data = try? JSONEncoder().encode(credential) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
