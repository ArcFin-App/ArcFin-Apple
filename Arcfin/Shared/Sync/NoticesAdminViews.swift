// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

private func statusBadge(_ status: NoticeStatus) -> AdminBadge {
    switch status {
    case .showing: AdminBadge("Showing", isProminent: true)
    case .scheduled: AdminBadge("Scheduled")
    case .ended: AdminBadge("Ended")
    }
}

/// Dates far enough back to edit something already showing, and a year ahead.
private let noticeRange = Date.now.addingTimeInterval(-7 * 24 * 3600)...Date.now.addingTimeInterval(365 * 24 * 3600)

/// Household › Announcements: messages shown in Arcfin, to everyone or to chosen people.
struct AnnouncementsAdminView: View {
    let model: HouseholdAdminModel
    let users: [ArcfinSyncAdminUser]

    private var announcements: [Announcement] { model.admin?.announcements ?? [] }

    var body: some View {
        SettingsForm {
            AdminIntroSection(text: "A banner in Arcfin, for everyone or chosen people, from and until the times you set. Nothing shows until you add one.")
            Section {
                if announcements.isEmpty {
                    Text("No announcements yet.")
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
                ForEach(announcements) { announcement in
                    NavigationLink {
                        AnnouncementEditor(model: model, users: users, original: announcement).tvSettingsPage()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            TVRowLabelText(verbatim: announcement.title.isEmpty ? String(localized: "Untitled") : announcement.title,
                                           detail: "\(audience(announcement))")
                            Spacer(minLength: DT.Spacing.xs)
                            statusBadge(NoticeStatus.of(announcement.starts, announcement.ends))
                        }
                    }
                    .tvListRow()
                }
                NavigationLink {
                    AnnouncementEditor(model: model, users: users, original: nil).tvSettingsPage()
                } label: {
                    TVRowLabelText(title: "Add Announcement")
                }
                .tvListRow()
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Announcements")
    }

    private func audience(_ announcement: Announcement) -> String {
        let style = announcement.style == "warning" ? String(localized: "Warning") : String(localized: "Info")
        let who = announcement.users.isEmpty ? String(localized: "Everyone")
            : announcement.users.map { users.name(of: $0) }.formatted(.list(type: .and))
        return style + " · " + who
    }
}

private struct AnnouncementEditor: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    let model: HouseholdAdminModel
    let users: [ArcfinSyncAdminUser]
    let original: Announcement?
    @State private var draft = Announcement()
    @State private var chosenPeople = false
    @State private var loaded = false
    @State private var confirmDelete = false

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !(draft.starts.map { start in draft.ends.map { $0 <= start } ?? false } ?? false)
            && !(chosenPeople && draft.users.isEmpty)
    }

