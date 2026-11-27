// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import JellyfinAPI
import SwiftUI
import VisionKit

/// Arcs friends: the only people a scene can be sent to. Each person has a code; adding someone's
/// code makes you friends both ways, so nobody on the server is listed to anyone they haven't added.
struct ArcsFriendsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var code: String?
    @State private var friends: [ArcPerson] = []
    @State private var loaded = false
    @State private var typed = ""
    @State private var isAdding = false
    @State private var message: String?
    @State private var scanning = false
    @State private var confirmNewCode = false

    private let client = ArcsClient()

    var body: some View {
        List {
            Section {
                if let code {
                    VStack(spacing: 14) {
                        QRCodeImage(text: ArcsClient.friendLink(code: code).absoluteString)
                            .frame(width: 180, height: 180)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel(Text("QR code for your friend code"))
                        Text(verbatim: code)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .textSelection(.enabled)
                        ShareLink(item: ArcsClient.friendLink(code: code),
                                  message: Text("Add me as a friend in Arcs on Arcfin: \(code)")) {
                            Label("Share Your Code", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } header: {
                Text("Your Code")
            } footer: {
                Text("Someone on your server adds this code, or scans it, and you can send each other scenes. Only friends can, and only people you've added are listed.")
            }

            Section {
                HStack {
                    TextField("Friend's code", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await add(typed) } }
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await add(typed) } }
                            .disabled(ArcsClient.friendCode(from: typed) == nil)
                    }
                }
                if DataScannerViewController.isSupported {
                    Button { scanning = true } label: { Label("Scan a Code", systemImage: "qrcode.viewfinder") }
                }
            } header: {
                Text("Add a Friend")
            } footer: {
                if let message { Text(verbatim: message) }
            }

            Section {
                if loaded && friends.isEmpty {
                    Text("No friends yet.").foregroundStyle(DT.Color.textSecondary)
                }
                ForEach(friends) { friend in
                    Label { Text(verbatim: friend.name) } icon: { Image(systemName: "person.crop.circle") }
                        .swipeActions {
                            Button(role: .destructive) { Task { await remove(friend) } } label: { Label("Remove", systemImage: "person.badge.minus") }
                        }
                }
            } header: {
                Text("Friends")
            } footer: {
                if !friends.isEmpty { Text("Swipe to remove someone. You stop being able to send each other scenes.") }
            }

            if code != nil {
                Section {
                    Button("New Code", role: .destructive) { confirmNewCode = true }
                } footer: {
                    Text("Your old code stops working. Friends you already have stay.")
                }
            }
        }
        .navigationTitle("Friends")
        .toolbar(.visible, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                PickCodeScanner(parse: ArcsClient.friendCode(from:)) { found in
                    scanning = false
                    Task { await add(found) }
                }
                .ignoresSafeArea()
                .navigationTitle("Scan a Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
            }
        }
        .confirmationDialog("Make a New Code?", isPresented: $confirmNewCode, titleVisibility: .visible) {
            Button("New Code", role: .destructive) { Task { await newCode() } }
        }
    }

    private func session() -> (ServerCredential, String)? {
        guard let credential = authManager.state.credential else { return nil }
        return (credential, authManager.authClient.authHeader(token: credential.accessToken))
    }

    private func load() async {
        guard let (credential, header) = session() else { return }
        if let result = try? await client.friends(credential: credential, authHeader: header) {
            code = result.code
            friends = result.friends
        }
        loaded = true
    }

    private func add(_ text: String) async {
        guard let parsed = ArcsClient.friendCode(from: text), let (credential, header) = session() else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            let friend = try await client.addFriend(code: parsed, credential: credential, authHeader: header)
            if !friends.contains(friend) { friends.append(friend) }
            typed = ""
            message = String(localized: "You and \(friend.name) are friends now.")
        } catch let error as PickTogetherError {
            message = error.message ?? String(localized: "That code isn't right.")
        } catch {
            message = String(localized: "Couldn't reach your server. Check your connection, then try again.")
        }
    }

    private func remove(_ friend: ArcPerson) async {
        guard let (credential, header) = session() else { return }
        try? await client.removeFriend(friend.id, credential: credential, authHeader: header)
        friends.removeAll { $0.id == friend.id }
    }

    private func newCode() async {
        guard let (credential, header) = session() else { return }
        if let fresh = try? await client.newFriendCode(credential: credential, authHeader: header) { code = fresh }
    }
}

extension ArcsDeepLink {
    static let pendingFriendKey = "arcfin.pendingArcsFriend"

    /// arcfin://arcs-friend/<code>, from a friend's QR code: Home asks before adding them.
    static func receiveFriend(_ url: URL) {
        guard let code = ArcsClient.friendCode(from: url.absoluteString) else { return }
        UserDefaults.standard.set(code, forKey: pendingFriendKey)
        NotificationCenter.default.post(name: .arcfinOpenArcs, object: nil)
    }
}

extension View {
    /// Asks whether to add the friend whose code was opened, and says how it went.
    func arcsFriendLink() -> some View {
        modifier(ArcsFriendLinkModifier())
    }
}

private struct ArcsFriendLinkModifier: ViewModifier {
    @Environment(AuthManager.self) private var authManager
    @State private var code: String?
    @State private var result: String?

    func body(content: Content) -> some View {
        content
            .onAppear { take() }
            .onReceive(NotificationCenter.default.publisher(for: .arcfinOpenArcs)) { _ in take() }
            .alert("Add a Friend in Arcs?", isPresented: Binding(get: { code != nil }, set: { if !$0 { code = nil } }), presenting: code) { code in
                Button("Add") { Task { await add(code) } }
                Button("Cancel", role: .cancel) {}
            } message: { code in
                Text("Add the person with the code \(code)? You'll be able to send each other scenes.")
            }
            .alert("Arcs Friends", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }), presenting: result) { _ in
                Button("OK") {}
            } message: { text in
                Text(verbatim: text)
            }
    }

    private func take() {
        guard let pending = UserDefaults.standard.string(forKey: ArcsDeepLink.pendingFriendKey) else { return }
        UserDefaults.standard.removeObject(forKey: ArcsDeepLink.pendingFriendKey)
        guard authManager.arcfinSyncStatus?.isOn("arcs") == true else { return }
        code = pending
    }

    private func add(_ code: String) async {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        do {
            let friend = try await ArcsClient().addFriend(code: code, credential: credential, authHeader: header)
            result = String(localized: "You and \(friend.name) are friends now.")
        } catch let error as PickTogetherError {
            result = error.message ?? String(localized: "That code isn't right.")
        } catch {
            result = String(localized: "Couldn't reach your server. Check your connection, then try again.")
        }
    }
}

/// Unwatched scenes friends sent, for the badge on the Arcs tab.
@MainActor @Observable
final class ArcsBadge {
    static let shared = ArcsBadge()
    var unseen = 0

    func refresh(authManager: AuthManager) async {
        guard authManager.arcfinSyncStatus?.isOn("arcs") == true, let credential = authManager.state.credential else {
            unseen = 0
            return
        }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let spoilerSafe = UserDefaults.standard.object(forKey: ArcsSettings.spoilerSafeKey) as? Bool ?? true
        if let availability = try? await ArcsClient().availability(spoilerSafe: spoilerSafe, credential: credential, authHeader: header) {
            unseen = availability.enabled ? availability.unseen : 0
        }
    }
}
