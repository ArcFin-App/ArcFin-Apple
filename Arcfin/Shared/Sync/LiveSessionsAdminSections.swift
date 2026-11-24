// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

enum LiveTime {
    static func when(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}

/// Someone in a party or session. Anyone but the host can be removed.
private struct LivePersonRow: View {
    let person: LivePerson
    let detail: String
    let isBusy: Bool
    let onRemove: () -> Void

    var body: some View {
        if person.isHost {
            TVRowLabelText(verbatim: person.name, detail: "\(detail)")
                .tvReadOnlyRow()
        } else {
            Button(action: onRemove) {
                HStack {
                    TVRowLabelText(verbatim: person.name, detail: "\(detail)")
                    Spacer()
                    Text("Remove")
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
                .contentShape(Rectangle())
            }
            .formRowButton()
            .tvListRow()
            .disabled(isBusy)
        }
    }
}

private struct LiveStatusRow: View {
    let badges: [AdminBadge]
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xxs) {
            HStack(spacing: DT.Spacing.xs) {
                ForEach(badges.indices, id: \.self) { badges[$0] }
            }
            TVRowLabelText(verbatim: detail)
        }
        .tvReadOnlyRow()
    }
}

struct LivePartySection: View {
    let party: LiveParty
    let isBusy: Bool
    let ask: (LiveConfirm) -> Void
    let reschedule: (Date?) async -> Bool
    let lock: (Bool) -> Void

    private var phase: AdminBadge {
        switch party.phase {
        case "scheduled": AdminBadge("Scheduled")
        case "lobby": AdminBadge("In the lobby")
        case "starting": AdminBadge("Starting", isProminent: true)
        case "started": AdminBadge("Watching", isProminent: true)
        default: AdminBadge(verbatim: party.phase)
        }
    }

    private var status: String {
        var text = String(localized: "Code \(party.code)")
        if let start = party.scheduledFor { text += " · " + String(localized: "starts \(LiveTime.when(start))") }
        return text
    }

    private func detail(_ person: LivePerson) -> String {
        [person.isHost ? String(localized: "Host") : nil,
         person.deviceName.isEmpty ? nil : person.deviceName,
         person.isAway ? String(localized: "Away") : nil].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        Section {
            LiveStatusRow(badges: [phase] + (party.locked ? [AdminBadge("Locked")] : []), detail: status)
            ForEach(party.people) { person in
                LivePersonRow(person: person, detail: detail(person), isBusy: isBusy) {
                    ask(.remove(person, code: party.code, fromParty: true))
                }
            }
            if party.canReschedule {
                NavigationLink {
                    PartyTimeView(party: party, save: reschedule).tvSettingsPage()
                } label: {
                    TVRowLabelText(title: party.scheduledFor == nil ? "Schedule" : "Change Time")
                }
                .tvListRow()
                .disabled(isBusy)
                if party.scheduledFor != nil {
                    Button("Make It Now") { Task { await reschedule(nil) } }
                        .formRowButton()
                        .disabled(isBusy)
                }
            }
            Button(party.locked ? LocalizedStringKey("Unlock") : "Lock") { lock(!party.locked) }
                .formRowButton()
                .disabled(isBusy)
            Button(role: .destructive) { ask(.endParty(party)) } label: {
                Text("End")
                    .foregroundStyle(DT.Color.palette("F43F5E"))
            }
            .formRowButton()
            .disabled(isBusy)
        } header: {
            Text("Watch party · \(party.itemName)")
        }
    }
}

struct LivePickSection: View {
    let session: LivePickSession
    let isBusy: Bool
    let ask: (LiveConfirm) -> Void
    let lock: (Bool) -> Void

    private var badges: [AdminBadge] {
        var badges: [AdminBadge] = []
        if let title = session.watchingTogether { badges.append(AdminBadge("Watching \(title)", isProminent: true)) }
        if session.locked { badges.append(AdminBadge("Locked")) }
        return badges
    }

    private var status: String {
        var text = String(localized: "Code \(session.code)") + " · "
            + String(localized: "started \(session.created.formatted(.relative(presentation: .named)))")
        if !session.matches.isEmpty {
            text += " · " + String(localized: "matches: \(session.matches.map(\.name).formatted(.list(type: .and)))")
        }
        return text
    }

    private func detail(_ person: LivePerson) -> String {
        [person.isHost ? String(localized: "Host") : nil,
         String(localized: "Swiped \(person.swiped)"),
         person.isAway ? String(localized: "Away") : nil].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        Section {
            LiveStatusRow(badges: badges, detail: status)
            ForEach(session.people) { person in
                LivePersonRow(person: person, detail: detail(person), isBusy: isBusy) {
                    ask(.remove(person, code: session.code, fromParty: false))
                }
            }
            Button(session.locked ? LocalizedStringKey("Unlock") : "Lock") { lock(!session.locked) }
                .formRowButton()
                .disabled(isBusy)
            Button(role: .destructive) { ask(.endPick(session)) } label: {
                Text("End")
                    .foregroundStyle(DT.Color.palette("F43F5E"))
            }
            .formRowButton()
            .disabled(isBusy)
        } header: {
            Text("Pick Together · round \(session.round)")
        }
    }
}

/// When a party starts: from now to 30 days ahead.
struct PartyTimeView: View {
    @Environment(\.dismiss) private var dismiss
    let party: LiveParty
    let save: (Date?) async -> Bool

    @State private var date = Date.now.addingTimeInterval(3600)
    @State private var isSaving = false
    private let opened = Date.now

    private var title: LocalizedStringKey { party.scheduledFor == nil ? "Schedule" : "Change Time" }

    private var range: ClosedRange<Date> { opened...opened.addingTimeInterval(30 * 24 * 3600) }

    var body: some View {
        SettingsForm {
            Section {
                DateTimeRow(title: "Starts", date: $date, range: range)
            } footer: {
                Text("Any time from now to 30 days ahead.")
            }
            Section {
                Button {
                    Task {
                        isSaving = true
                        if await save(date) { dismiss() }
                        isSaving = false
                    }
                } label: {
                    Text(isSaving ? "Saving…" : "Save")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .formRowButton()
                .disabled(isSaving || date < .now || date > range.upperBound)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(title)
        .onAppear { if let start = party.scheduledFor, start > .now { date = start } }
    }
}
