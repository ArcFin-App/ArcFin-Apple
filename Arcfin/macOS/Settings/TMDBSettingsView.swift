// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The user's own TMDB key. With it, title pages, streaming rows and Home's catalogue shelves
/// work without Seerr, and keep working when Seerr's requests fail. Laid out like the Seerr
/// page.
struct TMDBSettingsView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var model = TMDBKeyModel()

    var body: some View {
        SettingsForm {
            Section {
                SecureField("API key or read access token", text: $model.key)
                    .autocorrectionDisabled()
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
                    model.testConnection(seerrRepo: seerrRepo)
                } label: {
                    HStack {
                        if model.isTesting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(model.isTesting ? "Testing…" : "Test Connection")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(model.key.trimmingCharacters(in: .whitespaces).isEmpty || model.isTesting)

                if let result = model.testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? DT.Color.palette("10b981") : DT.Color.palette("F43F5E"))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            if !model.savedKey.isEmpty {
                Section {
                    Button(role: .destructive) {
                        model.key = ""
                        save()
                        model.testResult = nil
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
        model.save(seerrRepo: seerrRepo)
    }
}
