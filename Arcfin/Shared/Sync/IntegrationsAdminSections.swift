// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

enum IntegrationsConfirm {
    case removeSeerrKey, removeTmdbKey
    case drop(IntegrationsAdmin.Queued)

    var title: LocalizedStringKey {
        switch self {
        case .removeSeerrKey: "Remove the Seerr Key?"
        case .removeTmdbKey: "Remove the TMDB Key?"
        case .drop: "Drop This Request?"
        }
    }

    var action: LocalizedStringKey {
        switch self {
        case .removeSeerrKey, .removeTmdbKey: "Remove Key"
        case .drop: "Drop"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .removeSeerrKey: "The apps go back to signing in to Seerr themselves."
        case .removeTmdbKey: "The apps go back to using their own TMDB key, if they have one."
        case .drop: "It won't be sent to Seerr."
        }
    }
}

/// The dashboard's wording for Seerr's last check and where the master key comes from.
enum SeerrHealth {
    static func stateText(_ state: String?) -> String? {
        switch state {
        case nil: nil
        case "ok": String(localized: "Seerr answered.")
        case "keyRejected": String(localized: "Seerr refused the key. Check it in Seerr › Settings › General.")
        case "unreachable": String(localized: "This server can't reach Seerr at that address.")
        case "error": String(localized: "Seerr had a problem.")
        case let other?: other
        }
    }

    static func line(_ admin: IntegrationsAdmin) -> String? {
        guard var text = stateText(admin.seerrState) else { return nil }
        if admin.seerrState != "ok", let message = admin.seerrMessage, !message.isEmpty { text += " (\(message))" }
        if let checked = admin.seerrChecked { text += " " + checked.formatted(.relative(presentation: .named)) }
        return text
    }

    static func vaultText(_ source: String) -> String {
        switch source {
        case "environment":
            String(localized: "The master key comes from the ARCFIN_SYNC_MASTER_KEY environment variable, outside Jellyfin's folders: the strongest setup.")
        case "file":
            String(localized: "The master key comes from the file named by ARCFIN_SYNC_MASTER_KEY_FILE, outside Jellyfin's folders: the strongest setup.")
        default:
            String(localized: "Keys are encrypted with AES-256-GCM using a master key the plugin made in its own data folder, readable by the server's account only. For more protection, keep the master key outside Jellyfin's folders: set ARCFIN_SYNC_MASTER_KEY to a 32-byte key in base64 (openssl rand -base64 32), or ARCFIN_SYNC_MASTER_KEY_FILE to a file holding one (e.g. a Docker secret), then save the keys again.")
        }
    }
}

/// Whether a write-only key is saved. The key itself never comes back from the server.
private struct KeyStateRow: View {
    let title: LocalizedStringKey
    let isSet: Bool

    var body: some View {
        LabeledContent {
            Text(isSet ? "Saved" : "Not set")
                .foregroundStyle(isSet ? DT.Color.accent : DT.Color.textSecondary)
        } label: {
            TVRowLabelText(title: title)
        }
        .tvReadOnlyRow()
    }
}

struct SeerrKeySection: View {
    let admin: IntegrationsAdmin
    @Binding var url: String
    @Binding var publicURL: String
    @Binding var key: String
    @Binding var addUsers: Bool
    let isBusy: Bool
    let onRemove: () -> Void

    var body: some View {
        Section {
            TextField("Local address, as this server reaches it", text: $url, prompt: Text(verbatim: "http://seerr:5055"))
                .urlFieldKeyboard()
                .autocorrectionDisabled()
                .tvListRow()
            TextField("Public address, as people reach it", text: $publicURL, prompt: Text(verbatim: "https://requests.example.com"))
                .urlFieldKeyboard()
                .autocorrectionDisabled()
                .tvListRow()
            KeyStateRow(title: "API Key", isSet: admin.seerrKeySet)
            SecureField("API Key", text: $key,
                        prompt: Text(admin.seerrKeySet ? "Leave empty to keep the saved key" : "API key"))
                .tvListRow()
            Toggle(isOn: $addUsers) {
                TVRowLabelText(title: "Add people to Seerr the first time they use it")
            }
            .tvListRow()
            if admin.seerrKeySet {
                Button(role: .destructive, action: onRemove) {
                    Text("Remove Key")
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
                .formRowButton()
                .disabled(isBusy)
            }
        } header: {
            Text(verbatim: "Seerr")
        } footer: {
            Text("The public address becomes everyone's Seerr address in Arcfin, unless Settings sets one. The API key is in Seerr › Settings › General › API Key. It can't be shown again once saved.")
        }
    }
}

struct TMDBKeySection: View {
    let isSet: Bool
    @Binding var key: String
    let isBusy: Bool
    let onRemove: () -> Void

    var body: some View {
        Section {
            KeyStateRow(title: "API Key or Read Access Token", isSet: isSet)
            SecureField("API key or read access token", text: $key,
                        prompt: Text(isSet ? "Leave empty to keep the saved key" : "API key or read access token"))
                .tvListRow()
            if isSet {
                Button(role: .destructive, action: onRemove) {
                    Text("Remove Key")
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
                .formRowButton()
                .disabled(isBusy)
            }
        } header: {
            Text(verbatim: "TMDB")
        }
    }
}

/// Requests made while Seerr couldn't be reached. Choosing one offers to drop it.
struct SeerrQueueSection: View {
    let queue: [IntegrationsAdmin.Queued]
    let users: [ArcfinSyncAdminUser]
    let isBusy: Bool
    let onDrop: (IntegrationsAdmin.Queued) -> Void
    let onSendNow: () -> Void

    var body: some View {
        Section {
            if queue.isEmpty {
                Text("Nothing waiting.")
                    .foregroundStyle(DT.Color.textSecondary)
                    .tvReadOnlyRow()
            }
            ForEach(queue) { queued in
                Button { onDrop(queued) } label: {
                    TVRowLabelText(verbatim: users.name(of: queued.userId), detail: "\(detail(queued))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .formRowButton()
                .tvListRow()
                .accessibilityHint(Text("Drop"))
            }
            if !queue.isEmpty {
                Button("Send Now", action: onSendNow)
                    .formRowButton()
                    .disabled(isBusy)
            }
        } header: {
            Text("Waiting to Send")
        } footer: {
            Text("Requests made while Seerr couldn't be reached. The server tries again every few minutes for three days.")
        }
    }

    private func detail(_ queued: IntegrationsAdmin.Queued) -> String {
        var parts = [queued.created.formatted(.relative(presentation: .named)),
                     String(localized: "tried \(queued.attempts)×")]
        if let error = queued.lastError, !error.isEmpty { parts.append(error) }
        return parts.joined(separator: " · ")
    }
}
