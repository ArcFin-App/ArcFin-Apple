// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Arcfin for Everyone › Downloads: how much each person may keep downloaded across their
/// devices, for movies and episodes and for music.
struct DownloadLimitsAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let users: [ArcfinSyncAdminUser]
    @State private var model = HouseholdAdminModel()
    @State private var draft = DownloadLimitSettings()

    private var saved: DownloadLimitSettings? { model.admin.map { Self.trimmed($0.downloads) } }

    var body: some View {
        SettingsForm {
            if model.admin != nil {
                Section {
                    Toggle(isOn: $draft.enabled) {
                        TVRowLabelText(title: "Movie and Episode Limits")
                    }
                    .tvListRow()
                    if draft.enabled {
                        WholeNumberRow(title: "Most Titles", prompt: "No cap", value: $draft.maxTitles, maximum: 100_000)
                        DecimalRow(title: "Most Space (GB)", prompt: "No cap", value: $draft.maxGigabytes)
                    }
                } header: {
                    Text("Movies and Episodes")
                } footer: {
                    Text("Caps how much each person can keep downloaded in Arcfin. Whichever cap is reached first stops a download. Counted across all of a person's Arcfin devices. Leave a cap empty for no cap.")
                }
                Section {
                    Toggle(isOn: $draft.musicEnabled) {
                        TVRowLabelText(title: "Music Limits")
                    }
                    .tvListRow()
                    if draft.musicEnabled {
                        WholeNumberRow(title: "Most Albums", prompt: "No cap", value: $draft.musicMaxAlbums, maximum: 100_000)
                        WholeNumberRow(title: "Most Songs", prompt: "No cap", value: $draft.musicMaxSongs, maximum: 1_000_000)
                        DecimalRow(title: "Most Space (GB)", prompt: "No cap", value: $draft.musicMaxGigabytes)
                    }
                } header: {
                    Text("Music")
                } footer: {
                    Text("Whichever is reached first stops a download. A song or album on several of a person's devices counts once.")
                }
                if draft.enabled || draft.musicEnabled {
                    Section {
                        ForEach(users) { user in
                            NavigationLink {
                                DownloadPersonView(name: user.name, use: model.admin?.use(user.userId), movies: draft.enabled,
                                                   music: draft.musicEnabled, override: override(user.userId))
                                    .tvSettingsPage()
                            } label: {
                                TVRowLabelText(verbatim: user.name, detail: "\(summary(user.userId))")
                            }
                            .tvListRow()
                        }
                    } header: {
                        Text("For One Person")
                    }
                }
                Section {
                    Button {
                        Task { _ = await model.saveDownloads(Self.trimmed(draft), authManager: authManager) }
                    } label: {
                        Text(model.isBusy ? "Saving…" : "Save")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .formRowButton()
                    .disabled(model.isBusy || Self.trimmed(draft) == saved)
                }
            } else {
                AdminPendingSection(error: model.loadError)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Downloads")
        .task {
            await model.load(authManager: authManager)
            if let downloads = model.admin?.downloads { draft = downloads }
        }
        .adminErrorAlert(Binding(get: { model.actionError }, set: { model.actionError = $0 }))
    }

    private static func trimmed(_ settings: DownloadLimitSettings) -> DownloadLimitSettings {
        var next = settings
        next.users = next.users.filter { $0.mode != "inherit" || $0.musicMode != "inherit" }
        return next
    }

    private func index(_ userID: String) -> Int? {
        draft.users.firstIndex { ArcfinCompanionClient.normalized($0.userId) == ArcfinCompanionClient.normalized(userID) }
    }

    private func override(_ userID: String) -> Binding<DownloadLimitSettings.UserOverride> {
        Binding(
            get: { index(userID).map { draft.users[$0] } ?? DownloadLimitSettings.UserOverride(userId: userID) },
            set: { value in
                if let i = index(userID) { draft.users[i] = value } else { draft.users.append(value) }
            })
    }

    private func summary(_ userID: String) -> String {
        let own = override(userID).wrappedValue
        var parts: [String] = []
        if draft.enabled { parts.append(String(localized: "Movies: \(DownloadMode.text(own.mode))")) }
        if draft.musicEnabled { parts.append(String(localized: "Music: \(DownloadMode.text(own.musicMode))")) }
        return parts.joined(separator: " · ")
    }
}

enum DownloadMode {
    static let all = ["inherit", "off", "custom"]

    static func text(_ mode: String) -> String {
        switch mode {
        case "off": String(localized: "No Limits")
        case "custom": String(localized: "Custom")
        default: String(localized: "Same as Everyone")
        }
    }

    static func label(_ mode: String) -> Text { Text(verbatim: text(mode)) }
}

enum DownloadUse {
    static func titles(_ use: HouseholdAdmin.Use) -> String {
        String(localized: "\(use.titles) titles · \(use.bytes.formatted(.byteCount(style: .file)))")
    }

    static func music(_ use: HouseholdAdmin.Use) -> String {
        String(localized: "\(use.albums) albums · \(use.songs) songs · \(use.musicBytes.formatted(.byteCount(style: .file)))")
    }
}

/// One person's own download limits. Saved with the rest on the Downloads page.
private struct DownloadPersonView: View {
    let name: String
    let use: HouseholdAdmin.Use?
    let movies: Bool
    let music: Bool
    @Binding var override: DownloadLimitSettings.UserOverride

    var body: some View {
        SettingsForm {
            if movies {
                Section {
                    SettingsPicker("Limits", selection: $override.mode, options: DownloadMode.all) { DownloadMode.label($0) }
                    if override.mode == "custom" {
                        WholeNumberRow(title: "Most Titles", prompt: "No cap", value: $override.maxTitles, maximum: 100_000)
                        DecimalRow(title: "Most Space (GB)", prompt: "No cap", value: $override.maxGigabytes)
                    }
                    if let use { UseRow(text: DownloadUse.titles(use)) }
                } header: {
                    Text("Movies and Episodes")
                }
            }
            if music {
                Section {
                    SettingsPicker("Limits", selection: $override.musicMode, options: DownloadMode.all) { DownloadMode.label($0) }
                    if override.musicMode == "custom" {
                        WholeNumberRow(title: "Most Albums", prompt: "No cap", value: $override.musicMaxAlbums, maximum: 100_000)
                        WholeNumberRow(title: "Most Songs", prompt: "No cap", value: $override.musicMaxSongs, maximum: 1_000_000)
                        DecimalRow(title: "Most Space (GB)", prompt: "No cap", value: $override.musicMaxGigabytes)
                    }
                    if let use { UseRow(text: DownloadUse.music(use)) }
                } header: {
                    Text("Music")
                } footer: {
                    Text("Save on the Downloads page to keep the change.")
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(name)
    }
}

private struct UseRow: View {
    let text: String

    var body: some View {
        LabeledContent {
            Text(verbatim: text)
        } label: {
            TVRowLabelText(title: "Downloaded Now")
        }
        .tvReadOnlyRow()
    }
}