    var body: some View {
        SettingsForm {
            Section {
                TextField("Title", text: $draft.title)
                    .tvListRow()
                TextField("Message", text: $draft.message, axis: .vertical)
                    .lineLimit(2...6)
                    .tvListRow()
                SettingsPicker("Style", selection: $draft.style, options: ["info", "warning"]) { value in
                    value == "warning" ? Text("Warning") : Text("Info")
                }
            }
            Section {
                OptionalDateRows(title: "Starts", toggle: "Start at a Set Time", date: $draft.starts)
                OptionalDateRows(title: "Ends", toggle: "End at a Set Time", date: $draft.ends)
            } footer: {
                Text("Without a start it shows straight away; without an end it shows until you delete it.")
            }
            Section {
                SettingsPicker("Show To", selection: $chosenPeople, options: [false, true]) { $0 ? Text("Chosen People") : Text("Everyone") }
                if chosenPeople {
                    ForEach(users) { user in
                        Toggle(isOn: chosen(user.userId)) {
                            TVRowLabelText(verbatim: user.name)
                        }
                        .tvListRow()
                    }
                }
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    Text(model.isBusy ? "Saving…" : "Save")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .formRowButton()
                .disabled(model.isBusy || !canSave)
                if original != nil {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Delete Announcement")
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                    .formRowButton()
                    .disabled(model.isBusy)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(original == nil ? LocalizedStringKey("New Announcement") : "Edit Announcement")
        .onAppear {
            guard !loaded else { return }
            if let original { draft = original }
            chosenPeople = !draft.users.isEmpty
            loaded = true
        }
        .alert("Delete This Announcement?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    let rest = (model.admin?.announcements ?? []).filter { $0.id != draft.id }
                    if await model.saveAnnouncements(rest, authManager: authManager) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stops showing in Arcfin.")
        }
    }

    private func chosen(_ userID: String) -> Binding<Bool> {
        let id = ArcfinCompanionClient.normalized(userID)
        return Binding(
            get: { draft.users.contains { ArcfinCompanionClient.normalized($0) == id } },
            set: { on in
                draft.users.removeAll { ArcfinCompanionClient.normalized($0) == id }
                if on { draft.users.append(userID) }
            })
    }

    private func save() async {
        var next = draft
        next.title = next.title.trimmingCharacters(in: .whitespaces)
        if !chosenPeople { next.users = [] }
        var all = model.admin?.announcements ?? []
        if let i = all.firstIndex(where: { $0.id == next.id }) { all[i] = next } else { all.append(next) }
        if await model.saveAnnouncements(all, authManager: authManager) { dismiss() }
    }
}

/// A switch for whether there's a time, and the time when there is.
private struct OptionalDateRows: View {
    let title: LocalizedStringKey
    let toggle: LocalizedStringKey
    @Binding var date: Date?

    var body: some View {
        Toggle(isOn: Binding(get: { date != nil }, set: { date = $0 ? (date ?? Date.now.addingTimeInterval(3600)) : nil })) {
            TVRowLabelText(title: toggle)
        }
        .tvListRow()
        if let current = date {
            DateTimeRow(title: title, date: Binding(get: { current }, set: { date = $0 }), range: noticeRange)
        }
    }
}

/// Household › Planned Maintenance: when the server will be down, so Arcfin can say so.
struct MaintenanceAdminView: View {
    let model: HouseholdAdminModel

    private var windows: [MaintenanceWindow] { (model.admin?.maintenance ?? []).sorted { $0.starts < $1.starts } }

    var body: some View {
        SettingsForm {
            AdminIntroSection(text: "When the server will be down. Arcfin warns people ahead of time, then shows when the server will be back instead of a connection error. Windows that have ended are removed.")
            Section {
                if windows.isEmpty {
                    Text("No maintenance planned.")
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
                ForEach(windows) { window in
                    NavigationLink {
                        MaintenanceEditor(model: model, original: window).tvSettingsPage()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            TVRowLabelText(verbatim: "\(LiveTime.when(window.starts)) – \(LiveTime.when(window.ends))",
                                           detail: window.message.isEmpty ? nil : "\(window.message)")
                            Spacer(minLength: DT.Spacing.xs)
                            statusBadge(NoticeStatus.of(window.starts, window.ends))
                        }
                    }
                    .tvListRow()
                }
                NavigationLink {
                    MaintenanceEditor(model: model, original: nil).tvSettingsPage()
                } label: {
                    TVRowLabelText(title: "Add Maintenance")
                }
                .tvListRow()
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Planned Maintenance")
    }
}

private struct MaintenanceEditor: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    let model: HouseholdAdminModel
    let original: MaintenanceWindow?
    @State private var draft = MaintenanceWindow(starts: Date.now.addingTimeInterval(24 * 3600), ends: Date.now.addingTimeInterval(26 * 3600))
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        SettingsForm {
            Section {
                DateTimeRow(title: "Starts", date: $draft.starts, range: noticeRange)
                DateTimeRow(title: "Ends", date: $draft.ends, range: noticeRange)
                TextField("Message", text: $draft.message, axis: .vertical)
                    .lineLimit(2...6)
                    .tvListRow()
            } footer: {
                Text("The message is optional, for example what's being done.")
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    Text(model.isBusy ? "Saving…" : "Save")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .formRowButton()
                .disabled(model.isBusy || draft.ends <= draft.starts)
                if original != nil {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Text("Delete")
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                    .formRowButton()
                    .disabled(model.isBusy)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(original == nil ? LocalizedStringKey("Add Maintenance") : "Edit Maintenance")
        .onAppear {
            guard !loaded else { return }
            if let original { draft = original }
            loaded = true
        }
        .alert("Delete This Maintenance?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    let rest = (model.admin?.maintenance ?? []).filter { $0.id != draft.id }
                    if await model.saveMaintenance(rest, authManager: authManager) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Arcfin stops telling people about it.")
        }
    }

    private func save() async {
        var all = model.admin?.maintenance ?? []
        if let i = all.firstIndex(where: { $0.id == draft.id }) { all[i] = draft } else { all.append(draft) }
        if await model.saveMaintenance(all, authManager: authManager) { dismiss() }
    }
}
