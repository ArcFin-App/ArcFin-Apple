// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

// MARK: - Apple TV: being set up

/// The Apple TV's side of setup from an iPhone or iPad (#481), while it's on the sign-in
/// pages. Nothing is contacted until the person at the TV allows it, so a device on the
/// network can't sign this Apple TV in to another server by itself.
@MainActor @Observable
final class AppleTVSetupHost {
    enum Phase: Equatable {
        case idle
        /// A phone asked; the person at the TV allows it or not.
        case asking(userName: String, serverName: String)
        case contacting
        /// Shown here and on the phone, which approves it once they match.
        case showingCode(String, userName: String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Quick Connect is off on the server the phone sent: its password page, instead.
    var passwordServer: URL?

    @ObservationIgnored private var listener: DeviceSetupListener?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var channel: DeviceSetupChannel?
    @ObservationIgnored private var answer: CheckedContinuation<Bool, Never>?

    func start(authManager: AuthManager) {
        guard listener == nil, let listener = try? DeviceSetupListener() else { return }
        self.listener = listener
        listenTask = Task { [weak self] in
            for await channel in listener.channels {
                guard let self else { return }
                if self.channel != nil {
                    channel.finish(with: .failed(.busy))
                    continue
                }
                Task { await self.serve(channel, authManager: authManager) }
            }
        }
    }

    func stop() {
        listenTask?.cancel()
        listener?.stop()
        listener = nil
        endSession()
    }

    func allow(_ allowed: Bool) {
        answer?.resume(returning: allowed)
        answer = nil
    }

    /// The person at the TV stops it; the TV stays ready for another try.
    func cancelSession() {
        endSession(sending: .failed(.declined))
    }

    func dismissFailure() {
        if case .failed = phase { phase = .idle }
    }

    private enum Start {
        case started(url: URL, code: String, secret: String)
        case quickConnectOff(URL)
        case unreachable
    }

    /// The first address that answers, in the order the phone sent them.
    private func startQuickConnect(_ addresses: [String], authManager: AuthManager) async -> Start {
        let urls = addresses.compactMap(URL.init(string:)).filter { $0.scheme == "http" || $0.scheme == "https" }
        for url in urls {
            do {
                let (code, secret) = try await authManager.authClient.initiateQuickConnect(baseURL: url)
                return .started(url: url, code: code.filter(\.isNumber), secret: secret)
            } catch JellyfinAuthError.quickConnectDisabled {
                return .quickConnectOff(url)
            } catch {
                continue
            }
        }
        return .unreachable
    }

    private func serve(_ channel: DeviceSetupChannel, authManager: AuthManager) async {
        self.channel = channel
        var messages = channel.messages.makeAsyncIterator()
        guard case .hello(let profiles)? = await messages.next(), let first = profiles.first else {
            endSession()
            return
        }
        let names = ListFormatter.localizedString(byJoining: profiles.map(\.userName))
        phase = .asking(userName: names, serverName: first.serverName)
        let allowed = await withCheckedContinuation { answer = $0 }
        guard allowed else {
            endSession(sending: .failed(.declined))
            return
        }
        channel.send(.allowed)
        phase = .contacting

        // Each profile gets its own Quick Connect code on its own server. The first is shown
        // here for the person to check against the phone; the rest follow on the same
        // connection once that one's confirmed.
        var pending: [(index: Int, url: URL, secret: String)] = []
        for (index, profile) in profiles.enumerated() {
            switch await startQuickConnect(profile.servers, authManager: authManager) {
            case .started(let url, let code, let secret):
                pending.append((index, url, secret))
                channel.send(.code(profile: index, code: code))
                if pending.count == 1 { phase = .showingCode(code, userName: profile.userName) }
            case .quickConnectOff(let url):
                guard index > 0 else {
                    endSession(sending: .failed(.quickConnectOff))
                    passwordServer = url
                    return
                }
                channel.send(.skipped(profile: index, .quickConnectOff))
            case .unreachable:
                guard index > 0 else {
                    endSession(sending: .failed(.unreachable))
                    phase = .failed(String(localized: "This Apple TV couldn't reach \(first.serverName). Check it's on the same network as your server. If your server needs custom headers, add them here under Custom Headers first."))
                    return
                }
                channel.send(.skipped(profile: index, .unreachable))
            }
        }

        // The phone only says it approved; the server is what's checked. A phone that hangs
        // up early gets a short grace, so approvals it already made still sign in.
        var closedAt: Date?
        let watcher = Task {
            for await _ in channel.messages {}
            closedAt = .now
        }
        defer { watcher.cancel() }
        var signedIn: [Int: ServerCredential] = [:]
        for _ in 0..<300 where signedIn.count < pending.count {
            try? await Task.sleep(for: .seconds(2))
            guard channel === self.channel else { return }
            if let closedAt, Date.now.timeIntervalSince(closedAt) > 20 { break }
            for item in pending where signedIn[item.index] == nil {
                let approved = (try? await authManager.authClient.pollQuickConnect(baseURL: item.url, secret: item.secret)) ?? false
                guard approved else { continue }
                if let credential = try? await authManager.authClient.authenticateWithQuickConnect(baseURL: item.url, secret: item.secret) {
                    signedIn[item.index] = credential
                }
            }
        }
        guard let primary = signedIn.keys.min().flatMap({ signedIn[$0] }) else {
            endSession(sending: .failed(.expired))
            return
        }
        endSession(sending: .done(signedIn: signedIn.count))
        // The others first, then the first chosen, so that's the one in use.
        for (_, credential) in signedIn.sorted(by: { $0.key > $1.key }) where credential.id != primary.id {
            authManager.addProfile(credential)
        }
        authManager.save(primary)
    }

    private func giveUp() {
        guard case .showingCode = phase else { return }
        endSession()
    }

    /// `sending` goes out before the connection closes.
    private func endSession(sending last: DeviceSetup.Message? = nil) {
        answer?.resume(returning: false)
        answer = nil
        if let last { channel?.finish(with: last) } else { channel?.close() }
        channel = nil
        if case .failed = phase { return }
        phase = .idle
    }
}

/// The Apple TV's setup screen, over the sign-in pages while a phone is setting it up.
struct AppleTVSetupHostView: View {
    let host: AppleTVSetupHost

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 32) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 72))
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityHidden(true)
                content
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 1000)
            .padding(60)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch host.phase {
        case .idle:
            EmptyView()
        case .asking(let userName, let serverName):
            title("Set Up This Apple TV?")
            message(Text("\(userName) wants to sign this Apple TV in to \(serverName) from an iPhone or iPad."))
            HStack(spacing: 32) {
                Button("Allow") { host.allow(true) }
                Button("Cancel", role: .cancel) { host.allow(false) }
            }
        case .contacting:
            title("Contacting Your Server")
            ProgressView()
        case .showingCode(let code, let userName):
            title("Check the Code")
            message(Text("Make sure \(userName)'s iPhone or iPad shows the same code, then confirm it there."))
            Text(code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .tracking(10)
                .foregroundStyle(DT.Color.textPrimary)
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
            Button("Cancel", role: .cancel) { host.cancelSession() }
        case .failed(let reason):
            title("Couldn't Set Up This Apple TV")
            message(Text(reason))
            Button("OK") { host.dismissFailure() }
        }
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.title.bold())
            .foregroundStyle(DT.Color.textPrimary)
    }

    private func message(_ text: Text) -> some View {
        text
            .font(.callout)
            .foregroundStyle(DT.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - iPhone / iPad: setting one up

/// The phone's side (#481): notices a signed-out Apple TV on the network and offers to set it
/// up with one or more of this device's profiles, by approving the Quick Connect codes it
/// shows.
@MainActor @Observable
final class AppleTVSetupGuide {
    enum Phase: Equatable {
        case idle
        /// Settings › Set Up Nearby Apple TV: looking, with nothing found yet.
        case searching
        case offering(DeviceSetupBrowser.AppleTV)
        /// Waiting for the person at the Apple TV to press Allow.
        case waitingForTV(String)
        case confirming(code: String, name: String)
        case approving
        case done(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The profiles to sign the Apple TV in with, the active one first.
    var selected: Set<UUID> = []
    /// Profiles with a PIN, which can only be added after switching to them.
    private(set) var locked: Set<UUID> = []

    @ObservationIgnored private var browser: DeviceSetupBrowser?
    @ObservationIgnored private var browseTask: Task<Void, Never>?
    @ObservationIgnored private var channel: DeviceSetupChannel?
    @ObservationIgnored private var declined: Set<String> = []
    @ObservationIgnored private var sending: [ServerCredential] = []
    @ObservationIgnored private var confirmed = false
    @ObservationIgnored private var waitingCodes: [Int: String] = [:]
    @ObservationIgnored private var skipped = 0

    @ObservationIgnored private var found: [DeviceSetupBrowser.AppleTV] = []
    @ObservationIgnored private var searchTimeout: Task<Void, Never>?

    /// Keeps looking while the app is in front. The search stops when the Local Network
    /// permission is first asked for, or the network changes, so it starts again after a
    /// moment rather than staying stopped.
    func start(authManager: AuthManager) {
        guard browseTask == nil else { return }
        browseTask = Task { [weak self] in
            while !Task.isCancelled {
                let browser = DeviceSetupBrowser()
                self?.browser = browser
                for await results in browser.results {
                    guard let self else { return }
                    self.found = results
                    await self.offer(authManager: authManager)
                }
                browser.stop()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// The phone leaves the foreground, plays something or locks.
    func stop() {
        browseTask?.cancel()
        browseTask = nil
        browser?.stop()
        browser = nil
        found = []
        if case .offering = phase { phase = .idle }
        if phase == .searching { phase = .idle }
    }

    /// Settings › Set Up Nearby Apple TV: offers one even after Not Now, and says so when
    /// there's none.
    func findNearby(authManager: AuthManager) {
        declined = []
        phase = .searching
        start(authManager: authManager)
        Task { await offer(authManager: authManager) }
        searchTimeout?.cancel()
        searchTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, self.phase == .searching else { return }
            self.phase = .failed(String(localized: "No Apple TV to set up was found. Open Arcfin on the Apple TV, go to its sign-in page, and make sure both are on the same network."))
        }
    }

    private func offer(authManager: AuthManager) async {
        guard phase == .idle || phase == .searching,
              let tv = found.first(where: { !declined.contains($0.name) }) else { return }
        await prepareChoices(authManager: authManager)
        guard phase == .idle || phase == .searching else { return }
        searchTimeout?.cancel()
        phase = .offering(tv)
    }

    private func prepareChoices(authManager: AuthManager) async {
        var withPIN: Set<UUID> = []
        let active = authManager.state.credential?.id
        for profile in authManager.profiles where profile.id != active {
            if await authManager.pin(for: profile.id) != nil { withPIN.insert(profile.id) }
        }
        locked = withPIN
        selected = active.map { [$0] } ?? []
    }

    func toggle(_ id: UUID) {
        guard !locked.contains(id) else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    func notNow() {
        if case .offering(let tv) = phase { declined.insert(tv.name) }
        cancel()
    }

    func cancel() {
        channel?.finish(with: .failed(.declined))
        channel = nil
        phase = .idle
    }

    func setUp(_ tv: DeviceSetupBrowser.AppleTV, authManager: AuthManager) {
        let active = authManager.state.credential?.id
        // The active profile first: it's the one the Apple TV ends up using.
        sending = authManager.profiles
            .filter { selected.contains($0.id) && !locked.contains($0.id) }
            .sorted { ($0.id == active ? 0 : 1) < ($1.id == active ? 0 : 1) }
        guard !sending.isEmpty else { return }
        declined.insert(tv.name)
        confirmed = false
        waitingCodes = [:]
        skipped = 0
        let channel = DeviceSetupChannel(endpoint: tv.endpoint)
        self.channel = channel
        phase = .waitingForTV(tv.name)
        channel.send(.hello(profiles: sending.map { profile in
            DeviceSetup.Profile(userName: profile.displayName,
                                serverName: profile.baseURL.host() ?? profile.baseURL.absoluteString,
                                servers: Self.addresses(for: profile).map(\.absoluteString))
        }))
        Task {
            for await message in channel.messages {
                switch message {
                case .code(let index, let code):
                    if index == 0 {
                        phase = .confirming(code: code, name: tv.name)
                    } else if confirmed {
                        approve(index: index, code: code, authManager: authManager)
                    } else {
                        waitingCodes[index] = code
                    }
                case .skipped:
                    skipped += 1
                case .done(let count):
                    phase = .done(count == 1
                        ? String(localized: "The Apple TV is signed in as \(sending.first?.displayName ?? "").")
                        : String(localized: "The Apple TV is signed in with \(count) profiles."))
                    channel.close()
                case .failed(let failure):
                    phase = .failed(Self.explanation(failure))
                    channel.close()
                default:
                    break
                }
            }
            if self.channel === channel { self.channel = nil }
            switch phase {
            case .waitingForTV, .confirming:
                phase = .failed(String(localized: "The Apple TV stopped answering. Try again from its sign-in page."))
            case .approving:
                // Approved, but the Apple TV hung up before saying it had signed in.
                phase = .failed(String(localized: "The Apple TV stopped answering before it confirmed. Check whether it's signed in."))
            default:
                break
            }
        }
    }

    /// The first code matches what the Apple TV shows: approve it, and the others it sends.
    func confirm(code: String, authManager: AuthManager) {
        guard channel != nil else { return }
        confirmed = true
        phase = .approving
        approve(index: 0, code: code, authManager: authManager)
        for (index, code) in waitingCodes { approve(index: index, code: code, authManager: authManager) }
        waitingCodes = [:]
    }

    private func approve(index: Int, code: String, authManager: AuthManager) {
        guard sending.indices.contains(index), let channel else { return }
        let profile = sending[index]
        Task {
            let header = authManager.authClient.authHeader(token: profile.accessToken)
            let approved = (try? await authManager.authClient.authorizeQuickConnect(
                baseURL: profile.baseURL, authHeader: header, code: code)) ?? false
            if approved {
                channel.send(.approved(profile: index))
            } else if index == 0 {
                phase = .failed(String(localized: "The code has expired or was already used. Start again from the Apple TV's sign-in page."))
                channel.finish(with: .failed(.expired))
            }
        }
    }

    func dismiss() {
        channel?.close()
        channel = nil
        phase = .idle
    }

    /// Home first, then away, then the address in use now: the Apple TV is usually at home,
    /// and takes the first one that answers.
    private static func addresses(for credential: ServerCredential) -> [URL] {
        let defaults = UserDefaults.standard
        let id = credential.id.uuidString
        let stored = [defaults.string(forKey: "serverLocalURL.\(id)"), defaults.string(forKey: "serverRemoteURL.\(id)")]
            .compactMap { $0.flatMap(URL.init(string:)) }
        var seen = Set<String>()
        return (stored + [credential.baseURL]).filter { seen.insert($0.absoluteString).inserted }
    }

    private static func explanation(_ failure: DeviceSetup.Failure) -> String {
        switch failure {
        case .declined: String(localized: "Setup was cancelled on the Apple TV.")
        case .unreachable: String(localized: "The Apple TV couldn't reach your server. It needs to be on a network that can reach it.")
        case .quickConnectOff: String(localized: "Quick Connect is off on your server, so the Apple TV is showing its password page instead.")
        case .busy: String(localized: "Another device is already setting up this Apple TV.")
        case .expired: String(localized: "The code ran out before it was confirmed. Start again from the Apple TV's sign-in page.")
        }
    }
}

/// The card on iPhone and iPad, like the system's own setup cards.
struct AppleTVSetupCard: View {
    let guide: AppleTVSetupGuide
    let authManager: AuthManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "appletv.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(DT.Color.accent)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
                content
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch guide.phase {
        case .idle, .approving:
            ProgressView()
        case .searching:
            heading("Looking for Apple TVs")
            note(Text("Open Arcfin on the Apple TV and go to its sign-in page. It needs to be on the same network as this device."))
            ProgressView()
            Button("Cancel") { guide.dismiss() }
                .foregroundStyle(DT.Color.textSecondary)
        case .offering(let tv):
            heading("Set Up Apple TV?")
            Text(verbatim: tv.name)
                .font(.headline)
                .foregroundStyle(DT.Color.textSecondary)
            note(Text("Sign this Apple TV in with your profile from here."))
            if authManager.profiles.count > 1 { profilePicker }
            primary("Set Up") { guide.setUp(tv, authManager: authManager) }
                .disabled(guide.selected.isEmpty)
            Button("Not Now") { guide.notNow() }
                .foregroundStyle(DT.Color.textSecondary)
        case .waitingForTV(let name):
            heading("Allow on the Apple TV")
            note(Text("Press Allow on \(name) with its remote."))
            ProgressView()
            Button("Cancel") { guide.cancel() }
                .foregroundStyle(DT.Color.textSecondary)
        case .confirming(let code, let name):
            heading("Does the Code Match?")
            note(Text("Check that \(name) shows this code."))
            Text(code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .tracking(6)
                .foregroundStyle(DT.Color.textPrimary)
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
            primary("It Matches") { guide.confirm(code: code, authManager: authManager) }
            Button("Cancel") { guide.cancel() }
                .foregroundStyle(DT.Color.textSecondary)
        case .done(let text):
            heading("Apple TV Signed In")
            note(Text(text))
            primary("Done") { guide.dismiss() }
        case .failed(let text):
            heading("Couldn't Set Up Apple TV")
            note(Text(text))
            primary("OK") { guide.dismiss() }
        }
    }

    /// Which of this device's profiles to sign in; one with a PIN needs switching to first.
    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sign In As")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .padding(.bottom, 8)
            ForEach(authManager.profiles) { profile in
                let isLocked = guide.locked.contains(profile.id)
                Button { guide.toggle(profile.id) } label: {
                    HStack(spacing: 12) {
                        ProfileAvatar(profile: profile, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: profile.displayName)
                                .foregroundStyle(DT.Color.textPrimary)
                            if isLocked {
                                Text("Has a PIN. Switch to this profile to add it.")
                                    .font(.caption)
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: guide.selected.contains(profile.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(guide.selected.contains(profile.id) ? DT.Color.accent : DT.Color.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
                .opacity(isLocked ? 0.5 : 1)
                .accessibilityAddTraits(guide.selected.contains(profile.id) ? .isSelected : [])
            }
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func heading(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.title2.bold())
            .foregroundStyle(DT.Color.textPrimary)
    }

    private func note(_ text: Text) -> some View {
        text
            .font(.callout)
            .foregroundStyle(DT.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(DT.Color.accent)
        .foregroundStyle(DT.Color.onAccent)
    }
}
