// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import SyncEngine

@MainActor @Observable
final class DevicesSyncModel {
    private(set) var devices: [ArcfinSyncDevice] = []
    private(set) var isLoading = true
    private(set) var loadFailed = false
    var actionError: String?

    private let client = ArcfinSyncClient()

    func load(authManager: AuthManager) async {
        guard let session = authManager.arcfinSyncDevicesSession else { isLoading = false; return }
        do {
            devices = try await client.fetchDevices(credential: session.credential, authHeader: session.header)
            loadFailed = false
        } catch {
            loadFailed = devices.isEmpty
        }
        isLoading = false
    }

    func device(_ id: String) -> ArcfinSyncDevice? { devices.first { $0.deviceId == id } }

    func rename(_ device: ArcfinSyncDevice, to name: String, authManager: AuthManager) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if device.isCurrent {
            if await authManager.renameThisDevice(trimmed) {
                await load(authManager: authManager)
            } else {
                actionError = String(localized: "The new name wasn't saved. Check your connection and try again.")
            }
            return
        }
        guard let session = authManager.arcfinSyncDevicesSession,
              let renamed = try? await client.renameDevice(credential: session.credential, authHeader: session.header,
                                                           deviceID: device.deviceId, name: trimmed)
        else {
            actionError = String(localized: "The new name wasn't saved. Check your connection and try again.")
            return
        }
        devices = devices.map { $0.deviceId == renamed.deviceId ? renamed : $0 }
    }

    func forget(_ device: ArcfinSyncDevice, authManager: AuthManager) async -> Bool {
        guard let session = authManager.arcfinSyncDevicesSession,
              (try? await client.forgetDevice(credential: session.credential, authHeader: session.header,
                                              deviceID: device.deviceId)) != nil
        else {
            actionError = String(localized: "The device wasn't forgotten. Check your connection and try again.")
            return false
        }
        devices.removeAll { $0.deviceId == device.deviceId }
        return true
    }
}

