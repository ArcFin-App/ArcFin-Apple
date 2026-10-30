// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

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
        List {
            if isConfigured && !form.isEditing {
                SeerrConnectionSummary(url: seerrURL, authMethod: seerrAuthMethod, username: seerrUsername) {
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
                if form.isEditing || !isConfigured {
                    Button("Save") { save() }
                        .disabled(form.url.isEmpty || form.username.isEmpty || form.password.isEmpty)
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
        .onAppear { if !isConfigured { beginEditing() } }
        .confirmationDialog(
            "Remove Seerr connection?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
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
            TextField("http://10.0.1.122:5055", text: $form.url)
                .textContentType(.URL)
                .autocorrectionDisabled()
        } header: {
            Label("Server URL", systemImage: "server.rack")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }

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
    }

    // MARK: - Actions

    private func beginEditing() {
        form.beginEditing(url: seerrURL, username: seerrUsername,
                          password: authManager.seerrPassword, authMethod: seerrAuthMethod)
    }

    private func save() {
        seerrURL = form.url.trimmingCharacters(in: .whitespacesAndNewlines)
        seerrUsername = form.username
        authManager.saveSeerrPassword(form.password)
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
