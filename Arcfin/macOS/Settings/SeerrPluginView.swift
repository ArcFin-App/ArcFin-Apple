// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI
import AuthCore

struct SeerrPluginView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    @AppStorage("seerrURL")         private var seerrURL        = ""
    @AppStorage("seerrUsername")    private var seerrUsername   = ""
    @AppStorage("seerrAuthMethod")  private var seerrAuthMethod = SeerrAuthMethod.jellyfin

    @State private var form = SeerrConnectionForm()
    @State private var showRemoveConfirm = false

    private var isConfigured: Bool { !seerrURL.isEmpty }

    /// The connection is edited as one form (Edit → Save), not per-field toggles, so a lock on
    /// any one of its three synced keys locks editing the whole thing rather than just that field.
    private var isLocked: Bool {
        ["seerrURL", "seerrUsername", "seerrAuthMethod"].contains { authManager.arcfinSyncLockedKeys.contains($0) }
    }

    var body: some View {
        SettingsForm {
            if seerrRepo.isThroughServer {
                SeerrThroughServerSection()
            } else if isConfigured && !form.isEditing {
                SeerrConnectionSummary(url: seerrURL, authMethod: seerrAuthMethod, username: seerrUsername,
                                       usesQuickConnect: seerrAuthMethod.usesQuickConnect(password: authManager.seerrPassword),
                                       isManagedByServer: isLocked) {
                    showRemoveConfirm = true
                }
            } else {
                editingForm
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Seerr")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if seerrRepo.isThroughServer {
                    EmptyView()
                } else if form.isEditing || !isConfigured {
                    Button("Save") { save() }
                        .disabled(!form.isComplete)
                } else {
                    Button("Edit") { beginEditing() }
                        .disabled(isLocked)
                }
            }
            // Canceling only makes sense once there's an existing connection to cancel back
            // to — with nothing configured yet, Cancel had no real "before" state to return
            // to, and just hid the form behind a blank summary instead.
            if form.isEditing && isConfigured {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { form.isEditing = false; form.testResult = nil }
                }
            }
        }
        .onAppear { if !isConfigured && !seerrRepo.isThroughServer { beginEditing() } }
        .alert(
            "Remove Seerr connection?",
            isPresented: $showRemoveConfirm
        ) {
            Button("Remove", role: .destructive) { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the saved server URL and credentials. You can reconnect any time.")
        }
    }

    // MARK: - Editing form

    @ViewBuilder
    private var editingForm: some View {
        // Server URL
        Section {
            TextField("https://seerr.example.com" as String, text: $form.url)
                .textContentType(.URL)
                .autocorrectionDisabled()
        } header: {
            Label("Server URL", systemImage: "server.rack")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }

        if form.usesPassword {
            // Account type picker
            SeerrAccountTypeSection(form: form)

            // Credentials
            Section {
                TextField("Username", text: $form.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $form.password)
                    .autocorrectionDisabled()
            } header: {
                Label("Credentials", systemImage: "person.fill")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }

            // Test connection
            SeerrTestSection(form: form)
        } else {
            SeerrQuickConnectSection(form: form) { save() }
        }

        SeerrOtherSignInSection(form: form)
    }

    // MARK: - Actions

    private func beginEditing() {
        form.beginEditing(url: seerrURL, username: seerrUsername,
                          password: authManager.seerrPassword, authMethod: seerrAuthMethod,
                          jellyfinUsername: authManager.state.credential?.displayName)
    }

    private func save() {
        seerrURL = form.url.trimmingCharacters(in: .whitespacesAndNewlines)
        seerrUsername = form.username
        if form.password.isEmpty {
            authManager.removeSeerrPassword()
        } else {
            authManager.saveSeerrPassword(form.password)
        }
        seerrAuthMethod = form.authMethod
        form.isEditing = false
    }

    private func remove() {
        seerrURL = ""; seerrUsername = ""
        authManager.removeSeerrPassword()
        seerrAuthMethod = .jellyfin
        seerrRepo.clearAuthFailure()
        beginEditing()
    }
}
