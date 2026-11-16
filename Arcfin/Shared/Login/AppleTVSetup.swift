// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

// MARK: - Apple TV: being set up

/// The Apple TV's side of setup from an iPhone or iPad (#481), while it's on the sign-in
/// pages. The connection agrees fresh keys and shows a code made from them on both screens
/// (see DeviceSetup). Nothing is contacted until the person here presses Allow and the
/// person at the phone confirms the same code, so nobody else on the network can sign this
/// Apple TV in, or listen in.
@MainActor @Observable
final class AppleTVSetupHost {
    enum Phase: Equatable {
        case idle
        /// A phone connected; the person here checks the code and allows it or not.
        case confirming(code: String)
        /// Allowed here; waiting for the phone to confirm the same code.
        case waitingForPhone(code: String)
        case signingIn(names: String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Quick Connect is off on the server the phone sent: its password page, instead.
    var passwordServer: URL?
    /// Goes up each time a phone signs this Apple TV in, so Add Profile can close.
    private(set) var completedSetups = 0

    @ObservationIgnored private var listener: DeviceSetupListener?
    @ObservationIgnored private var listenTask: Task<Void, Never>?
    @ObservationIgnored private var session: DeviceSetupSession?
    @ObservationIgnored private var answer: CheckedContinuation<Bool, Never>?

    func start(authManager: AuthManager) {
        guard listener == nil, let listener = try? DeviceSetupListener() else { return }
        self.listener = listener
        listenTask = Task { [weak self] in
            for await session in listener.sessions {
                guard let self else { return }
                if self.session != nil {
                    session.finish(with: .failed(.busy))
                    continue
                }
                Task { await self.serve(session, authManager: authManager) }
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

    /// The person here stops it; the TV stays ready for another try.
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

    private func serve(_ session: DeviceSetupSession, authManager: AuthManager) async {
        self.session = session
        phase = .confirming(code: session.code)
        let allowed = await withCheckedContinuation { answer = $0 }
        guard allowed else {
            endSession(sending: .failed(.declined))
            return
        }
        session.send(.allowed(signedIn: authManager.profiles.map(\.userID)))
        phase = .waitingForPhone(code: session.code)

        // The phone sends its profiles only once its person has confirmed the same code.
        var messages = session.messages.makeAsyncIterator()
        guard case .hello(let profiles)? = await messages.next(), let first = profiles.first,
              self.session === session else {
            endSession()
            return
        }
        phase = .signingIn(names: ListFormatter.localizedString(byJoining: profiles.map(\.userName)))

        // Each profile gets its own Quick Connect code on its own server, which the phone
        // approves with that profile's sign-in. The connection is already checked, so no
        // more codes need comparing.
        var pending: [(index: Int, url: URL, secret: String)] = []
        for (index, profile) in profiles.enumerated() {
            switch await startQuickConnect(profile.servers, authManager: authManager) {
            case .started(let url, let code, let secret):
                pending.append((index, url, secret))
                session.send(.code(profile: index, code: code))
            case .quickConnectOff(let url):
                guard index > 0 else {
                    endSession(sending: .failed(.quickConnectOff))
                    passwordServer = url
                    return
                }
                session.send(.skipped(profile: index, .quickConnectOff))
            case .unreachable:
                guard index > 0 else {
                    endSession(sending: .failed(.unreachable))
                    phase = .failed(String(localized: "This Apple TV couldn't reach \(first.serverName). Check it's on the same network as your server. If your server needs custom headers, add them here under Custom Headers first."))
                    return
                }
                session.send(.skipped(profile: index, .unreachable))
            }
        }

        // The phone only says it approved; the server is what's checked. A phone that hangs
        // up early gets a short grace, so approvals it already made still sign in.
        var closedAt: Date?
        let watcher = Task {
            for await _ in session.messages {}
            closedAt = .now
        }
        defer { watcher.cancel() }
        var signedIn: [Int: ServerCredential] = [:]
        for _ in 0..<300 where signedIn.count < pending.count {
            try? await Task.sleep(for: .seconds(2))
            guard self.session === session else { return }
            if let closedAt, Date.now.timeIntervalSince(closedAt) > 20 { break }
            for item in pending where signedIn[item.index] == nil {
                let approved = (try? await authManager.authClient.pollQuickConnect(baseURL: item.url, secret: item.secret)) ?? false
                guard approved else { continue }
                if let credential = try? await authManager.authClient.authenticateWithQuickConnect(baseURL: item.url, secret: item.secret) {
                    signedIn[item.index] = credential
                }
            }
        }
        guard let primaryIndex = signedIn.keys.min(), let primary = signedIn[primaryIndex] else {
            endSession(sending: .failed(.expired))
            return
        }
        endSession(sending: .done(signedIn: signedIn.count))
        // The others first, then the first chosen, so that's the one in use.
        for (_, credential) in signedIn.sorted(by: { $0.key > $1.key }) where credential.userID != primary.userID || credential.baseURL != primary.baseURL {
            authManager.addProfile(credential)
        }
        authManager.save(primary)
        Self.keepTMDBKeys(profiles: profiles, signedIn: signedIn, authManager: authManager)
        completedSetups += 1
    }

    /// Each profile's TMDB key, under the id the profile got here, and the active one's in
    /// the slot TMDB reads.
    private static func keepTMDBKeys(profiles: [DeviceSetup.Profile], signedIn: [Int: ServerCredential],
                                     authManager: AuthManager) {
        let active = authManager.state.credential?.id
        for (index, credential) in signedIn {
            guard let key = profiles[index].tmdbKey, !key.isEmpty else { continue }
            let id = authManager.profiles.first { $0.userID == credential.userID && $0.baseURL == credential.baseURL }?.id ?? credential.id
            try? TMDBCredential.save(key, profile: id)
            if id == active { try? TMDBCredential.save(key) }
        }
    }

    /// `sending` goes out before the connection closes.
    private func endSession(sending last: DeviceSetup.Message? = nil) {
        answer?.resume(returning: false)
        answer = nil
        if let last { session?.finish(with: last) } else { session?.close() }
        session = nil
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
        case .confirming(let code):
            title("Set Up This Apple TV?")
            message(Text("An iPhone or iPad on this network wants to set up this Apple TV. Allow it only if it shows this code."))
            codeText(code)
            HStack(spacing: 32) {
                Button("Allow") { host.allow(true) }
                Button("Cancel", role: .cancel) { host.allow(false) }
            }
        case .waitingForPhone(let code):
            title("Confirm on Your iPhone or iPad")
            message(Text("Check that it shows the same code, then confirm it there."))
            codeText(code)
            Button("Cancel", role: .cancel) { host.cancelSession() }
        case .signingIn(let names):
            title("Signing In")
            message(Text("Signing in \(names)."))
            ProgressView()
        case .failed(let reason):
            title("Couldn't Set Up This Apple TV")
            message(Text(reason))
            Button("OK") { host.dismissFailure() }
        }
    }

    private func codeText(_ code: String) -> some View {
        Text(code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code)
            .font(.system(size: 96, weight: .bold, design: .rounded))
            .monospacedDigit()
            .tracking(10)
            .foregroundStyle(DT.Color.textPrimary)
            .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
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
/// up with one or more of this device's profiles. Once both people have checked the code,
/// it sends the profiles over the sealed connection and approves the Quick Connect code the
/// Apple TV starts for each.
@MainActor @Observable
final class AppleTVSetupGuide {
    enum Phase: Equatable {
        case idle
        /// Settings › Set Up Nearby Apple TV: looking, with nothing found yet.
        case searching
        case offering(DeviceSetupBrowser.AppleTV)
        case connecting(String)
        /// Both screens show this; the person confirms it matches.
        case confirming(code: String, name: String)
        /// Confirmed here; waiting for the person at the Apple TV to press Allow.
        case waitingForTV(String)
        /// Both confirmed: which profiles to sign in, leaving out those already on the TV.
        case choosing(String)
        case approving
        case done(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The profiles to sign the Apple TV in with, the active one first.
    var selected: Set<UUID> = []
    /// Profiles with a PIN, which can only be added after switching to them.
    private(set) var locked: Set<UUID> = []

    /// How long it looks by itself each time the app comes to the front. Settings › Set Up
    /// Nearby Apple TV looks again whenever it's asked.
    private static let lookingWindow: Duration = .seconds(120)

    @ObservationIgnored private var browser: DeviceSetupBrowser?
    @ObservationIgnored private var browseTask: Task<Void, Never>?
    @ObservationIgnored private var session: DeviceSetupSession?
    @ObservationIgnored private var declined: Set<String> = []
    @ObservationIgnored private var sending: [ServerCredential] = []
    /// Set once the Apple TV allowed it: the user ids it already has.
    private(set) var onTV: Set<String>?
    @ObservationIgnored private var phoneConfirmed = false
    @ObservationIgnored private var found: [DeviceSetupBrowser.AppleTV] = []
    @ObservationIgnored private var searchTimeout: Task<Void, Never>?

    /// Looks for a while after the app comes to the front, then stops to save battery. The
    /// search also stops when the Local Network permission is first asked for, so it starts
    /// again after a moment.
    func start(authManager: AuthManager) {
        guard browseTask == nil else { return }
        browseTask = Task { [weak self] in
            let deadline = ContinuousClock.now + Self.lookingWindow
            while !Task.isCancelled, ContinuousClock.now < deadline {
                let browser = DeviceSetupBrowser()
                self?.browser = browser
                let stopper = Task {
                    try? await Task.sleep(until: deadline)
                    browser.stop()
                }
                for await results in browser.results {
                    guard let self else { return }
                    self.found = results
                    await self.offer(authManager: authManager)
                }
                stopper.cancel()
                browser.stop()
                try? await Task.sleep(for: .seconds(3))
            }
            self?.browser = nil
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

    /// Settings › Set Up Nearby Apple TV: looks again, offers one even after Not Now, and
    /// says so when there's none.
    func findNearby(authManager: AuthManager) {
        declined = []
        phase = .searching
        stop()
        phase = .searching
        start(authManager: authManager)
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
        let free = authManager.profiles.filter { !(onTV?.contains($0.userID) ?? false) && !withPIN.contains($0.id) }
        selected = Set([free.first { $0.id == active } ?? free.first].compactMap { $0?.id })
    }

    func toggle(_ id: UUID) {
        guard !locked.contains(id) else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Hides this Apple TV until the app is next opened, or Settings looks again.
    func notNow() {
        if case .offering(let tv) = phase { declined.insert(tv.name) }
        cancel()
    }

    func cancel() {
        session?.finish(with: .failed(.declined))
        session = nil
        phase = .idle
    }

    func setUp(_ tv: DeviceSetupBrowser.AppleTV, authManager: AuthManager) {
        sending = []
        onTV = nil
        phoneConfirmed = false
        phase = .connecting(tv.name)
        Task {
            guard let session = try? await withTimeout(seconds: 10, { try await DeviceSetupSession.connect(to: tv.endpoint) }) else {
                phase = .failed(String(localized: "The Apple TV stopped answering. Try again from its sign-in page."))
                return
            }
            guard case .connecting = phase else {
                session.finish(with: .failed(.declined))
                return
            }
            self.session = session
            phase = .confirming(code: session.code, name: tv.name)
            for await message in session.messages {
                switch message {
                case .allowed(let signedIn):
                    onTV = Set(signedIn)
                    await prepareChoices(authManager: authManager)
                    if phoneConfirmed, case .waitingForTV(let name) = phase { phase = .choosing(name) }
                case .code(let index, let code):
                    approve(index: index, code: code, authManager: authManager)
                case .done(let count):
                    phase = .done(count == 1
                        ? String(localized: "The Apple TV is signed in as \(sending.first?.displayName ?? "").")
                        : String(localized: "The Apple TV is signed in with \(count) profiles."))
                case .failed(let failure):
                    phase = .failed(Self.explanation(failure))
                default:
                    break
                }
            }
            if self.session === session { self.session = nil }
            switch phase {
            case .confirming, .waitingForTV, .choosing:
                phase = .failed(String(localized: "The Apple TV stopped answering. Try again from its sign-in page."))
            case .approving:
                phase = .failed(String(localized: "The Apple TV stopped answering before it confirmed. Check whether it's signed in."))
            default:
                break
            }
        }
    }

    /// The person saw the same code on both screens: the connection is the Apple TV's.
    /// Profiles are picked once the Apple TV has allowed it too.
    func confirm() {
        guard case .confirming(_, let name) = phase else { return }
        phoneConfirmed = true
        phase = onTV == nil ? .waitingForTV(name) : .choosing(name)
    }

    /// The profiles that can still go to the Apple TV.
    func available(_ authManager: AuthManager) -> [ServerCredential] {
        authManager.profiles.filter { !(onTV?.contains($0.userID) ?? false) }
    }

    /// Sends the picked profiles, sealed, each with its TMDB key, the active one first.
    func signIn(authManager: AuthManager) {
        guard let session, case .choosing = phase else { return }
        let activeID = authManager.state.credential?.id
        sending = available(authManager)
            .filter { selected.contains($0.id) && !locked.contains($0.id) }
            .sorted { ($0.id == activeID ? 0 : 1) < ($1.id == activeID ? 0 : 1) }
        guard !sending.isEmpty else { return }
        session.send(.hello(profiles: sending.map { profile in
            let key = profile.id == activeID ? TMDBCredential.load() : TMDBCredential.load(profile: profile.id)
            return DeviceSetup.Profile(userName: profile.displayName,
                                       serverName: profile.baseURL.host() ?? profile.baseURL.absoluteString,
                                       servers: Self.addresses(for: profile).map(\.absoluteString),
                                       tmdbKey: key.flatMap { $0.isEmpty ? nil : $0 })
        }))
        phase = .approving
    }

    private func approve(index: Int, code: String, authManager: AuthManager) {
        guard sending.indices.contains(index), let session else { return }
        let profile = sending[index]
        Task {
            let header = authManager.authClient.authHeader(token: profile.accessToken)
            let approved = (try? await authManager.authClient.authorizeQuickConnect(
                baseURL: profile.baseURL, authHeader: header, code: code)) ?? false
            if approved {
                session.send(.approved(profile: index))
            } else if index == 0 {
                phase = .failed(String(localized: "The code has expired or was already used. Start again from the Apple TV's sign-in page."))
                session.finish(with: .failed(.expired))
            }
        }
    }

    func dismiss() {
        session?.close()
        session = nil
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

/// Runs `work`, giving up after `seconds`.
private func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw CancellationError() }
        return first
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
        case .idle:
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
            primary("Set Up") { guide.setUp(tv, authManager: authManager) }
            Button("Not Now") { guide.notNow() }
                .foregroundStyle(DT.Color.textSecondary)
        case .connecting(let name):
            heading("Connecting to \(name)")
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
            primary("It Matches") { guide.confirm() }
            Button("Cancel") { guide.cancel() }
                .foregroundStyle(DT.Color.textSecondary)
        case .waitingForTV(let name):
            heading("Allow on the Apple TV")
            note(Text("Press Allow on \(name) with its remote."))
            ProgressView()
            Button("Cancel") { guide.cancel() }
                .foregroundStyle(DT.Color.textSecondary)
        case .choosing:
            if guide.available(authManager).isEmpty {
                heading("Already Signed In")
                note(Text("All your profiles are already on this Apple TV."))
                primary("Done") { guide.cancel() }
            } else {
                heading("Sign In As")
                profilePicker
                primary("Sign In") { guide.signIn(authManager: authManager) }
                    .disabled(guide.selected.isEmpty)
                Button("Cancel") { guide.cancel() }
                    .foregroundStyle(DT.Color.textSecondary)
            }
        case .approving:
            heading("Signing In the Apple TV")
            ProgressView()
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

    /// Which of this device's profiles to sign in. One already on the Apple TV isn't offered;
    /// one with a PIN needs switching to first.
    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(authManager.profiles) { profile in
                let onTV = guide.onTV?.contains(profile.userID) ?? false
                let isLocked = onTV || guide.locked.contains(profile.id)
                Button { guide.toggle(profile.id) } label: {
                    HStack(spacing: 12) {
                        ProfileAvatar(profile: profile, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: profile.displayName)
                                .foregroundStyle(DT.Color.textPrimary)
                            if onTV {
                                Text("Already on this Apple TV.")
                                    .font(.caption)
                                    .foregroundStyle(DT.Color.textSecondary)
                            } else if isLocked {
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
