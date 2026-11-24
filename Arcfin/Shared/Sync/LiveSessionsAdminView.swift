// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

enum LiveConfirm: Identifiable {
    case remove(LivePerson, code: String, fromParty: Bool)
    case endParty(LiveParty)
    case endPick(LivePickSession)

    var id: String {
        switch self {
        case .remove(let person, let code, _): "remove-\(code)-\(person.id)"
        case .endParty(let party): "party-\(party.code)"
        case .endPick(let session): "pick-\(session.code)"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .remove(let person, _, _): "Remove \(person.name)?"
        case .endParty: "End this watch party for everyone in it?"
        case .endPick: "End this Pick Together session for everyone in it?"
        }
    }

    var action: LocalizedStringKey {
        switch self {
        case .remove: "Remove"
        case .endParty, .endPick: "End"
        }
    }

    var message: LocalizedStringKey? {
        switch self {
        case .remove: "They can't join again with this code."
        case .endParty, .endPick: nil
        }
    }
}

/// Arcfin for Everyone › Happening Now: every watch party and Pick Together session on now or
/// scheduled, with the host's controls over each.
struct LiveSessionsAdminView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var live: LiveSessions?
    @State private var error: String?
    @State private var actionError: String?
    @State private var confirm: LiveConfirm?
    @State private var isBusy = false
    private let client = ArcfinCompanionClient()

    var body: some View {
        SettingsForm {
            if let live {
                AdminIntroSection(text: "Every watch party and Pick Together session on now or scheduled. You have the host's controls over any of them.")
                if live.watchParties.isEmpty && live.pickSessions.isEmpty {
                    Section {
                        Text("Nothing on right now.")
                            .foregroundStyle(DT.Color.textSecondary)
                            .tvReadOnlyRow()
                    }
                }
                ForEach(live.watchParties) { party in
                    LivePartySection(party: party, isBusy: isBusy, ask: { HapticManager.warning(); confirm = $0 },
                                     reschedule: { date in await act { try await client.adminScheduleParty(date, code: party.code, credential: $0, authHeader: $1) } },
                                     lock: { locked in Task { await act { try await client.adminLockParty(locked, code: party.code, credential: $0, authHeader: $1) } } })
                }
                ForEach(live.pickSessions) { session in
                    LivePickSection(session: session, isBusy: isBusy, ask: { HapticManager.warning(); confirm = $0 },
                                    lock: { locked in Task { await act { try await client.adminLockPick(locked, code: session.code, credential: $0, authHeader: $1) } } })
                }
                if AdminRefresh.showsButton {
                    Section {
                        Button("Refresh") { Task { await load() } }
                            .formRowButton()
                            .disabled(isBusy)
                    }
                }
            } else {
                AdminPendingSection(error: error)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Happening Now")
        .task { await load() }
        .refreshable { await load() }
        .adminErrorAlert($actionError)
        .confirmationPrompt(Text(confirm?.title ?? ""), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { pending in
            Button(pending.action, role: .destructive) { Task { await carryOut(pending) } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            if let message = pending.message { Text(message) }
        }
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            live = try await client.liveSessions(credential: access.credential, authHeader: access.header)
            error = nil
        } catch {
            if live == nil { self.error = AdminSyncError.loadMessage() } else { actionError = AdminSyncError.message(error) }
        }
    }

    /// Runs an action and shows what's on after it. If the server refuses, it shows what's on now.
    @discardableResult
    private func act(_ call: (ServerCredential, String) async throws -> LiveSessions) async -> Bool {
        guard let access = authManager.arcfinSyncDevicesSession else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            live = try await call(access.credential, access.header)
            HapticManager.success()
            return true
        } catch {
            actionError = AdminSyncError.message(error)
            await load()
            return false
        }
    }

    private func carryOut(_ pending: LiveConfirm) async {
        switch pending {
        case .remove(let person, let code, true):
            await act { try await client.adminRemoveFromParty(personID: person.id, code: code, credential: $0, authHeader: $1) }
        case .remove(let person, let code, false):
            await act { try await client.adminRemoveFromPick(personID: person.id, code: code, credential: $0, authHeader: $1) }
        case .endParty(let party):
            await act { try await client.adminEndParty(code: party.code, credential: $0, authHeader: $1) }
        case .endPick(let session):
            await act { try await client.adminEndPick(code: session.code, credential: $0, authHeader: $1) }
        }
    }
}
