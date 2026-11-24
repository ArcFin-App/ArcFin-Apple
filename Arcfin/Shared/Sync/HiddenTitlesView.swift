// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// What this person hid from Continue Watching and Next Up, on every device, with Show Again.
struct HiddenTitlesView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var continueWatching: [MediaItem] = []
    @State private var nextUp: [MediaItem] = []
    @State private var isLoading = true

    private var companion: ServerCompanion { .shared }

    var body: some View {
        Form {
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if continueWatching.isEmpty && nextUp.isEmpty {
                Text("Nothing is hidden. Hide a title from Continue Watching or a show from Next Up by touching and holding it.")
                    .foregroundStyle(DT.Color.textSecondary)
                    .tvReadOnlyRow()
            } else {
                row(title: "Continue Watching", items: continueWatching, from: .continueWatching)
                row(title: "Next Up", items: nextUp, from: .nextUp)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Hidden Titles")
        .task { await load() }
    }

    @ViewBuilder
    private func row(title: LocalizedStringKey, items: [MediaItem], from row: HiddenRow) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    HStack {
                        Text(item.name)
                            .foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Button("Show Again") { showAgain(item, from: row) }
                            .buttonStyle(.bordered)
                            .tint(DT.Color.accent)
                    }
                }
            } header: {
                Text(title)
            } footer: {
                if row == .continueWatching {
                    Text("Titles come back by themselves once they're played again.")
                }
            }
        }
    }

    private func load() async {
        guard case .authenticated(let credential) = authManager.state else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let client = JellyfinMediaClient()
        let hidden = companion.hidden
        async let cw = client.getItems(credential: credential, authHeader: header, ids: hidden.continueWatching.map(\.itemId))
        async let up = client.getItems(credential: credential, authHeader: header, ids: hidden.nextUp.map(\.itemId))
        continueWatching = (try? await cw) ?? []
        nextUp = (try? await up) ?? []
        isLoading = false
    }

    private func showAgain(_ item: MediaItem, from row: HiddenRow) {
        Task {
            guard await companion.setHidden(false, itemID: item.id, from: row, authManager: authManager) else { return }
            if row == .nextUp { nextUp.removeAll { $0.id == item.id } } else { continueWatching.removeAll { $0.id == item.id } }
        }
    }
}

/// A signing key Arcfin won't trust by itself: the first one seen over plain HTTP, or one that
/// replaced the trusted key without its signature. Its fingerprint, worked out here, has to
/// match the one on the server's dashboard before the admin's commands are carried out.
struct ServerKeyChangedSection: View {
    @Environment(AuthManager.self) private var authManager
    @State private var typing = false
    @State private var typed = ""
    @State private var wrong = false
    @State private var reporting = false

    private var companion: ServerCompanion { .shared }

    var body: some View {
        if companion.keyWasReplaced {
            Section {
                Label("Your server's admin replaced its security key", systemImage: "key.horizontal")
                    .foregroundStyle(DT.Color.textPrimary)
                    .tvReadOnlyRow()
                Button("OK") { companion.keyWasReplaced = false }
                    .formRowButton()
            } footer: {
                Text("Arcfin checked the new key and now uses it for your admin's commands.")
            }
        }
        if let key = companion.changedKey ?? companion.unverifiedKey {
            let changed = companion.changedKey != nil
            let fingerprint = ServerCompanion.fingerprint(key)
            Section {
                Label(changed ? "The server's security key changed" : "Check your server's security key",
                      systemImage: changed ? "exclamationmark.shield" : "checkmark.shield")
                    .foregroundStyle(changed ? DT.Color.palette("f59e0b") : DT.Color.textPrimary)
                    .tvReadOnlyRow()
                LabeledContent("Fingerprint") {
                    Text(verbatim: fingerprint)
                        .font(.system(.body, design: .monospaced))
                }
                .tvReadOnlyRow()
                Button("It Matches") { typed = ""; typing = true }
                    .formRowButton()
                Button("It Doesn't Match", role: .destructive) { reporting = true }
                    .formRowButton()
            } footer: {
                Text(changed
                     ? "Arcfin ignores your admin's commands (clearing a PIN, locking a profile) until this is checked. Compare it with the fingerprint under Settings › Server on a device that already trusts your server, or with Arcfin Sync › Security on the server's dashboard."
                     : "This server is reached without HTTPS, so Arcfin can't be sure the key came from it. Compare it with the fingerprint under Settings › Server on another device that trusts your server, or with Arcfin Sync › Security on the server's dashboard. Until then, your admin's commands (clearing a PIN, locking a profile) aren't carried out.")
            }
            .alert("Type the Last 4 Characters", isPresented: $typing) {
                TextField("Last 4 characters", text: $typed)
                    .autocorrectionDisabled()
                Button("Check") {
                    if Self.endsMatch(typed, fingerprint) {
                        Task {
                            if changed { await companion.trustNewKey(authManager: authManager) }
                            else { await companion.confirmUnverifiedKey(authManager: authManager) }
                        }
                    } else {
                        wrong = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Type the last 4 characters of the fingerprint you're comparing with: on the other device or the dashboard, not this one.")
            }
            .alert("That Doesn't Match", isPresented: $wrong) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The key on this device isn't the one you compared with, so Arcfin won't trust it. If you typed it right, tap It Doesn't Match to tell your admin.")
            }
            .confirmationDialog("Tell your admin the key doesn't match?", isPresented: $reporting, titleVisibility: .visible) {
                Button("Tell My Admin", role: .destructive) { Task { await companion.reportMismatch(authManager: authManager) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Arcfin keeps ignoring this key. Your admin sees which device reported it; something on this network may be pretending to be your server.")
            }
        }
    }

    /// The typed characters against the fingerprint's last 4, ignoring case, spaces and colons.
    static func endsMatch(_ typed: String, _ fingerprint: String) -> Bool {
        let clean = { (text: String) in text.uppercased().filter { $0.isLetter || $0.isNumber } }
        let wanted = String(clean(fingerprint).suffix(4))
        return wanted.count == 4 && clean(typed) == wanted
    }
}

/// The fingerprint of the key this device trusts, so someone can compare another device with it.
struct ServerKeyFingerprintRow: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if let server = authManager.state.credential?.baseURL, let fingerprint = ServerCompanion.shared.trustedFingerprint(for: server) {
            LabeledContent("Security Key") {
                Text(verbatim: fingerprint)
                    .font(.system(.footnote, design: .monospaced))
            }
            .tvReadOnlyRow()
        }
    }
}

/// Seerr settings when the server's Arcfin Sync plugin holds the Seerr key.
struct SeerrThroughServerSection: View {
    var body: some View {
        Section {
            Label("Connected through your server", systemImage: "checkmark.shield")
                .foregroundStyle(DT.Color.textPrimary)
                .tvReadOnlyRow()
        } footer: {
            Text("Your server's admin has set up Seerr on the server, so there's nothing to sign in to here. Requests are made with your own Seerr account and limits, and the server sends any it couldn't deliver as soon as Seerr is back.")
        }
    }
}

/// Settings › TMDB when the server's Arcfin Sync plugin holds the TMDB key: nothing to enter or
/// keep on this device.
struct TMDBThroughServerView: View {
    var body: some View {
        SettingsForm {
            Section {
                Label("Connected through your server", systemImage: "checkmark.shield")
                    .foregroundStyle(DT.Color.textPrimary)
                    .tvReadOnlyRow()
            } footer: {
                Text("Your server's admin has set up TMDB on the server, so Arcfin uses the server's key and keeps none on this device. Any key saved here before has been removed.")
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("TMDB")
    }
}
