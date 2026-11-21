// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

@MainActor @Observable
final class AdminUsersModel {
    private(set) var users: [JellyfinUser] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var actionError: String?
    var actionDone: String?

    let admin = JellyfinAdminClient()

    func load(authManager: AuthManager) async {
        guard let access = AdminAccess.session(authManager) else {
            errorMessage = AdminAccess.unavailableMessage
            isLoading = false
            return
        }
        do {
            users = try await admin.users(credential: access.credential, authHeader: access.header)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't load the server's users.")
        }
        isLoading = false
    }

    func perform(_ authManager: AuthManager, done: String? = nil, failure: String,
                 _ work: @escaping (JellyfinAdminClient, ServerCredential, String) async throws -> Void) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await work(admin, access.credential, access.header)
                HapticManager.impact(.light)
                if let done { actionDone = done }
                await load(authManager: authManager)
            } catch {
                actionError = failure
            }
        }
    }
}

/// Every user on the server, with Add User.
struct AdminUsersView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = AdminUsersModel()
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newPassword = ""

    var body: some View {
        List {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(DT.Color.textSecondary)
            }
            ForEach(model.users) { user in
                NavigationLink {
                    AdminUserDetailView(user: user, model: model)
                } label: {
                    HStack(spacing: 12) {
                        AdminUserAvatar(user: user, credential: AdminAccess.session(authManager)?.credential)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .foregroundStyle(user.isDisabled ? DT.Color.textSecondary : DT.Color.textPrimary)
                            Text(subtitle(user))
                                .font(.system(.caption))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                }
            }
        }
        .overlay { if model.isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Users")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("Add User")
            }
        }
        .alert("Add User", isPresented: $showAdd) {
            TextField("Name", text: $newName)
                .autocorrectionDisabled()
            SecureField("Password", text: $newPassword)
            Button("Add") {
                let name = newName.trimmingCharacters(in: .whitespaces), password = newPassword
                newName = ""; newPassword = ""
                guard !name.isEmpty else { return }
                model.perform(authManager, done: String(localized: "“\(name)” can now sign in. Set what they can watch and do on their page."),
                              failure: String(localized: "The user wasn't added. The name may already be taken.")) { admin, credential, header in
                    try await admin.createUser(name: name, password: password, credential: credential, authHeader: header)
                }
            }
            Button("Cancel", role: .cancel) { newName = ""; newPassword = "" }
        } message: {
            Text("They can see every library to begin with. A blank password lets them sign in without one.")
        }
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
        .adminResultAlerts(error: $model.actionError, done: $model.actionDone)
    }

    private func subtitle(_ user: JellyfinUser) -> String {
        var parts: [String] = []
        if user.isAdministrator { parts.append(String(localized: "Admin")) }
        if user.isDisabled { parts.append(String(localized: "Disabled")) }
        if !user.hasPassword { parts.append(String(localized: "No password")) }
        if let last = user.lastActivity {
            parts.append(String(localized: "Active \(last.formatted(.relative(presentation: .named)))"))
        } else {
            parts.append(String(localized: "Never signed in"))
        }
        return parts.joined(separator: " · ")
    }
}

/// A user's Jellyfin picture, or their initials, with a key for an admin.
private struct AdminUserAvatar: View {
    let user: JellyfinUser
    let credential: ServerCredential?

