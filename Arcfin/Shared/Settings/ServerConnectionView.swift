// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine

/// Server & Connection: how fast this connection to the server is, what the account is
/// allowed, what plays here as it is, and anything that looks wrong.
@MainActor @Observable
final class ServerConnectionModel {
    enum Reach: Equatable {
        case checking, reachable(Double), unreachable, notSet
    }

    private(set) var bitsPerSecond: Int?
    private(set) var responseTime: Double?
    private(set) var isTesting = false
    private(set) var testFailed = false
    private(set) var policy: UserPolicy?
    private(set) var info: JellyfinPublicServerInfo?
    private(set) var local = Reach.notSet
    private(set) var remote = Reach.notSet

    private let client = JellyfinMediaClient()

    func load(_ auth: AuthManager, localURL: URL?, remoteURL: URL?) async {
        guard let credential = auth.state.credential else { return }
        let header = auth.authClient.authHeader(token: credential.accessToken)
        async let profile = try? client.getUserProfile(credential: credential, authHeader: header)
        async let publicInfo = try? client.getPublicInfo(baseURL: credential.baseURL)
        async let localReach = reach(localURL)
        async let remoteReach = reach(remoteURL)
        policy = await profile?.policy
        info = await publicInfo
        local = await localReach
        remote = await remoteReach
    }

    private func reach(_ url: URL?) async -> Reach {
        guard let url else { return .notSet }
        return await client.responseTime(baseURL: url).map(Reach.reachable) ?? .unreachable
    }

    func runSpeedTest(_ auth: AuthManager) async {
        guard let credential = auth.state.credential, !isTesting else { return }
        isTesting = true
        testFailed = false
        let header = auth.authClient.authHeader(token: credential.accessToken)
        responseTime = await client.responseTime(baseURL: credential.baseURL)
        bitsPerSecond = await client.testBitrate(credential: credential, authHeader: header,
                                                 sizeBytes: 30_000_000, duration: .seconds(6))
        testFailed = bitsPerSecond == nil
        isTesting = false
    }

    /// Anything worth knowing, worst first. Empty when it all looks fine.
    var problems: [String] {
        var found: [String] = []
        if let bitsPerSecond, bitsPerSecond < 4_000_000 {
            found.append(String(localized: "This connection is slow for HD video. Expect the server to convert video to a lower quality."))
        }
        if remote == .unreachable {
            found.append(String(localized: "The remote address doesn't answer, so the server can't be reached away from home."))
        }
        if local == .unreachable {
            found.append(String(localized: "The local address doesn't answer from here."))
        }
        if let limit = policy?.remoteClientBitrateLimit, limit > 0, let bitsPerSecond, bitsPerSecond > limit {
            found.append(String(localized: "Your admin limits streaming away from home to \(Self.rate(limit)), below what this connection can do."))
        }
        if policy?.forceRemoteSourceTranscoding == true {
            found.append(String(localized: "Your admin has the server convert everything you play away from home."))
        }
        if let version = info?.version, version.compare("10.9", options: .numeric) == .orderedAscending {
            found.append(String(localized: "Jellyfin \(version) is older than 10.9: lyrics, Sound Check and trickplay need 10.9 or later."))
        }
        return found
    }

    static func rate(_ bitsPerSecond: Int) -> String {
        let megabits = Double(bitsPerSecond) / 1_000_000
        return megabits >= 10
            ? String(localized: "\(Int(megabits.rounded())) Mbps")
            : String(localized: "\(megabits.formatted(.number.precision(.fractionLength(1)))) Mbps")
    }

    /// What the player would start a video at on this connection.
    var videoQuality: String? {
        guard let bitsPerSecond else { return nil }
        guard let cap = AutoQuality.startingCap(measuredBps: bitsPerSecond) else { return String(localized: "Original quality") }
        let rate = Self.rate(cap.maxBitrate ?? bitsPerSecond)
        guard let width = cap.maxWidth else { return String(localized: "Up to \(rate)") }
        return String(localized: "Up to \(rate), \(Self.resolution(width))")
    }

    private static func resolution(_ width: Int) -> String {
        switch width {
        case 1920...: "1080p"
        case 1280...: "720p"
        case 960...: "540p"
        default: "480p"
        }
    }

    /// What music would stream at, leaving the same room the player leaves for video.
    var musicQuality: String? {
        guard let bitsPerSecond else { return nil }
        let safe = Double(bitsPerSecond) * 0.75
        if safe >= 2_000_000 { return String(localized: "Lossless") }
        let kilobits = [320, 256, 192, 128, 96].first { Double($0 * 1000) <= safe } ?? 64
        return String(localized: "\(kilobits) kbps")
    }
}

