// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import SeerrAPI

/// The user's own TMDB key. With it, title pages, streaming rows and Home's catalogue shelves
/// work without Seerr, and keep working when Seerr's requests fail. Laid out like the Seerr
/// and Streamystats pages.
struct TMDBSettingsView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var key = TMDBCredential.load() ?? ""
    @State private var savedKey = TMDBCredential.load() ?? ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        List {
            Section {
                SecureField("API key or read access token", text: $key)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(save)
            } header: {
                Label("API Key", systemImage: "key")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Optional. Get a free key at themoviedb.org under Settings → API. Arcfin uses it for where titles are streaming, title details and what's popular without Seerr, and when Seerr can't reach TMDB. Requests still go through Seerr. Stored in the Keychain on this device.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "Testing…" : "Test Connection")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? Color(hex: "10b981") : Color(hex: "EF4444"))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if !savedKey.isEmpty {
                Section {
                    Button(role: .destructive) {
                        key = ""
                        save()
                        testResult = nil
                    } label: {
                        Text("Remove Key").frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("TMDB")
        // Kept like the other integrations' fields: leaving the page saves what's typed.
        .onDisappear(perform: save)
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != savedKey else { return }
        try? TMDBCredential.save(trimmed)
        savedKey = trimmed
        seerrRepo.reloadTMDB()
        if !trimmed.isEmpty { Task { await seerrRepo.loadDiscover() } }
    }

    private func testConnection() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        isTesting = true
        testResult = nil
        Task {
            do {
                _ = try await TMDBClient(key: trimmed).trending()
                testResult = "✓ Connected to TMDB"
                save()
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