/// Settings › Server › Devices & Sync: this device's name and sync mode, sending its settings to
/// the others, and every device signed in with Arcfin on this account.
struct DevicesSyncView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(SettingsSyncMode.key) private var syncMode = SettingsSyncMode.automatic
    @State private var model = DevicesSyncModel()
    @State private var nameDraft = ""
    @State private var confirmSend = false
    @State private var sendResult: String?

    private var thisDevice: ArcfinSyncDevice? {
        model.devices.first(where: \.isCurrent) ?? authManager.arcfinSyncCurrentDevice
    }

    private var otherDevices: [ArcfinSyncDevice] { model.devices.filter { !$0.isCurrent } }

    var body: some View {
        SettingsForm {
            Section {
                TextField("Device Name", text: $nameDraft)
                    .autocorrectionDisabled()
                    .onSubmit(saveName)
                    .tvListRow()
                if let thisDevice, nameDraft.trimmingCharacters(in: .whitespaces) != thisDevice.name {
                    Button("Save Name", action: saveName)
                        .formRowButton()
                }
            } header: {
                Text("This Device")
            } footer: {
                Text("How this device appears on your other devices. Leave it empty to use the name Jellyfin has for it.")
            }

            Section {
                SettingsPicker("Sync Settings", selection: $syncMode, options: SettingsSyncMode.allCases) { Text($0.title) }
                    .syncLocked(SettingsSyncMode.key, authManager)
                    .onChange(of: syncMode) { authManager.syncModeChanged() }
            } footer: {
                Text(modeFooter)
            }

            Section {
                Button { confirmSend = true } label: {
                    TVRowLabelText(title: "Send This Device's Settings to My Other Devices",
                                   detail: "Your other devices change to match this one. Locked settings stay as your admin set them.")
                }
                .formRowButton()
                .disabled(authManager.isSyncingArcfin)
            }

            Section {
                if model.isLoading && model.devices.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .tvReadOnlyRow()
                } else if model.loadFailed {
                    Text("Couldn't load your devices. Check your connection and try again.")
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                } else if otherDevices.isEmpty {
                    Text("Sign in to Arcfin on another device and it appears here.")
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
                ForEach(otherDevices) { device in
                    NavigationLink {
                        SyncDeviceDetailView(model: model, deviceID: device.deviceId).tvSettingsPage()
                    } label: {
                        SyncDeviceRow(device: device)
                    }
                    .tvListRow()
                }
            } header: {
                Text("My Other Devices")
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Devices & Sync")
        .task {
            await model.load(authManager: authManager)
            nameDraft = thisDevice?.name ?? authManager.authClient.currentDeviceName
        }
        .refreshable { await model.load(authManager: authManager) }
        .alert("Send This Device's Settings?", isPresented: $confirmSend) {
            Button("Send") { send() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your other devices take this device's settings the next time they sync. Ones set to Ask First ask before they do.")
        }
        .alert("Settings", isPresented: Binding(get: { sendResult != nil }, set: { if !$0 { sendResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sendResult ?? "")
        }
        .alert("Couldn't Do That", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var modeFooter: String {
        switch syncMode {
        case .automatic: String(localized: "Settings you change here go to your other devices, and theirs come here.")
        case .ask: String(localized: "Settings you change here still go to your other devices. When one changes them, this device asks before using them.")
        case .off: String(localized: "This device keeps its own settings. Settings your admin locked still apply.")
        }
    }

    private func saveName() {
        guard let thisDevice else { return }
        Task { await model.rename(thisDevice, to: nameDraft, authManager: authManager) }
    }

    private func send() {
        Task {
            sendResult = await authManager.sendSettingsToOtherDevices()
                ? String(localized: "Sent. Your other devices change to match this one the next time they sync.")
                : String(localized: "The settings weren't sent. Check your connection and try again.")
        }
    }
}

private struct SyncDeviceRow: View {
    let device: ArcfinSyncDevice

    private var detail: String {
        var parts = [SettingDisplay.platformName(device.platform)]
        if let lastSeen = device.lastSeen {
            parts.append(String(localized: "Last seen \(lastSeen.formatted(.relative(presentation: .named)))"))
        }
        parts.append(SettingDisplay.syncMode(device.syncMode))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Label {
            TVRowLabelText(verbatim: device.name, detail: "\(detail)")
        } icon: {
            Image(systemName: SettingDisplay.platformImage(device.platform))
        }
    }
}

/// One of the account's other devices: rename it, use its settings here, see how they differ,
/// or forget it.
struct SyncDeviceDetailView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    let model: DevicesSyncModel
    let deviceID: String
    @State private var nameDraft = ""
    @State private var confirmUse = false
    @State private var confirmForget = false
    @State private var usedSettings = false

    private var device: ArcfinSyncDevice? { model.device(deviceID) }

    var body: some View {
        SettingsForm {
            if let device {
                Section {
                    TextField("Device Name", text: $nameDraft)
                        .autocorrectionDisabled()
                        .onSubmit { rename(device) }
                        .tvListRow()
                    if nameDraft.trimmingCharacters(in: .whitespaces) != device.name {
                        Button("Save Name") { rename(device) }
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
                    if let lastSeen = device.lastSeen {
                        LabeledContent("Last Seen", value: lastSeen.formatted(.relative(presentation: .named)))
                            .tvReadOnlyRow()
                    }
                    LabeledContent("Sync Settings", value: SettingDisplay.syncMode(device.syncMode))
                        .tvReadOnlyRow()
                }

                Section {
                    Button { confirmUse = true } label: {
                        TVRowLabelText(title: "Use These Settings Here",
                                       detail: "This device changes to match that one. Locked settings stay as your admin set them.")
                    }
                    .formRowButton()
                    .disabled(differences(device).isEmpty)
                }

                SyncDifferencesSection(device: device, differences: differences(device))

                Section {
                    Button(role: .destructive) { HapticManager.warning(); confirmForget = true } label: {
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
        .alert("Use These Settings Here?", isPresented: $confirmUse) {
            Button("Use These Settings") {
                if let device { authManager.useSettings(of: device) }
                usedSettings = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The settings that differ change to match \(device?.name ?? "").")
        }
        .alert("Forget This Device?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) {
                guard let device else { return }
                Task { if await model.forget(device, authManager: authManager) { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stays signed in, and appears again the next time it opens Arcfin.")
        }
        .alert("Done", isPresented: $usedSettings) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device now uses those settings.")
        }
    }

    private func differences(_ device: ArcfinSyncDevice) -> [SyncDifference] {
        guard let profile = authManager.state.credential?.id.uuidString else { return [] }
        let local = SettingsSyncEngine.collectLocalPayload().settings
        let (set, clear) = SettingsSyncEngine.replacement(
            source: device.settings, sourcePlatform: device.platform, local: local,
            locked: SettingsSyncEngine.lockedKeys(profile: profile))
        let schema = SettingsSchema.bundled
        return schema.settings.compactMap { setting in
            guard set[setting.key] != nil || clear.contains(setting.key) else { return nil }
            return SyncDifference(setting: setting, there: set[setting.key], here: local[setting.key])
        }
    }

    private func rename(_ device: ArcfinSyncDevice) {
        Task { await model.rename(device, to: nameDraft, authManager: authManager) }
    }
}

struct SyncDifference: Identifiable {
    let setting: SettingsSchema.Setting
    /// nil: that device has the default.
    let there: String?
    let here: String?
    var id: String { setting.key }
}

private struct SyncDifferencesSection: View {
    let device: ArcfinSyncDevice
    let differences: [SyncDifference]

    var body: some View {
        Section {
            if differences.isEmpty {
                Text("Its settings are the same as this device's.")
                    .foregroundStyle(DT.Color.textSecondary)
                    .tvReadOnlyRow()
            }
            ForEach(differences) { difference in
                let there = SettingDisplay.value(difference.there, of: difference.setting)
                let here = SettingDisplay.value(difference.here, of: difference.setting)
                TVRowLabelText(verbatim: SettingDisplay.title(difference.setting),
                               detail: "\(String(localized: "There: \(there)")) · \(String(localized: "Here: \(here)"))")
                    .tvReadOnlyRow()
            }
        } header: {
            Text("Different Here")
        }
    }
}
