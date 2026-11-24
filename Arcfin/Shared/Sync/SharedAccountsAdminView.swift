// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Household › Shared Accounts: an account signed in on a shared screen, and the people who
/// watch on it. Each change is saved straight away.
struct SharedAccountsAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let model: HouseholdAdminModel
    let users: [ArcfinSyncAdminUser]

    private var accounts: [SharedAccountSetting] { model.admin?.sharedAccounts ?? [] }

    private var unshared: [ArcfinSyncAdminUser] {
        users.filter { user in !accounts.contains { Self.same($0.userId, user.userId) } }
    }

    var body: some View {
        SettingsForm {
            AdminIntroSection(text: "Pick an account used by several people, for example the one on the living-room TV, and choose who watches on it. When something plays on a shared account, Arcfin there asks who's watching, and their own progress and watched status follow along.")
            Section {
                if accounts.isEmpty {
                    Text("No shared accounts yet.")
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
                ForEach(accounts) { account in
                    NavigationLink {
                        SharedAccountView(model: model, users: users, accountID: account.userId).tvSettingsPage()
                    } label: {
                        TVRowLabelText(verbatim: users.name(of: account.userId), detail: "\(members(account))")
                    }
                    .tvListRow()
                }
            } header: {
                Text("Shared Accounts")
            }
            if !unshared.isEmpty {
                Section {
                    SettingsPicker("Add a Shared Account", selection: Binding(get: { String?.none }, set: { id in
                        guard let id else { return }
                        Task { _ = await model.saveSharedAccounts(accounts + [SharedAccountSetting(userId: id)], authManager: authManager) }
                    }), options: [nil] + unshared.map { Optional($0.userId) }) { value in
                        if let value { Text(verbatim: users.name(of: value)) } else { Text("Choose…") }
                    }
                    .disabled(model.isBusy)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Shared Accounts")
    }

    static func same(_ a: String, _ b: String) -> Bool {
        ArcfinCompanionClient.normalized(a) == ArcfinCompanionClient.normalized(b)
    }

    private func members(_ account: SharedAccountSetting) -> String {
        account.members.isEmpty ? String(localized: "No one yet") : account.members.map { users.name(of: $0) }.formatted(.list(type: .and))
    }
}

/// One shared account: who watches on it, or stop sharing it.
private struct SharedAccountView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    let model: HouseholdAdminModel
    let users: [ArcfinSyncAdminUser]
    let accountID: String
    @State private var confirmRemove = false

    private var accounts: [SharedAccountSetting] { model.admin?.sharedAccounts ?? [] }
    private var account: SharedAccountSetting? { accounts.first { SharedAccountsAdminView.same($0.userId, accountID) } }

    var body: some View {
        SettingsForm {
            if let account {
                Section {
                    ForEach(users.filter { !SharedAccountsAdminView.same($0.userId, accountID) }) { user in
                        Toggle(isOn: member(user.userId, of: account)) {
                            TVRowLabelText(verbatim: user.name)
                        }
                        .tvListRow()
                        .disabled(model.isBusy)
                    }
                } header: {
                    Text("Who Watches on It")
                } footer: {
                    Text("Arcfin on this account asks which of these people are watching.")
                }
                Section {
                    Button(role: .destructive) { HapticManager.warning(); confirmRemove = true } label: {
                        Text("Stop Sharing This Account")
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                    .formRowButton()
                    .disabled(model.isBusy)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(users.name(of: accountID))
        .alert("Stop Sharing This Account?", isPresented: $confirmRemove) {
            Button("Stop Sharing", role: .destructive) {
                Task {
                    let rest = accounts.filter { !SharedAccountsAdminView.same($0.userId, accountID) }
                    if await model.saveSharedAccounts(rest, authManager: authManager) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Arcfin on it stops asking who's watching.")
        }
    }

    private func member(_ userID: String, of account: SharedAccountSetting) -> Binding<Bool> {
        Binding(
            get: { account.members.contains { SharedAccountsAdminView.same($0, userID) } },
            set: { on in
                var next = account
                next.members.removeAll { SharedAccountsAdminView.same($0, userID) }
                if on { next.members.append(userID) }
                let all = accounts.map { SharedAccountsAdminView.same($0.userId, accountID) ? next : $0 }
                Task { _ = await model.saveSharedAccounts(all, authManager: authManager) }
            })
    }
}
