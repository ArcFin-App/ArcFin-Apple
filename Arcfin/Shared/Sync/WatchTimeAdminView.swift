// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// One person's watch time as it's being edited: kept while switched off, so switching back
/// on brings their numbers back.
struct WatchTimeDraft: Equatable {
    var isOn: Bool
    var rule: WatchLimitRule

    var hasBedtime: Bool {
        get { rule.bedtimeStart != nil && rule.bedtimeEnd != nil }
        set {
            rule.bedtimeStart = newValue ? (rule.bedtimeStart ?? "21:00") : nil
            rule.bedtimeEnd = newValue ? (rule.bedtimeEnd ?? "07:00") : nil
        }
    }
}

/// Arcfin for Everyone › Watch Time: a daily limit and a bedtime for anyone who needs them.
struct WatchTimeAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let users: [ArcfinSyncAdminUser]

    @State private var admin: LimitsAdmin?
    @State private var error: String?
    @State private var actionError: String?
    @State private var timeZone = ""
    @State private var drafts: [String: WatchTimeDraft] = [:]
    @State private var isSaving = false
    @State private var warnBeforeEnd = true
    private let client = ArcfinCompanionClient()

    var body: some View {
        SettingsForm {
            if let admin {
                AdminIntroSection(text: "Daily watch time and a bedtime for anyone who needs them. The server counts time from every app and stops playback once time's up or bedtime starts, with a message.")
                Section {
                    TextField("Time Zone", text: $timeZone, prompt: Text(verbatim: "Europe/Dublin"))
                        .autocorrectionDisabled()
                        .tvListRow()
                } header: {
                    Text("Time Zone")
                } footer: {
                    Text(verbatim: clockLine(admin))
                }
                Section {
                    Toggle(isOn: $warnBeforeEnd) {
                        TVRowLabelText(title: "Warn 10 and 5 Minutes Before Time's Up or Bedtime")
                    }
                    .tvListRow()
                } footer: {
                    Text("Arcfin shows a message while something's playing, so no one's cut off without notice.")
                }
                ForEach(users) { user in
                    WatchTimeUserSection(name: user.name, usedToday: admin.used(user.userId), draft: draft(for: user.userId))
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        Text(isSaving ? "Saving…" : "Save")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .formRowButton()
                    .disabled(isSaving)
                }
            } else {
                AdminPendingSection(error: error)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Watch Time")
        .task { await load() }
        .adminErrorAlert($actionError)
    }

    private func clockLine(_ admin: LimitsAdmin) -> String {
        let zone = (admin.timeZone ?? "").isEmpty ? " (\(admin.serverTimeZone))" : ""
        return String(localized: "Server time now: \(admin.serverTime)") + zone
    }

    private func draft(for userID: String) -> Binding<WatchTimeDraft> {
        Binding(
            get: { drafts[userID] ?? WatchTimeDraft(isOn: false, rule: WatchLimitRule(userId: userID)) },
            set: { drafts[userID] = $0 })
    }

    private func show(_ next: LimitsAdmin) {
        warnBeforeEnd = next.warnBeforeEnd
        admin = next
        timeZone = next.timeZone ?? ""
        var fresh: [String: WatchTimeDraft] = [:]
        for user in users {
            let id = ArcfinCompanionClient.normalized(user.userId)
            if var rule = next.rules.first(where: { ArcfinCompanionClient.normalized($0.userId) == id }) {
                rule.userId = user.userId
                fresh[user.userId] = WatchTimeDraft(isOn: true, rule: rule)
            } else {
                fresh[user.userId] = drafts[user.userId].map { WatchTimeDraft(isOn: false, rule: $0.rule) }
                    ?? WatchTimeDraft(isOn: false, rule: WatchLimitRule(userId: user.userId))
            }
        }
        drafts = fresh
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            show(try await client.limitsAdmin(credential: access.credential, authHeader: access.header))
        } catch {
            self.error = AdminSyncError.loadMessage()
        }
    }

    private func save() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        let zone = timeZone.trimmingCharacters(in: .whitespaces)
        let rules = users.compactMap { user in drafts[user.userId].flatMap { $0.isOn ? $0.rule : nil } }
        isSaving = true
        defer { isSaving = false }
        do {
            show(try await client.saveLimits(LimitsAdminChange(timeZone: zone.isEmpty ? nil : zone, rules: rules, warnBeforeEnd: warnBeforeEnd),
                                             credential: access.credential, authHeader: access.header))
            HapticManager.success()
        } catch {
            actionError = AdminSyncError.message(error)
        }
    }
}

/// One person's limit: on or off, minutes a day, weekend minutes and bedtime.
struct WatchTimeUserSection: View {
    let name: String
    let usedToday: Int?
    @Binding var draft: WatchTimeDraft

    var body: some View {
        Section {
            Toggle(isOn: $draft.isOn) {
                if let usedToday {
                    TVRowLabelText(verbatim: name, detail: "\(usedToday) min watched today")
                } else {
                    TVRowLabelText(verbatim: name)
                }
            }
            .tvListRow()
            if draft.isOn {
                WholeNumberRow(title: "Minutes a Day", prompt: "120", value: Binding(
                    get: { draft.rule.dailyMinutes },
                    set: { draft.rule.dailyMinutes = $0 ?? 0 }), maximum: 1440)
                WholeNumberRow(title: "Weekend Minutes", prompt: "Same", value: $draft.rule.weekendMinutes, maximum: 1440)
                Toggle(isOn: $draft.hasBedtime) {
                    TVRowLabelText(title: "Bedtime")
                }
                .tvListRow()
                if draft.hasBedtime {
                    TimeOfDayRow("Bedtime Starts", time: Binding(
                        get: { draft.rule.bedtimeStart ?? "21:00" }, set: { draft.rule.bedtimeStart = $0 }))
                        .tvListRow()
                    TimeOfDayRow("Bedtime Ends", time: Binding(
                        get: { draft.rule.bedtimeEnd ?? "07:00" }, set: { draft.rule.bedtimeEnd = $0 }))
                        .tvListRow()
                }
                TextField("Time Zone", text: Binding(
                    get: { draft.rule.timeZone ?? "" },
                    set: { draft.rule.timeZone = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }),
                    prompt: Text("Same as everyone"))
                    .autocorrectionDisabled()
                    .tvListRow()
            }
        } footer: {
            if draft.isOn {
                Text("0 minutes a day means no daily limit. Leave weekend minutes empty to use the same as weekdays. A time zone here, like Europe/Dublin, is used for this person's bedtime and day instead of everyone's.")
            }
        }
    }
}