    private var initials: String {
        user.name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    var body: some View {
        ZStack {
            Circle().fill(user.isDisabled ? DT.Color.textSecondary.opacity(0.4) : DT.Color.accent)
            Text(initials)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DT.Color.onAccent)
            if let tag = user.primaryImageTag, let credential {
                RetryingAsyncImage(
                    url: JellyfinMediaClient.userImageURL(baseURL: credential.baseURL, userID: user.id, tag: tag,
                                                          fillWidth: 108, token: credential.accessToken),
                    logCategory: "AdminUserAvatar",
                    content: { $0.resizable().scaledToFill() },
                    placeholder: { Color.clear })
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .saturation(user.isDisabled ? 0 : 1)
        .overlay(alignment: .bottomTrailing) {
            if user.isAdministrator {
                Image(systemName: "key.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DT.Color.onAccent)
                    .padding(3)
                    .background(Circle().fill(DT.Color.palette("60A5FA")))
                    .offset(x: 3, y: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One user's permissions and library access, as switches, and their password.
private struct AdminUserDetailView: View {
    let user: JellyfinUser
    let model: AdminUsersModel

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var policy: [String: Any] = [:]
    @State private var originalPolicy: [String: Any] = [:]
    @State private var version: ServerVersion?
    @State private var confirmUntested = false
    @State private var notKept: [String] = []
    @State private var libraries: [JellyfinLibraryFolder] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showPassword = false
    @State private var password = ""
    @State private var confirmDelete = false

    private var isSelf: Bool { authManager.state.credential?.userID == user.id }

    private struct PolicySwitch {
        let key: String
        let title: LocalizedStringKey
    }

    private struct PolicyGroup {
        let title: LocalizedStringKey
        let switches: [PolicySwitch]
    }

    /// The switches, by what they're about. Keys the server doesn't send aren't shown.
    private static let groups: [PolicyGroup] = [
        PolicyGroup(title: "Account", switches: [
            PolicySwitch(key: "IsAdministrator", title: "Administrator"),
            PolicySwitch(key: "IsDisabled", title: "Disabled"),
            PolicySwitch(key: "IsHidden", title: "Hidden from Sign-In Screens"),
            PolicySwitch(key: "EnableRemoteAccess", title: "Allow Remote Connections"),
        ]),
        PolicyGroup(title: "Playback", switches: [
            PolicySwitch(key: "EnableMediaPlayback", title: "Allow Playback"),
            PolicySwitch(key: "EnableAudioPlaybackTranscoding", title: "Allow Audio Conversion"),
            PolicySwitch(key: "EnableVideoPlaybackTranscoding", title: "Allow Video Conversion"),
            PolicySwitch(key: "EnablePlaybackRemuxing", title: "Allow Remuxing"),
            PolicySwitch(key: "ForceRemoteSourceTranscoding", title: "Always Convert Remote Sources"),
            PolicySwitch(key: "EnableLiveTvAccess", title: "Live TV"),
            PolicySwitch(key: "EnableLiveTvManagement", title: "Manage Live TV Recordings"),
            PolicySwitch(key: "EnableSharedDeviceControl", title: "Control Shared Devices"),
            PolicySwitch(key: "EnableRemoteControlOfOtherUsers", title: "Control Other Users' Playback"),
        ]),
        PolicyGroup(title: "Content", switches: [
            PolicySwitch(key: "EnableContentDownloading", title: "Allow Downloads"),
            PolicySwitch(key: "EnableContentDeletion", title: "Allow Deleting Media"),
            PolicySwitch(key: "EnableSubtitleManagement", title: "Manage Subtitles"),
            PolicySwitch(key: "EnableLyricManagement", title: "Manage Lyrics"),
            PolicySwitch(key: "EnableCollectionManagement", title: "Manage Collections"),
            PolicySwitch(key: "EnablePublicSharing", title: "Allow Public Sharing"),
        ]),
    ]

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                AdminCompatibilityNote(status: ServerCompatibility.status(version))
                ForEach(Self.groups.indices, id: \.self) { index in
                    let group = Self.groups[index]
                    Section(group.title) {
                        ForEach(group.switches.filter { policy[$0.key] is Bool && ServerCompatibility.allows($0.key, on: version) }, id: \.key) { entry in
                            Toggle(entry.title, isOn: flag(entry.key))
                                .disabled(isSelf && (entry.key == "IsAdministrator" || entry.key == "IsDisabled"))
                        }
                    }
                }
                Section {
                    Toggle("All Libraries", isOn: flag("EnableAllFolders"))
                    if policy["EnableAllFolders"] as? Bool == false {
                        ForEach(libraries) { library in
                            Toggle(library.name, isOn: folder(library.id))
                        }
                    }
                } header: {
                    Text("Library Access")
                } footer: {
                    Text("New libraries are included automatically only with All Libraries on.")
                }
                Section {
                    Button { showPassword = true } label: {
                        Label("Set Password", systemImage: "key")
                    }
                    if !isSelf {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete User", systemImage: "person.crop.circle.badge.minus")
                                .foregroundStyle(DT.Color.palette("F43F5E"))
                        }
                    }
                } footer: {
                    if isSelf { Text("You can't remove your own admin rights or delete yourself here.") }
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(user.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if ServerCompatibility.status(version).needsConfirmation { confirmUntested = true } else { save() }
                }
                .disabled(isLoading || isSaving || !ServerCompatibility.status(version).canSave
                          || ServerEditGuard.changedKeys(from: originalPolicy, to: policy).isEmpty)
            }
        }
        .adminDiscardChangesGuard(!ServerEditGuard.changedKeys(from: originalPolicy, to: policy).isEmpty)
        .task { await load() }
        .untestedServerConfirmation(isPresented: $confirmUntested, status: ServerCompatibility.status(version)) { save() }
        .alert("Not All Saved", isPresented: Binding(get: { !notKept.isEmpty }, set: { if !$0 { notKept = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The server didn't keep \(ServerEditGuard.describe(notKept)) as sent. The page now shows what it has.")
        }
        .alert("Set Password", isPresented: $showPassword) {
            SecureField("New Password", text: $password)
            Button("Set") {
                let password = password
                self.password = ""
                model.perform(authManager, done: String(localized: "\(user.name)'s password was changed."),
                              failure: String(localized: "The password wasn't changed.")) { admin, credential, header in
                    try await admin.setPassword(userId: user.id, to: password, credential: credential, authHeader: header)
                }
            }
            Button("Cancel", role: .cancel) { password = "" }
        } message: {
            Text("Leave it blank to let \(user.name) sign in without a password.")
        }
        .alert("Delete \(user.name)?", isPresented: $confirmDelete) {
            Button("Delete User", role: .destructive) {
                model.perform(authManager, failure: String(localized: "The user wasn't deleted.")) { admin, credential, header in
                    try await admin.deleteUser(id: user.id, credential: credential, authHeader: header)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their watch history, favourites and settings go too. This can't be undone.")
        }
    }

    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { policy[key] as? Bool ?? false }, set: { policy[key] = $0 })
    }

    private func folder(_ id: String) -> Binding<Bool> {
        Binding(
            get: { (policy["EnabledFolders"] as? [String] ?? []).contains(id) },
            set: { on in
                var folders = policy["EnabledFolders"] as? [String] ?? []
                folders.removeAll { $0 == id }
                if on { folders.append(id) }
                policy["EnabledFolders"] = folders
            }
        )
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else {
            model.actionError = AdminAccess.unavailableMessage
            isLoading = false
            return
        }
        version = await ServerVersions.version(for: access.credential)
        async let policyData = model.admin.policy(userId: user.id, credential: access.credential, authHeader: access.header)
        async let folders = model.admin.libraries(credential: access.credential, authHeader: access.header)
        if let data = try? await policyData, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            policy = object
            originalPolicy = object
        } else {
            model.actionError = String(localized: "Couldn't load \(user.name)'s permissions.")
        }
        libraries = (try? await folders) ?? []
        isLoading = false
    }

    private func save() {
        guard ServerCompatibility.status(version).canSave else { return }
        let mismatched = ServerEditGuard.mismatches(from: originalPolicy, to: policy)
        guard mismatched.isEmpty else {
            model.actionError = String(localized: "Nothing was saved: \(ServerEditGuard.describe(mismatched)) didn't match what the server expects.")
            return
        }
        guard let access = AdminAccess.session(authManager),
              let data = try? JSONSerialization.data(withJSONObject: policy) else { return }
        let changed = ServerEditGuard.changedKeys(from: originalPolicy, to: policy), sent = policy
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await model.admin.setPolicy(userId: user.id, data, credential: access.credential, authHeader: access.header)
            } catch {
                model.actionError = String(localized: "The permissions weren't saved.")
                return
            }
            // What the server kept, read back, so a permission it refused isn't reported as saved.
            if let reread = try? await model.admin.policy(userId: user.id, credential: access.credential, authHeader: access.header),
               let object = try? JSONSerialization.jsonObject(with: reread) as? [String: Any] {
                notKept = ServerEditGuard.notKept(changed, sent: sent, reread: object)
                policy = object
                originalPolicy = object
            }
            if notKept.isEmpty { model.actionDone = String(localized: "\(user.name)'s permissions were saved.") }
            HapticManager.impact(.light)
            await model.load(authManager: authManager)
        }
    }
}

/// Every device signed in to the server; removing one signs it out.
struct AdminDevicesView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var devices: [JellyfinDevice] = []
    @State private var isLoading = true
    @State private var removing: JellyfinDevice?
    @State private var error: String?

    // Signing out the device Arcfin runs on would revoke the token it's using.
    private let ownDeviceID = UserDefaults.standard.string(forKey: "arcfin.deviceId")

    var body: some View {
        List {
            ForEach(devices) { device in
                let isThisDevice = device.id == ownDeviceID
                HStack(spacing: 12) {
                    Image(systemName: icon(device))
                        .font(.system(.title3))
                        .foregroundStyle(DT.Color.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).foregroundStyle(DT.Color.textPrimary)
                        Text([[device.appName, device.appVersion].compactMap { $0 }.joined(separator: " "),
                              device.lastUserName,
                              device.lastActivity.map { $0.formatted(.relative(presentation: .named)) }]
                            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    if isThisDevice {
                        Spacer()
                        Text("This Device")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .swipeActions {
                    if !isThisDevice {
                        Button("Sign Out", role: .destructive) { removing = device }
                    }
                }
                .contextMenu {
                    if !isThisDevice {
                        Button("Sign Out Device", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { removing = device }
                    }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Devices")
        .task { await load() }
        .refreshable { await load() }
        .alert("Sign Out \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
               presenting: removing) { device in
            Button("Sign Out", role: .destructive) { remove(device) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's removed from the server and has to sign in again.")
        }
        .alert("Couldn't Do That", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func icon(_ device: JellyfinDevice) -> String {
        let text = (device.name + " " + device.appName).lowercased()
        if text.contains("tv") { return "appletv" }
        if text.contains("iphone") || text.contains("android") || text.contains("mobile") { return "iphone" }
        if text.contains("ipad") || text.contains("tablet") { return "ipad" }
        if text.contains("mac") || text.contains("windows") || text.contains("web") || text.contains("firefox") || text.contains("chrome") { return "desktopcomputer" }
        return "display"
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else {
            error = AdminAccess.unavailableMessage
            isLoading = false
            return
        }
        if let fetched = try? await JellyfinAdminClient().devices(credential: access.credential, authHeader: access.header) {
            devices = fetched.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        } else {
            error = String(localized: "Couldn't load the server's devices.")
        }
        isLoading = false
    }

    private func remove(_ device: JellyfinDevice) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await JellyfinAdminClient().deleteDevice(id: device.id, credential: access.credential, authHeader: access.header)
                devices.removeAll { $0.id == device.id }
            } catch {
                self.error = String(localized: "\(device.name) wasn't signed out.")
            }
        }
    }
}
