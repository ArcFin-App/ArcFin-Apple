// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Arcfin for Everyone › Seerr & TMDB: the keys this server uses for Seerr and TMDB on
/// everyone's behalf, and the Seerr requests waiting to be sent. Keys are write-only: they're
/// sent once and never shown or read back.
struct IntegrationsAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let users: [ArcfinSyncAdminUser]

    @State private var admin: IntegrationsAdmin?
    @State private var error: String?
    @State private var actionError: String?
    @State private var seerrURL = ""
    @State private var seerrPublicURL = ""
    @State private var seerrKey = ""
    @State private var tmdbKey = ""
    @State private var addSeerrUsers = false
    @State private var isBusy = false
    @State private var confirm: IntegrationsConfirm?
    @State private var testResult: String?
    private let client = ArcfinCompanionClient()

    var body: some View {
        SettingsForm {
            if let admin {
                AdminIntroSection(text: "With these set, Arcfin uses Seerr and TMDB through this server: the keys stay here, encrypted, and never reach anyone's device. Every Seerr call is made as the person using it, with their own Seerr permissions and request limits. Without them, the apps keep signing in to Seerr themselves.")
                SeerrKeySection(admin: admin, url: $seerrURL, publicURL: $seerrPublicURL, key: $seerrKey, addUsers: $addSeerrUsers,
                                isBusy: isBusy, onRemove: { confirm = .removeSeerrKey })
                Section {
                    Button {
                        Task { await saveSeerr() }
                    } label: {
                        Text(isBusy ? "Saving…" : "Save Seerr")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .formRowButton()
                    Button("Test Seerr") { Task { await test() } }
                        .formRowButton()
                } footer: {
                    if let health = SeerrHealth.line(admin) { Text(verbatim: health) }
                }
                .disabled(isBusy)
                TMDBKeySection(isSet: admin.tmdbKeySet, key: $tmdbKey, isBusy: isBusy, onRemove: { confirm = .removeTmdbKey })
                Section {
                    Button {
                        Task { await saveTMDB() }
                    } label: {
                        Text(isBusy ? "Saving…" : "Save TMDB Key")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .formRowButton()
                    .disabled(isBusy || tmdbKey.isEmpty)
                }
                SeerrQueueSection(queue: admin.queue, users: users, isBusy: isBusy,
                                  onDrop: { confirm = .drop($0) }, onSendNow: { Task { await sendNow() } })
                Section {
                    Text(verbatim: SeerrHealth.vaultText(admin.vaultKeySource))
                        .font(.subheadline)
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                } header: {
                    Text("Encryption")
                }
            } else {
                AdminPendingSection(error: error)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Seerr & TMDB")
        .task { await load() }
        .adminErrorAlert($actionError)
        .alert("Test Seerr", isPresented: Binding(get: { testResult != nil }, set: { if !$0 { testResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(testResult ?? "")
        }
        .confirmationPrompt(Text(confirm?.title ?? ""), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { pending in
            Button(pending.action, role: .destructive) { Task { await carryOut(pending) } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    private func show(_ next: IntegrationsAdmin) {
        admin = next
        seerrURL = next.seerrUrl ?? ""
        seerrPublicURL = next.seerrPublicUrl ?? ""
        addSeerrUsers = next.addSeerrUsers
        seerrKey = ""
        tmdbKey = ""
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            show(try await client.integrationsAdmin(credential: access.credential, authHeader: access.header))
        } catch {
            self.error = AdminSyncError.loadMessage()
        }
    }

    private func perform(_ call: (ServerCredential, String) async throws -> IntegrationsAdmin) async -> IntegrationsAdmin? {
        guard let access = authManager.arcfinSyncDevicesSession else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let next = try await call(access.credential, access.header)
            show(next)
            HapticManager.success()
            return next
        } catch {
            actionError = AdminSyncError.message(error)
            return nil
        }
    }

    /// Saves one card and keeps what's typed, unsaved, in the other.
    private func save(_ change: IntegrationsAdminChange) async {
        let typed = (url: seerrURL, publicURL: seerrPublicURL, key: seerrKey, tmdb: tmdbKey, addUsers: addSeerrUsers)
        let savedSeerr = change.tmdbKey == nil
        guard await perform({ try await client.saveIntegrations(change, credential: $0, authHeader: $1) }) != nil else { return }
        if savedSeerr {
            tmdbKey = typed.tmdb
        } else {
            (seerrURL, seerrPublicURL, seerrKey, addSeerrUsers) = (typed.url, typed.publicURL, typed.key, typed.addUsers)
        }
    }

    /// Seerr's address, key and setting only; TMDB's key is left as saved.
    private func saveSeerr(apiKey: String? = nil) async {
        await save(IntegrationsAdminChange(seerrUrl: seerrURL.trimmingCharacters(in: .whitespaces),
                                           seerrPublicUrl: seerrPublicURL.trimmingCharacters(in: .whitespaces),
                                           seerrApiKey: apiKey ?? (seerrKey.isEmpty ? nil : seerrKey),
                                           tmdbKey: nil, addSeerrUsers: addSeerrUsers))
    }

    /// TMDB's key only; Seerr stays as saved, whatever is typed in its fields.
    private func saveTMDB(key: String? = nil) async {
        guard let admin else { return }
        await save(IntegrationsAdminChange(seerrUrl: admin.seerrUrl, seerrPublicUrl: admin.seerrPublicUrl, seerrApiKey: nil,
                                           tmdbKey: key ?? tmdbKey, addSeerrUsers: admin.addSeerrUsers))
    }

    private func test() async {
        // What's typed, saved or not; testing saves nothing, so the typed values stay.
        let typed = (url: seerrURL, publicURL: seerrPublicURL, key: seerrKey, tmdb: tmdbKey, addUsers: addSeerrUsers)
        let url = typed.url.trimmingCharacters(in: .whitespaces)
        if let next = await perform({ try await client.testSeerr(url: url.isEmpty ? nil : url, apiKey: typed.key.isEmpty ? nil : typed.key,
                                                                 credential: $0, authHeader: $1) }) {
            (seerrURL, seerrPublicURL, seerrKey, tmdbKey, addSeerrUsers) = typed
            testResult = SeerrHealth.stateText(next.seerrState) ?? String(localized: "Add Seerr's local address and API key first.")
        }
    }

    private func sendNow() async {
        _ = await perform { try await client.sendQueued(credential: $0, authHeader: $1) }
    }

    private func carryOut(_ pending: IntegrationsConfirm) async {
        switch pending {
        case .removeSeerrKey:
            await saveSeerr(apiKey: "")
        case .removeTmdbKey:
            await saveTMDB(key: "")
        case .drop(let queued):
            _ = await perform { try await client.dropQueued(queued.id, credential: $0, authHeader: $1) }
        }
    }
}
