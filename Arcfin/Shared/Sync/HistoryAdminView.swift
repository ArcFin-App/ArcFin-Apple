// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// How long history is kept.
enum HistoryKeep: Hashable {
    case days(Int), custom, forEver

    static let choices: [HistoryKeep] = [.days(7), .days(30), .days(90), .days(180), .days(365), .custom, .forEver]

    init(_ keepDays: Int?) {
        if let keepDays { self = Self.choices.contains(.days(keepDays)) ? .days(keepDays) : .custom } else { self = .forEver }
    }

    var label: Text {
        switch self {
        case .days(365): Text("1 year")
        case .days(let days): Text("\(days) days")
        case .custom: Text("Custom…")
        case .forEver: Text("For Ever")
        }
    }
}

/// Arcfin for Everyone › History: past watch parties and Pick Together sessions, and how long
/// the server keeps them.
struct HistoryAdminView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var saved: HistorySettings?
    @State private var enabled = false
    @State private var keep = HistoryKeep.days(90)
    @State private var customDays: Int?
    @State private var kind: String?
    @State private var entries: [HistoryEntry] = []
    @State private var error: String?
    @State private var actionError: String?
    @State private var confirmClear = false
    @State private var isBusy = false
    private let client = ArcfinCompanionClient()

    private var keepDays: Int? {
        switch keep {
        case .days(let days): days
        case .custom: customDays
        case .forEver: nil
        }
    }

    private var hasChanges: Bool {
        guard let saved else { return false }
        return saved.enabled != enabled || saved.keepDays != keepDays
    }

    var body: some View {
        SettingsForm {
            if saved != nil {
                AdminIntroSection(text: "Past watch parties and Pick Together sessions: when, who hosted, who took part, and how they ended. Only kept while this is on.")
                settingsSection
                Section {
                    SettingsPicker("Show", selection: $kind, options: [nil, "watchParty", "pickTogether"]) { value in
                        switch value {
                        case "watchParty"?: Text("Watch Parties")
                        case "pickTogether"?: Text("Pick Together")
                        default: Text("Everything")
                        }
                    }
                    if entries.isEmpty {
                        Text(saved?.enabled == true ? "Nothing yet." : "History is off.")
                            .foregroundStyle(DT.Color.textSecondary)
                            .tvReadOnlyRow()
                    }
                    ForEach(entries) { HistoryEntryRow(entry: $0) }
                } header: {
                    Text("History")
                }
                Section {
                    Button(role: .destructive) { HapticManager.warning(); confirmClear = true } label: {
                        Text("Clear History")
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                    .formRowButton()
                    .disabled(isBusy)
                }
            } else {
                AdminPendingSection(error: error)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("History")
        .task { await load() }
        .refreshable { await loadEntries() }
        .onChange(of: kind) { Task { await loadEntries() } }
        .adminErrorAlert($actionError)
        .alert("Clear all watch party and Pick Together history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { Task { await clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var settingsSection: some View {
        Section {
            Toggle(isOn: $enabled) {
                TVRowLabelText(title: "Keep History")
            }
            .tvListRow()
            if enabled {
                SettingsPicker("Keep For", selection: $keep, options: HistoryKeep.choices) { $0.label }
                if keep == .custom {
                    WholeNumberRow(title: "Days", prompt: "30", value: $customDays, maximum: 3650)
                }
            }
            Button {
                Task { await saveSettings() }
            } label: {
                Text(isBusy ? "Saving…" : "Save")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .formRowButton()
            .disabled(isBusy || !hasChanges)
        } footer: {
            if enabled && keep == .custom {
                Text("Any number of days from 1 to 3650.")
            }
        }
    }

    private func show(_ settings: HistorySettings) {
        saved = settings
        enabled = settings.enabled
        keep = HistoryKeep(settings.keepDays)
        customDays = settings.keepDays
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            show(try await client.historySettings(credential: access.credential, authHeader: access.header))
            await loadEntries()
        } catch {
            self.error = AdminSyncError.loadMessage()
        }
    }

    private func loadEntries() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            entries = try await client.history(kind: kind, credential: access.credential, authHeader: access.header)
        } catch {
            actionError = AdminSyncError.message(error)
        }
    }

    private func saveSettings() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        if keep == .custom, !(1...3650).contains(customDays ?? 0) {
            actionError = String(localized: "Pick 1 to 3650 days.")
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            show(try await client.saveHistorySettings(HistorySettings(enabled: enabled, keepDays: keepDays),
                                                      credential: access.credential, authHeader: access.header))
            HapticManager.success()
            await loadEntries()
        } catch {
            actionError = AdminSyncError.message(error)
        }
    }

    private func clear() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.clearHistory(credential: access.credential, authHeader: access.header)
            HapticManager.success()
            await loadEntries()
        } catch {
            actionError = AdminSyncError.message(error)
        }
    }
}

/// One past watch party or Pick Together session.
private struct HistoryEntryRow: View {
    let entry: HistoryEntry

    private var title: String {
        if entry.isWatchParty { return String(localized: "Watch party · \(entry.itemName ?? "")") }
        if let item = entry.itemName { return String(localized: "Pick Together · watched \(item)") }
        return String(localized: "Pick Together")
    }

    private var outcome: AdminBadge {
        switch entry.outcome {
        case "watched": AdminBadge("Watched together", isProminent: true)
        case "ended": AdminBadge("Ended by the host")
        case "cancelled": AdminBadge("Ended by an admin")
        case "notStarted": AdminBadge("Never started")
        case "left": AdminBadge("Everyone left")
        default: AdminBadge(verbatim: entry.outcome)
        }
    }

    private var details: String {
        let host = entry.hostName.isEmpty ? String(localized: "someone") : entry.hostName
        var hosted = String(localized: "Hosted by \(host)")
        if !entry.people.isEmpty { hosted += " · " + entry.people.formatted(.list(type: .and)) }
        var times: [String] = []
        if let planned = entry.scheduledFor { times.append(String(localized: "Planned for \(LiveTime.when(planned))")) }
        if let started = entry.startedWatching { times.append(String(localized: "Started \(LiveTime.when(started))")) }
        times.append(String(localized: "Ended \(LiveTime.when(entry.ended))"))
        var lines = [hosted, times.joined(separator: " · ")]
        if !entry.matches.isEmpty { lines.append(String(localized: "Matches: \(entry.matches.formatted(.list(type: .and)))")) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TVRowLabelText(verbatim: title, detail: "\(details)")
            Spacer(minLength: DT.Spacing.xs)
            outcome
        }
        .tvReadOnlyRow()
    }
}