struct ServerConnectionView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = ServerConnectionModel()
    var localURL: String = ""
    var remoteURL: String = ""
    /// Local, Remote or Custom; the Mac has only the one address.
    var currentlyUsing: String?

    var body: some View {
        List {
            speedSection
            connectionSection
            if let policy = model.policy { accountSection(policy) }
            deviceSection
            checkSection
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(String(localized: "Server & Connection"))
        .task {
            await model.load(authManager, localURL: URL(string: localURL).flatMap { $0.host == nil ? nil : $0 },
                             remoteURL: URL(string: remoteURL).flatMap { $0.host == nil ? nil : $0 })
        }
    }

    private var speedSection: some View {
        Section {
            if let bitsPerSecond = model.bitsPerSecond {
                LabeledContent("Download Speed", value: ServerConnectionModel.rate(bitsPerSecond))
                    .tvReadOnlyRow()
                if let responseTime = model.responseTime {
                    LabeledContent("Response Time", value: String(localized: "\(Int(responseTime.rounded())) ms"))
                        .tvReadOnlyRow()
                }
                if let video = model.videoQuality {
                    LabeledContent("Video", value: video).tvReadOnlyRow()
                }
                if let music = model.musicQuality {
                    LabeledContent("Music", value: music).tvReadOnlyRow()
                }
            } else if model.testFailed {
                Text("The speed test didn't finish. The server may block it, or the connection dropped.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.palette("F43F5E"))
                    .tvReadOnlyRow()
            }
            Button {
                Task { await model.runSpeedTest(authManager) }
            } label: {
                HStack {
                    Spacer()
                    if model.isTesting { ProgressView().padding(.trailing, 6) }
                    Text(model.isTesting ? "Testing…" : model.bitsPerSecond == nil ? "Test Speed" : "Test Again")
                    Spacer()
                }
            }
            .formRowButton()
            .disabled(model.isTesting)
        } header: {
            header("Speed Test", systemImage: "speedometer")
        } footer: {
            Text("Measures this connection to your server, the way the player does before a video starts. Wi-Fi and mobile data can differ.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    private var connectionSection: some View {
        Section {
            if let currentlyUsing { LabeledContent("Currently Using", value: currentlyUsing).tvReadOnlyRow() }
            if let address = authManager.state.credential?.baseURL.absoluteString {
                LabeledContent("Address", value: address).lineLimit(1).tvReadOnlyRow()
            }
            if model.local != .notSet { reachRow("Local Address", model.local) }
            if model.remote != .notSet { reachRow("Remote Address", model.remote) }
            if let info = model.info {
                LabeledContent("Server", value: info.serverName ?? "—").tvReadOnlyRow()
                LabeledContent("Jellyfin", value: info.version ?? "—").tvReadOnlyRow()
            }
        } header: {
            header("Connection", systemImage: "network")
        }
    }

    private func reachRow(_ title: LocalizedStringKey, _ reach: ServerConnectionModel.Reach) -> some View {
        LabeledContent(title) {
            switch reach {
            case .checking, .notSet: ProgressView()
            case .reachable(let time): Text("Answers in \(Int(time.rounded())) ms")
            case .unreachable: Text("Doesn't answer").foregroundStyle(DT.Color.palette("F43F5E"))
            }
        }
        .tvReadOnlyRow()
    }

    private func accountSection(_ policy: UserPolicy) -> some View {
        Section {
            LabeledContent("Streaming Away from Home", value: policy.remoteClientBitrateLimit.flatMap { $0 > 0 ? $0 : nil }
                .map { String(localized: "Up to \(ServerConnectionModel.rate($0))") } ?? String(localized: "No limit"))
                .tvReadOnlyRow()
            allowed("Remote Access", policy.enableRemoteAccess)
            allowed("Downloads", policy.enableContentDownloading)
            allowed("Video Conversion", policy.enableVideoPlaybackTranscoding)
            allowed("Audio Conversion", policy.enableAudioPlaybackTranscoding)
            allowed("Live TV", policy.enableLiveTvAccess)
            allowed("Deleting Items", policy.enableContentDeletion)
            LabeledContent("Streams at Once", value: policy.maxActiveSessions > 0 ? "\(policy.maxActiveSessions)" : String(localized: "No limit"))
                .tvReadOnlyRow()
        } header: {
            header("Your Account", systemImage: "person.crop.circle")
        } footer: {
            Text("Set by your server's admin.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    private func allowed(_ title: LocalizedStringKey, _ isAllowed: Bool) -> some View {
        LabeledContent(title, value: isAllowed ? String(localized: "Allowed") : String(localized: "Not Allowed"))
            .tvReadOnlyRow()
    }

    private var engine: PlaybackEngineKind {
        PlaybackEngineKind(rawValue: UserDefaults.standard.string(forKey: "playbackEngine") ?? "") ?? .auto
    }

    @ViewBuilder
    private var deviceSection: some View {
        if let baseURL = authManager.state.credential?.baseURL {
            let engine = engine
            let native = engine == .auto || engine == .aether
            let summary = JellyfinMediaClient.directPlaySummary(nativeDecoder: native, baseURL: baseURL)
            Section {
                LabeledContent("Player", value: engine == .auto ? String(localized: "Auto (Aether)") : engine.rawValue)
                    .tvReadOnlyRow()
                LabeledContent("Files", value: names(summary.containers)).tvReadOnlyRow()
                LabeledContent("Video", value: summary.videoCodecs.map(names) ?? String(localized: "Any format")).tvReadOnlyRow()
                LabeledContent("Audio", value: summary.audioCodecs.map(names) ?? String(localized: "Any format")).tvReadOnlyRow()
                LabeledContent("AV1 Hardware Decoding", value: summary.decodesAV1InHardware ? String(localized: "Yes") : String(localized: "No"))
                    .tvReadOnlyRow()
            } header: {
                header("Plays as It Is on This Device", systemImage: "play.rectangle")
            } footer: {
                Text(summary.isCompatibilityMode
                     ? "Compatibility Mode is on, so the server converts everything else to H.264 and AAC."
                     : "Anything else, the server converts as it plays. Your music plays as it is when the format is one this device reads.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    private func names(_ formats: [String]) -> String {
        ListFormatter.localizedString(byJoining: formats.map { $0.uppercased() })
    }

    private var checkSection: some View {
        Section {
            if model.problems.isEmpty {
                Label("Nothing looks wrong", systemImage: "checkmark.circle")
                    .foregroundStyle(DT.Color.palette("10B981"))
                    .tvReadOnlyRow()
            } else {
                ForEach(model.problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DT.Color.palette("F59E0B"))
                        .tvReadOnlyRow()
                }
            }
        } header: {
            header("Check", systemImage: "stethoscope")
        } footer: {
            Text("Run the speed test for a fuller check.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    private func header(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
    }
}
