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

    func beginEditing(url: String, username: String, password: String, authMethod: SeerrAuthMethod) {
        self.url = url
        self.username = username
        self.password = password
        self.authMethod = authMethod
        testResult = nil
        isEditing = true
    }

    func testConnection(seerrRepo: SeerrRepository) {
        guard let url = URL(string: self.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            testResult = "✗ Invalid URL"; return
        }
        isTesting = true; testResult = nil
        let path = authMethod.apiPath
        let body = try? JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
        ])
        Task {
            var req = URLRequest(url: url.appendingPathComponent(path))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            req.timeoutInterval = 10
            do {
                let (_, resp) = try await URLSession.arcfin.data(for: req)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    testResult = "✓ Connected as \(authMethod.label)"
                    seerrRepo.clearAuthFailure()
                } else if let http = resp as? HTTPURLResponse, http.statusCode == 403 {
                    testResult = "✗ Wrong account type — try the other option"
                } else {
                    testResult = "✗ Invalid credentials"
                }
            } catch {
                testResult = "✗ \(error.localizedDescription)"
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
        } header: {
            Label("Connection", systemImage: "server.rack")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }

        Section {
            Button(role: .destructive, action: onRemove) {
                Text("Remove Connection")
                    .frame(maxWidth: .infinity, alignment: .center)
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
            Text(form.authMethod.description)
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }
}

/// Settings › Seerr › Test Connection, while editing.
struct SeerrTestSection: View {
    let form: SeerrConnectionForm
    @Environment(SeerrRepository.self) private var seerrRepo

    var body: some View {
        Section {
            Button { form.testConnection(seerrRepo: seerrRepo) } label: {
                HStack {
                    if form.isTesting { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "network") }
                    Text(form.isTesting ? "Testing…" : "Test Connection")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .disabled(form.url.isEmpty || form.username.isEmpty || form.password.isEmpty || form.isTesting)

            if let result = form.testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.hasPrefix("✓") ? DT.Color.palette("10b981") : DT.Color.palette("EF4444"))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
