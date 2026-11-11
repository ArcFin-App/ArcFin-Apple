// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

/// The Seerr connection as it's edited in Settings › Seerr, and testing it.
@MainActor @Observable
final class SeerrConnectionForm {
    // Draft copies — edits only commit to AppStorage (and re-trigger the live
    // connection) on Save, so browsing the form can't accidentally reconfigure it.
    var isEditing = false
    var url = ""
    var username = ""
    var password = ""
    var authMethod = SeerrAuthMethod.jellyfin

    var testResult: String? = nil
    private(set) var isTesting = false
    /// Signing in with a username and password rather than Quick Connect, the usual way.
    private(set) var usesPassword = false
    private var jellyfinUsername = ""

    /// Whether Save can go ahead.
    var isComplete: Bool {
        !url.isEmpty && !username.isEmpty && (!usesPassword || !password.isEmpty)
    }

    /// A connection with no saved password signs in with Quick Connect, as the Jellyfin user.
    func beginEditing(url: String, username: String, password: String, authMethod: SeerrAuthMethod,
                      jellyfinUsername: String? = nil) {
        self.jellyfinUsername = jellyfinUsername ?? ""
        usesPassword = !password.isEmpty || authMethod == .local
        self.url = url
        self.username = username.isEmpty ? self.jellyfinUsername : username
        self.password = password
        self.authMethod = authMethod
        testResult = nil
        isEditing = true
    }

    func useQuickConnect() {
        usesPassword = false
        authMethod = .jellyfin
        password = ""
        if !jellyfinUsername.isEmpty { username = jellyfinUsername }
        testResult = nil
    }

    func usePassword() {
        usesPassword = true
        testResult = nil
    }

    /// `onSuccess` runs once Seerr has accepted the sign-in.
    func testConnection(seerrRepo: SeerrRepository, authManager: AuthManager, onSuccess: (() -> Void)? = nil) {
        guard let url = URL(string: self.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            testResult = "✗ " + String(localized: "Invalid URL"); return
        }
        isTesting = true; testResult = nil
        let client = SeerrHTTPClient(baseURL: url, username: username, password: password, authMethod: authMethod,
                                     authorizeQuickConnect: SeerrSignIn.quickConnectAuthorizer(authManager: authManager))
        Task {
            do {
                try await client.login()
                testResult = "✓ " + (await client.usesQuickConnect
                    ? String(localized: "Connected with Quick Connect")
                    : String(localized: "Connected"))
                seerrRepo.clearAuthFailure()
                onSuccess?()
            } catch {
                testResult = "✗ " + SeerrSignInText.message(for: error)
            }
            isTesting = false
        }
    }
}

/// Settings › Seerr once it's connected: the saved connection, read-only, and removing it.
struct SeerrConnectionSummary: View {
    let url: String
    let authMethod: SeerrAuthMethod
    let username: String
    /// Connected through Quick Connect rather than a saved password.
    var usesQuickConnect = false
    /// The server's Arcfin Sync plugin sets this connection: it can't be removed here, since
    /// the plugin would put it straight back.
    var isManagedByServer = false
    let onRemove: () -> Void

    var body: some View {
        Section {
            // Focusable on tvOS so the page doesn't open with focus on Remove Connection.
            LabeledContent("Server URL", value: url)
                .lineLimit(1)
                .tvReadOnlyRow()
            LabeledContent("Account Type", value: authMethod.label)
                .tvReadOnlyRow()
            LabeledContent("Username", value: username)
                .tvReadOnlyRow()
            if usesQuickConnect {
                LabeledContent("Signs In With", value: String(localized: "Quick Connect"))
                    .tvReadOnlyRow()
            }
        } header: {
            Label("Connection", systemImage: "server.rack")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }

        if isManagedByServer {
            Section {
            } footer: {
                Text("Your server sets up this Seerr connection for everyone, so it can't be removed here. Ask your admin to change it.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        } else {
            Section {
                Button(role: .destructive, action: onRemove) {
                    Text("Remove Connection")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
}

/// Settings › Seerr › Account Type, while editing.
struct SeerrAccountTypeSection: View {
    @Bindable var form: SeerrConnectionForm

    var body: some View {
        Section {
            Picker("Account Type", selection: $form.authMethod) {
                ForEach(SeerrAuthMethod.allCases, id: \.self) { method in
                    Text(method.label).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Label("Account Type", systemImage: "person.badge.key")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        } footer: {
            Text(form.authMethod == .jellyfin
                 ? "Sign in with your Jellyfin username and password."
                 : "Sign in with a local Seerr account.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }
}

/// Settings › Seerr while editing, the usual way: sign in as the Jellyfin user through Quick
/// Connect, with nothing to type. `onConnected` saves the connection.
struct SeerrQuickConnectSection: View {
    let form: SeerrConnectionForm
    let onConnected: () -> Void
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Section {
            Button {
                form.testConnection(seerrRepo: seerrRepo, authManager: authManager, onSuccess: onConnected)
            } label: {
                HStack(spacing: 8) {
                    if form.isTesting { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "bolt.horizontal.circle.fill") }
                    Text(form.isTesting ? "Signing In…" : "Sign In with Quick Connect")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(form.url.isEmpty || form.username.isEmpty || form.isTesting)

            if let result = form.testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("✓") ? DT.Color.palette("10b981") : DT.Color.palette("F43F5E"))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } header: {
            Label("Sign In", systemImage: "person.badge.key")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        } footer: {
            Text("Signs in to Seerr as \(form.username) with your Jellyfin account. There's no password to type, and none is saved.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }
}

/// Switching between Quick Connect and a username and password, while editing.
struct SeerrOtherSignInSection: View {
    let form: SeerrConnectionForm

    var body: some View {
        Section {
            if form.usesPassword {
                Button("Sign In with Quick Connect Instead") { withAnimation { form.useQuickConnect() } }
            } else {
                Button("Use a Username and Password") { withAnimation { form.usePassword() } }
            }
        } header: {
            if !form.usesPassword {
                Text("Other Ways to Sign In")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }
        } footer: {
            if !form.usesPassword {
                Text("For a local Seerr account, or when Quick Connect is turned off on your Jellyfin server.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }
}

/// Settings › Seerr › Test Connection, while editing.
struct SeerrTestSection: View {
    let form: SeerrConnectionForm
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Section {
            Button { form.testConnection(seerrRepo: seerrRepo, authManager: authManager) } label: {
                HStack {
                    if form.isTesting { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "network") }
                    Text(form.isTesting ? "Testing…" : "Test Connection")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(!form.isComplete || form.isTesting)

            if let result = form.testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("✓") ? DT.Color.palette("10b981") : DT.Color.palette("F43F5E"))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
