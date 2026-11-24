// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Arcfin for Everyone › Household and Downloads: download limits, shared accounts, announcements
/// and planned maintenance, each saved on its own.
@MainActor @Observable
final class HouseholdAdminModel {
    private(set) var admin: HouseholdAdmin?
    private(set) var loadError: String?
    private(set) var isBusy = false
    var actionError: String?

    private let client = ArcfinCompanionClient()

    func load(authManager: AuthManager) async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            admin = try await client.householdAdmin(credential: access.credential, authHeader: access.header)
            loadError = nil
        } catch {
            if admin == nil { loadError = AdminSyncError.loadMessage() }
        }
    }

    func saveDownloads(_ settings: DownloadLimitSettings, authManager: AuthManager) async -> Bool {
        await save(authManager) { try await self.client.saveDownloadLimits(settings, credential: $0, authHeader: $1) }
    }

    func saveSharedAccounts(_ accounts: [SharedAccountSetting], authManager: AuthManager) async -> Bool {
        await save(authManager) { try await self.client.saveSharedAccounts(accounts, credential: $0, authHeader: $1) }
    }

    func saveAnnouncements(_ announcements: [Announcement], authManager: AuthManager) async -> Bool {
        await save(authManager) { try await self.client.saveAnnouncements(announcements, credential: $0, authHeader: $1) }
    }

    func saveMaintenance(_ windows: [MaintenanceWindow], authManager: AuthManager) async -> Bool {
        await save(authManager) { try await self.client.saveMaintenance(windows, credential: $0, authHeader: $1) }
    }

    private func save(_ authManager: AuthManager, _ call: (ServerCredential, String) async throws -> HouseholdAdmin) async -> Bool {
        guard let access = authManager.arcfinSyncDevicesSession else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            admin = try await call(access.credential, access.header)
            HapticManager.success()
            return true
        } catch {
            actionError = AdminSyncError.message(error)
            return false
        }
    }
}

/// The hub: one row for each household feature the plugin has.
struct HouseholdAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let users: [ArcfinSyncAdminUser]
    let features: Set<String>
    @State private var model = HouseholdAdminModel()

    var body: some View {
        SettingsForm {
            if let admin = model.admin {
                Section {
                    if features.contains("sharedAccounts") {
                        NavigationLink {
                            SharedAccountsAdminView(model: model, users: users).tvSettingsPage()
                        } label: {
                            TVRowLabelText(title: "Shared Accounts", detail: "\(String(localized: "Shared accounts: \(admin.sharedAccounts.count)"))")
                        }
                        .tvListRow()
                    }
                    if features.contains("announcements") {
                        NavigationLink {
                            AnnouncementsAdminView(model: model, users: users).tvSettingsPage()
                        } label: {
                            TVRowLabelText(title: "Announcements", detail: "\(String(localized: "Showing now: \(admin.announcements.filter { NoticeStatus.of($0.starts, $0.ends) == .showing }.count)"))")
                        }
                        .tvListRow()
                    }
                    if features.contains("maintenance") {
                        NavigationLink {
                            MaintenanceAdminView(model: model).tvSettingsPage()
                        } label: {
                            TVRowLabelText(title: "Planned Maintenance", detail: "\(String(localized: "Planned: \(admin.maintenance.filter { $0.ends > .now }.count)"))")
                        }
                        .tvListRow()
                    }
                }
            } else {
                AdminPendingSection(error: model.loadError)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Household")
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
        .adminErrorAlert(Binding(get: { model.actionError }, set: { model.actionError = $0 }))
    }
}

/// Whether an announcement or maintenance window is on now, still to come, or over.
enum NoticeStatus {
    case scheduled, showing, ended

    static func of(_ starts: Date?, _ ends: Date?, now: Date = .now) -> NoticeStatus {
        if let starts, starts > now { return .scheduled }
        if let ends, ends <= now { return .ended }
        return .showing
    }
}

/// A number with a decimal part, such as gigabytes; empty is nil.
struct DecimalRow: View {
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        LabeledContent {
            TextField(title, text: $text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .onChange(of: text) { _, new in
                    let cleaned = new.replacingOccurrences(of: ",", with: ".")
                    value = cleaned.isEmpty ? nil : Double(cleaned).map { max($0, 0) } ?? value
                }
        } label: {
            TVRowLabelText(title: title)
        }
        .tvListRow()
        .onAppear { text = value.map { $0.formatted(.number.grouping(.never)) } ?? "" }
    }
}
