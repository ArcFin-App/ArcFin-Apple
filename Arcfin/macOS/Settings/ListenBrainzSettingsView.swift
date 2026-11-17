// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The profile's ListenBrainz token. With it, every song heard in Arcfin is sent to the
/// profile's ListenBrainz account. Laid out like the TMDB page.
struct ListenBrainzSettingsView: View {
    @State private var model: ListenBrainzTokenModel

    init(profile: UUID?) {
        _model = State(initialValue: ListenBrainzTokenModel(profile: profile))
    }

    var body: some View {
        SettingsForm {
            Section {
                SecureField("User token", text: $model.token)
                    .autocorrectionDisabled()
                    .onSubmit(model.save)
            } header: {
                Label("User Token", systemImage: "key")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Optional. Sends the songs you play in Arcfin to your ListenBrainz account, for your listening history and recommendations. A song counts once you've heard half of it or four minutes. Find your token at listenbrainz.org under Settings. Stored in the Keychain on this device, for this profile only.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Button {
                    model.testConnection()
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
                .formRowButton()
                .disabled(model.isTokenEmpty || model.isTesting)

                if let result = model.testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? DT.Color.palette("10b981") : DT.Color.palette("F43F5E"))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } footer: {
                ListenBrainzStatusFooter(model: model)
            }

            if !model.savedToken.isEmpty {
                Section {
                    Button(role: .destructive, action: model.remove) {
                        Text("Remove Token").frame(maxWidth: .infinity, alignment: .center)
                    }
                    .formRowButton()
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("ListenBrainz")
        // Kept like the other integrations' fields: leaving the page saves what's typed.
        .onDisappear(perform: model.save)
    }
}
