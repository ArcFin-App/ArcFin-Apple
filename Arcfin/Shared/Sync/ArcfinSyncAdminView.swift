// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SyncEngine

/// Settings › Server › Arcfin for Everyone, and Admin › Arcfin for Everyone: what every Arcfin
/// app on this server starts with, what it can't change, and everyone's devices.
struct ArcfinSyncAdminView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = ArcfinSyncAdminModel()

    var body: some View {
        SettingsForm {
            if model.isLoading && model.savedPolicy.settings.isEmpty && model.users.isEmpty {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .tvReadOnlyRow()
                }
            } else if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
            } else {
                Section {
                    ForEach(model.schema.groups) { group in
                        let settings = model.schema.settings(in: group)
                        if !settings.isEmpty {
                            NavigationLink {
                                AdminPolicyGroupView(model: model, group: group, userID: nil).tvSettingsPage()
                            } label: {
                                TVRowLabelText(verbatim: SettingDisplay.groupTitle(group),
                                               detail: "\(summary(settings, user: nil))")
                            }
                            .tvListRow()
                        }
                    }
                } header: {
                    Text("Settings for Everyone")
                } footer: {
                    Text("A default is what a setting starts at until someone changes it. A locked setting always has its default, and can't be changed in the app.")
                }

                Section {
                    ForEach(model.users) { user in
                        NavigationLink {
                            AdminSyncUserView(model: model, userID: user.userId).tvSettingsPage()
                        } label: {
                            TVRowLabelText(verbatim: user.name, detail: "\(userSummary(user))")
                        }
                        .tvListRow()
                    }
                } header: {
                    Text("Users & Devices")
                } footer: {
                    Text("Each user's own defaults and locks, and the devices they use Arcfin on.")
                }

            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Arcfin for Everyone")
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
        .alert("Couldn't Do That", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private func summary(_ settings: [SettingsSchema.Setting], user: String?) -> String {
        let locked = settings.filter { model.isLocked($0.key) }.count
        let defaults = settings.filter { model.defaultValue($0.key, user: nil) != nil }.count
        return String(localized: "Defaults: \(defaults) · Locked: \(locked)")
    }

    private func userSummary(_ user: ArcfinSyncAdminUser) -> String {
        let devices = String(localized: "Devices: \(user.devices.count)")
        let overrides = model.overrideCount(user: user.userId)
        return overrides == 0 ? devices : "\(devices) · \(String(localized: "Own settings: \(overrides)"))"
    }
}

/// One schema group's settings, each with its default and lock, for everyone or for one user.
struct AdminPolicyGroupView: View {
    @Environment(AuthManager.self) private var authManager
    let model: ArcfinSyncAdminModel
    let group: SettingsSchema.Group
    /// nil: everyone's.
    let userID: String?

    var body: some View {
        SettingsForm {
            ForEach(model.schema.settings(in: group)) { setting in
                Section {
                    AdminPolicySettingRows(model: model, setting: setting, userID: userID)
                } header: {
                    Text(verbatim: SettingDisplay.title(setting))
                } footer: {
                    Text(verbatim: footer(setting))
                }
            }
            Section {
                Button {
                    Task { await model.save(authManager: authManager) }
                } label: {
                    Text(model.isSaving ? "Saving…" : "Save Changes")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .formRowButton()
                .disabled(!model.hasChanges || model.isSaving)
                if model.hasChanges {
                    Button("Discard Changes", role: .destructive) { model.discardChanges() }
                        .formRowButton()
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(SettingDisplay.groupTitle(group))
    }

    private func footer(_ setting: SettingsSchema.Setting) -> String {
        var parts: [String] = []
        if setting.scope == .device { parts.append(String(localized: "Kept on each device; never synced.")) }
        if let value = setting.default {
            parts.append(String(localized: "The app's own default: \(SettingDisplay.value(value, of: setting))."))
        }
        let platforms = setting.platforms.map { SettingDisplay.platformName($0) }.formatted(.list(type: .and))
        if !platforms.isEmpty { parts.append(String(localized: "On \(platforms).")) }
        return parts.joined(separator: " ")
    }
}

private struct AdminPolicySettingRows: View {
    let model: ArcfinSyncAdminModel
    let setting: SettingsSchema.Setting
    let userID: String?

    private var choices: [String?]? {
        switch setting.type {
        case .bool: [nil, "true", "false"]
        case .int, .string, .double: setting.options.map { [nil] + $0.map(\.value) }
        case .json: nil
        }
    }

    private var defaultBinding: Binding<String?> {
        Binding(
            get: { model.defaultValue(setting.key, user: userID) },
            set: { value in
                if let userID { model.setUserDefault(value, for: setting.key, user: userID) }
                else { model.setDefault(value, for: setting.key) }
            })
    }

    private func valid(_ text: String) -> Bool {
        switch setting.type {
        case .int: Int(text) != nil
        case .double: Double(text) != nil
        case .json: (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
        case .bool, .string: true
        }
    }

    private var noDefault: String {
        userID == nil ? String(localized: "No Default") : String(localized: "Same as Everyone")
    }

    var body: some View {
        if let choices {
            SettingsPicker("Default", selection: defaultBinding, options: choices) { value in
                Text(verbatim: value.map { SettingDisplay.value($0, of: setting) } ?? noDefault)
            }
        } else {
            TextField(noDefault, text: Binding(
                get: { defaultBinding.wrappedValue ?? "" },
                set: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    defaultBinding.wrappedValue = trimmed.isEmpty ? nil
                        : valid(trimmed) ? trimmed : defaultBinding.wrappedValue
                }))
                .autocorrectionDisabled()
                .tvListRow()
        }
        if let userID {
            SettingsPicker("Locked", selection: Binding(
                get: { model.lockChoice(setting.key, user: userID) },
                set: { model.setLockChoice($0, for: setting.key, user: userID) }),
                options: PolicyLockChoice.allCases) { choice in
                switch choice {
                case .inherited: Text(model.isLocked(setting.key) ? "Same as Everyone (Locked)" : "Same as Everyone (Not Locked)")
                case .locked: Text("Locked")
                case .unlocked: Text("Not Locked")
                }
            }
        } else {
            Toggle(isOn: Binding(get: { model.isLocked(setting.key) }, set: { model.setLocked($0, for: setting.key) })) {
                TVRowLabelText(title: "Locked")
            }
            .tvListRow()
        }
    }
}

/// One user: their own defaults and locks, the settings their account has, and their devices.
struct AdminSyncUserView: View {
    let model: ArcfinSyncAdminModel
    let userID: String

    var body: some View {
        SettingsForm {
            if let user = model.user(userID) {
                Section {
                    ForEach(model.schema.groups) { group in
                        if !model.schema.settings(in: group).isEmpty {
                            NavigationLink {
                                AdminPolicyGroupView(model: model, group: group, userID: userID).tvSettingsPage()
                            } label: {
                                TVRowLabelText(verbatim: SettingDisplay.groupTitle(group))
                            }
                            .tvListRow()
                        }
                    }
                } header: {
                    Text("Their Own Defaults and Locks")
                } footer: {
                    Text("These take the place of everyone's for this user.")
                }

                Section {
                    NavigationLink {
                        AdminSettingsListView(title: String(localized: "Saved Settings"), values: user.settings,
                                              schema: model.schema).tvSettingsPage()
                    } label: {
                        TVRowLabelText(title: "Saved Settings", detail: "What this user's devices have synced.")
                    }
                    .tvListRow()
                }

                Section {
                    if user.devices.isEmpty {
                        Text("No devices yet.")
                            .foregroundStyle(DT.Color.textSecondary)
                            .tvReadOnlyRow()
                    }
                    ForEach(user.devices) { device in
                        NavigationLink {
                            AdminSyncDeviceView(model: model, userID: userID, deviceID: device.deviceId).tvSettingsPage()
                        } label: {
                            Label {
                                TVRowLabelText(verbatim: device.name, detail: "\(deviceDetail(device))")
                            } icon: {
                                Image(systemName: SettingDisplay.platformImage(device.platform))
                            }
                        }
                        .tvListRow()
                    }
                } header: {
                    Text("Devices")
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(model.user(userID)?.name ?? "")
    }

    private func deviceDetail(_ device: ArcfinSyncDevice) -> String {
        var parts = [SettingDisplay.platformName(device.platform), SettingDisplay.syncMode(device.syncMode)]
        if let lastSeen = device.lastSeen { parts.append(lastSeen.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}

/// An admin's view of someone's device: rename it, see its settings, or forget it.
struct AdminSyncDeviceView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    let model: ArcfinSyncAdminModel
    let userID: String
    let deviceID: String
    @State private var nameDraft = ""
    @State private var confirmForget = false

    private var user: ArcfinSyncAdminUser? { model.user(userID) }
    private var device: ArcfinSyncDevice? { user?.devices.first { $0.deviceId == deviceID } }

    var body: some View {
        SettingsForm {
            if let user, let device {
                Section {
                    TextField("Device Name", text: $nameDraft)
                        .autocorrectionDisabled()
                        .onSubmit { rename(device, of: user) }
                        .tvListRow()
                    if nameDraft.trimmingCharacters(in: .whitespaces) != device.name {
                        Button("Save Name") { rename(device, of: user) }
                            .formRowButton()
                    }
                } footer: {
                    Text("Leave it empty to use the name Jellyfin has for it: \(device.jellyfinDeviceName).")
                }

                Section {
                    LabeledContent("Device", value: SettingDisplay.platformName(device.platform))
                        .tvReadOnlyRow()
                    if let model = device.model, !model.isEmpty {
                        LabeledContent("Model", value: model)
                            .tvReadOnlyRow()
                    }
                    if let version = device.appVersion, !version.isEmpty {
                        LabeledContent("App Version", value: version)
                            .tvReadOnlyRow()
                    }
                    LabeledContent("Sync Settings", value: SettingDisplay.syncMode(device.syncMode))
                        .tvReadOnlyRow()
                    NavigationLink {
                        AdminSettingsListView(title: device.name, values: device.settings, schema: model.schema).tvSettingsPage()
                    } label: {
                        TVRowLabelText(title: "Its Settings")
                    }
                    .tvListRow()
                }

                Section {
                    Button(role: .destructive) { confirmForget = true } label: {
                        Text("Forget Device")
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                    .formRowButton()
                } footer: {
                    Text("Removes it from this list. It stays signed in, and appears again the next time it opens Arcfin.")
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(device?.name ?? "")
        .onAppear { nameDraft = device?.name ?? "" }
        .alert("Forget This Device?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) {
                guard let user, let device else { return }
                Task { if await model.forgetDevice(device, of: user, authManager: authManager) { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stays signed in, and appears again the next time it opens Arcfin.")
        }
    }

    private func rename(_ device: ArcfinSyncDevice, of user: ArcfinSyncAdminUser) {
        Task { await model.renameDevice(device, of: user, to: nameDraft, authManager: authManager) }
    }
}

/// A list of settings and their values, by schema group.
struct AdminSettingsListView: View {
    let title: String
    let values: [String: String]
    let schema: SettingsSchema

    var body: some View {
        SettingsForm {
            if values.isEmpty {
                Section {
                    Text("Nothing saved yet.")
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
            }
            ForEach(schema.groups) { group in
                let settings = schema.settings(in: group).filter { values[$0.key] != nil }
                if !settings.isEmpty {
                    Section {
                        ForEach(settings) { setting in
                            LabeledContent(SettingDisplay.title(setting), value: SettingDisplay.value(values[setting.key], of: setting))
                                .tvReadOnlyRow()
                        }
                    } header: {
                        Text(verbatim: SettingDisplay.groupTitle(group))
                    }
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(title)
    }
}
