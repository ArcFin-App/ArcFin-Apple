// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// One section of the server's configuration, held as the JSON the server sent so saving
/// posts every field back, including ones these screens don't show.
@MainActor @Observable
final class AdminConfigModel {
    let section: String?
    private(set) var values: [String: Any] = [:]
    private var original: [String: Any] = [:]
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var version: ServerVersion?
    var error: String?
    var saved = false
    /// Changed settings the server didn't keep as sent, after a save.
    var notKept: [String] = []

    init(section: String?) { self.section = section }

    var hasChanges: Bool { !ServerEditGuard.changedKeys(from: original, to: values).isEmpty }

    func isChanged(_ key: String) -> Bool {
        ServerEditGuard.changedKeys(from: original, to: values).contains(key)
    }

    func originalInt(_ key: String) -> Int? {
        (original[key] as? NSNumber)?.intValue
    }
    var compatibility: ServerCompatibility.Status { ServerCompatibility.status(version) }

    /// Shown only when the server sends the setting and its version has it.
    func has(_ key: String) -> Bool {
        values[key] != nil && !(values[key] is NSNull) && ServerCompatibility.allows(key, on: version)
    }

    /// Whether a choice of a setting exists in this server's version.
    func offers(_ key: String, _ value: String) -> Bool {
        ServerCompatibility.allows("\(key)=\(value)", on: version)
    }

    func load(authManager: AuthManager) async {
        guard let access = AdminAccess.session(authManager) else { return }
        version = await ServerVersions.version(for: access.credential)
        do {
            let data = try await JellyfinAdminClient().configuration(section, credential: access.credential, authHeader: access.header)
            values = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            original = values
            error = nil
        } catch {
            self.error = String(localized: "Couldn't load the server's settings.")
        }
        isLoading = false
    }

    func save(authManager: AuthManager) {
        guard compatibility.canSave else { return }
        let mismatched = ServerEditGuard.mismatches(from: original, to: values)
        guard mismatched.isEmpty else {
            error = String(localized: "Nothing was saved: \(ServerEditGuard.describe(mismatched)) didn't match what the server expects.")
            return
        }
        guard let access = AdminAccess.session(authManager),
              let data = try? JSONSerialization.data(withJSONObject: values) else { return }
        let changed = ServerEditGuard.changedKeys(from: original, to: values), sent = values
        isSaving = true
        Task {
            defer { isSaving = false }
            let client = JellyfinAdminClient()
            do {
                try await client.setConfiguration(section, data, credential: access.credential, authHeader: access.header)
            } catch {
                self.error = String(localized: "The server didn't take the change.")
                return
            }
            // What the server kept, read back, so a setting it dropped or reset isn't reported as saved.
            if let reread = try? await client.configuration(section, credential: access.credential, authHeader: access.header),
               let object = try? JSONSerialization.jsonObject(with: reread) as? [String: Any] {
                notKept = ServerEditGuard.notKept(changed, sent: sent, reread: object)
                values = object
                original = object
            } else {
                original = values
            }
            if notKept.isEmpty { saved = true }
            HapticManager.impact(.light)
        }
    }

    func bool(_ key: String) -> Binding<Bool> {
        Binding(get: { self.values[key] as? Bool ?? false }, set: { self.values[key] = $0 })
    }

    func text(_ key: String) -> Binding<String> {
        Binding(get: { self.values[key] as? String ?? "" }, set: { self.values[key] = $0 })
    }

    func int(_ key: String) -> Binding<Int> {
        Binding(get: { (self.values[key] as? NSNumber)?.intValue ?? 0 }, set: { self.values[key] = $0 })
    }

    /// A list of strings, edited as one comma-separated line.
    func list(_ key: String) -> Binding<String> {
        Binding(
            get: { (self.values[key] as? [String] ?? []).joined(separator: ", ") },
            set: { self.values[key] = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        )
    }

    /// Whether `value` is in the list at `key`, as a switch.
    func member(_ key: String, _ value: String) -> Binding<Bool> {
        Binding(
            get: { (self.values[key] as? [String] ?? []).contains(value) },
            set: { on in
                var list = self.values[key] as? [String] ?? []
                list.removeAll { $0 == value }
                if on { list.append(value) }
                self.values[key] = list
            }
        )
    }
}

/// The Save button, the load error and the "saved" note every settings page shares.
private struct AdminConfigPage<Content: View>: View {
    let title: String
    let model: AdminConfigModel
    let restartNote: Bool
    /// False while something on the page can't be sent as it is.
    var isValid = true
    @ViewBuilder let content: () -> Content

    @Environment(AuthManager.self) private var authManager
    @State private var confirmUntested = false

    var body: some View {
        List {
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                AdminCompatibilityNote(status: model.compatibility)
                content()
                    .disabled(!model.compatibility.canSave)
                if restartNote {
                    Section {
                        Label("Some of these take effect only after the server restarts, from the Admin tab.", systemImage: "arrow.clockwise.circle")
                            .font(.system(.footnote))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(title)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if model.compatibility.needsConfirmation { confirmUntested = true } else { model.save(authManager: authManager) }
                }
                .disabled(!model.hasChanges || model.isSaving || !model.compatibility.canSave || !isValid)
            }
        }
        .adminDiscardChangesGuard(model.hasChanges)
        .task { await model.load(authManager: authManager) }
        .untestedServerConfirmation(isPresented: $confirmUntested, status: model.compatibility) {
            model.save(authManager: authManager)
        }
        .alert("Not All Saved", isPresented: Binding(get: { !model.notKept.isEmpty }, set: { if !$0 { model.notKept = [] } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The server didn't keep \(ServerEditGuard.describe(model.notKept)) as sent. The page now shows what it has.")
        }
        .alert("Couldn't Do That", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
        .alert("Saved", isPresented: Binding(get: { model.saved }, set: { model.saved = $0 })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restartNote ? String(localized: "The server has the new settings. Restart it for all of them to take effect.")
                 : String(localized: "The server has the new settings."))
        }
    }
}

extension View {
    /// With unsaved changes, going back asks before throwing them away.
    func adminDiscardChangesGuard(_ hasChanges: Bool) -> some View {
        modifier(AdminDiscardChangesGuard(hasChanges: hasChanges))
    }
}

private struct AdminDiscardChangesGuard: ViewModifier {
    let hasChanges: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(hasChanges)
            .toolbar {
                if hasChanges {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { confirming = true }
                    }
                }
            }
            .alert("Discard Changes?", isPresented: $confirming) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("What you changed on this page hasn't been saved to the server.")
            }
    }
}

/// A number field with a unit after it, for the settings pages.
private struct AdminNumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    var unit: LocalizedStringKey? = nil

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            // No thousands separator: ports, limits and counts read as plain numbers.
            TextField("0", value: $value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 110)
            if let unit {
                Text(unit).foregroundStyle(DT.Color.textSecondary)
            }
        }
    }
}

/// Server › General: its name, metadata language, Quick Connect, and limits.
struct AdminGeneralSettingsView: View {
    @State private var model = AdminConfigModel(section: nil)

    var body: some View {
        AdminConfigPage(title: String(localized: "General"), model: model, restartNote: false) {
            Section {
                if model.has("ServerName") {
                    TextField("Server Name", text: model.text("ServerName"))
                }
                if model.has("QuickConnectAvailable") {
                    Toggle("Quick Connect", isOn: model.bool("QuickConnectAvailable"))
                }
            } footer: {
                Text("Quick Connect lets someone sign in on a TV by approving a code on a device already signed in.")
            }
            Section("Metadata") {
                if model.has("PreferredMetadataLanguage") {
                    TextField("Language (e.g. en)", text: model.text("PreferredMetadataLanguage"))
                        .autocorrectionDisabled()
                }
                if model.has("MetadataCountryCode") {
                    TextField("Country (e.g. US)", text: model.text("MetadataCountryCode"))
                        .autocorrectionDisabled()
                }
            }
            Section {
                if model.has("RemoteClientBitrateLimit") {
                    AdminNumberField(title: "Remote Streaming Limit", value: megabits("RemoteClientBitrateLimit"), unit: "Mb/s")
                }
                if model.has("LibraryScanFanoutConcurrency") {
                    AdminNumberField(title: "Parallel Library Scans", value: model.int("LibraryScanFanoutConcurrency"))
                }
                if model.has("ParallelImageEncodingLimit") {
                    AdminNumberField(title: "Parallel Image Encodes", value: model.int("ParallelImageEncodingLimit"))
                }
                if model.has("LibraryMonitorDelay") {
                    AdminNumberField(title: "Wait Before Scanning a Change", value: model.int("LibraryMonitorDelay"), unit: "s")
                }
            } header: {
                Text("Performance")
            } footer: {
                Text("0 means no limit, or the server's own choice. The streaming limit applies to every connection from outside your network.")
            }
        }
    }

    /// The server keeps the limit in bits per second.
    private func megabits(_ key: String) -> Binding<Int> {
        let bits = model.int(key)
        return Binding(get: { bits.wrappedValue / 1_000_000 }, set: { bits.wrappedValue = $0 * 1_000_000 })
    }
}

/// Server › Playback & Transcoding: hardware acceleration, codecs, quality and throttling.
struct AdminEncodingSettingsView: View {
    @State private var model = AdminConfigModel(section: "encoding")

    private static let accelerations: [(value: String, label: LocalizedStringKey)] = [
        ("none", "None (Software)"), ("nvenc", "NVIDIA NVENC"), ("qsv", "Intel Quick Sync"),
        ("vaapi", "Video Acceleration API (VA-API)"), ("amf", "AMD AMF"), ("videotoolbox", "Apple VideoToolbox"),
        ("rkmpp", "Rockchip MPP"), ("v4l2m2m", "Video4Linux2"),
    ]

    private static let decodeCodecs: [(value: String, label: String)] = [
        ("h264", "H.264"), ("hevc", "HEVC"), ("mpeg2video", "MPEG-2"), ("vc1", "VC-1"),
        ("vp8", "VP8"), ("vp9", "VP9"), ("av1", "AV1"),
    ]

    private static let presets: [(value: String, label: LocalizedStringKey)] = [
        ("auto", "Automatic"), ("veryslow", "Very Slow"), ("slower", "Slower"), ("slow", "Slow"), ("medium", "Medium"),
        ("fast", "Fast"), ("faster", "Faster"), ("veryfast", "Very Fast"), ("superfast", "Super Fast"), ("ultrafast", "Ultra Fast"),
    ]

    var body: some View {
        AdminConfigPage(title: String(localized: "Playback & Transcoding"), model: model, restartNote: false) {
            AdminEncodersSection()
            Section {
                if model.has("HardwareAccelerationType") {
                    Picker("Hardware Acceleration", selection: model.text("HardwareAccelerationType")) {
                        ForEach(Self.accelerations.filter { model.offers("HardwareAccelerationType", $0.value) }, id: \.value) {
                            Text($0.label).tag($0.value)
                        }
                    }
                }
                if model.text("HardwareAccelerationType").wrappedValue != "none" {
                    if model.has("EnableHardwareEncoding") {
                        Toggle("Hardware Encoding", isOn: model.bool("EnableHardwareEncoding"))
                    }
                }
            } header: {
                Text("Acceleration")
            } footer: {
                Text("Pick what the server's graphics hardware supports. A wrong choice makes conversions fail.")
            }
            if model.text("HardwareAccelerationType").wrappedValue != "none", model.has("HardwareDecodingCodecs") {
                Section("Hardware Decoding") {
                    ForEach(Self.decodeCodecs, id: \.value) { codec in
                        Toggle(codec.label, isOn: model.member("HardwareDecodingCodecs", codec.value))
                    }
                    if model.has("EnableDecodingColorDepth10Hevc") {
                        Toggle("10-bit HEVC", isOn: model.bool("EnableDecodingColorDepth10Hevc"))
                    }
                    if model.has("EnableDecodingColorDepth10Vp9") {
                        Toggle("10-bit VP9", isOn: model.bool("EnableDecodingColorDepth10Vp9"))
                    }
                }
            }
            Section("Encoding") {
                if model.has("AllowHevcEncoding") {
                    Toggle("Allow HEVC Encoding", isOn: model.bool("AllowHevcEncoding"))
                }
                if model.has("AllowAv1Encoding") {
                    Toggle("Allow AV1 Encoding", isOn: model.bool("AllowAv1Encoding"))
                }
                if model.has("EncoderPreset") {
                    Picker("Encoder Preset", selection: model.text("EncoderPreset")) {
                        ForEach(Self.presets, id: \.value) { Text($0.label).tag($0.value) }
                    }
                }
                if model.has("H264Crf") {
                    AdminNumberField(title: "H.264 Quality (CRF)", value: model.int("H264Crf"))
                }
                if model.has("H265Crf") {
                    AdminNumberField(title: "HEVC Quality (CRF)", value: model.int("H265Crf"))
                }
                if model.has("EncodingThreadCount") {
                    AdminNumberField(title: "Encoding Threads", value: model.int("EncodingThreadCount"))
                }
            }
            Section {
                if model.has("EnableTonemapping") {
                    Toggle("Tone Mapping", isOn: model.bool("EnableTonemapping"))
                }
                if model.has("EnableThrottling") {
                    Toggle("Throttle Conversions", isOn: model.bool("EnableThrottling"))
                }
                if model.has("EnableSegmentDeletion") {
                    Toggle("Delete Played Segments", isOn: model.bool("EnableSegmentDeletion"))
                }
                if model.has("TranscodingTempPath") {
                    TextField("Transcode Folder", text: model.text("TranscodingTempPath"))
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Behaviour")
            } footer: {
                Text("Tone mapping converts HDR to SDR for screens without HDR. Throttling pauses a conversion that's well ahead of playback; deleting played segments keeps the transcode folder small. Lower CRF means better quality and bigger streams; -1 threads lets the server choose.")
            }
        }
    }
}

/// Server › Networking: remote access, ports, HTTPS, and which addresses count as local.
struct AdminNetworkSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = AdminConfigModel(section: "network")

    private static let portKeys = ["InternalHttpPort", "InternalHttpsPort", "PublicHttpPort", "PublicHttpsPort"]

    private var portsValid: Bool {
        Self.portKeys.allSatisfy { !model.has($0) || (1...65535).contains(model.int($0).wrappedValue) }
    }

    /// The address this device reaches the server at, when the changes would stop that
    /// working once the server restarts: its port moved, or HTTPS switched on or off under it.
    private var cutOffAddress: String? {
        guard let url = authManager.state.credential?.baseURL else { return nil }
        let isHTTPS = url.scheme == "https"
        let port = url.port ?? (isHTTPS ? 443 : 80)
        let keys = isHTTPS ? ["InternalHttpsPort", "PublicHttpsPort"] : ["InternalHttpPort", "PublicHttpPort"]
        let portMoved = keys.contains { model.isChanged($0) && model.originalInt($0) == port }
        let schemeLost = isHTTPS
            ? model.isChanged("EnableHttps") && !model.bool("EnableHttps").wrappedValue
            : model.isChanged("RequireHttps") && model.bool("RequireHttps").wrappedValue
        return portMoved || schemeLost ? url.absoluteString : nil
    }

    var body: some View {
        AdminConfigPage(title: String(localized: "Networking"), model: model, restartNote: true, isValid: portsValid) {
            Section {
                if model.has("EnableRemoteAccess") {
                    Toggle("Allow Remote Connections", isOn: model.bool("EnableRemoteAccess"))
                }
                if model.has("AutoDiscovery") {
                    Toggle("Discoverable on the Network", isOn: model.bool("AutoDiscovery"))
                }
                if model.has("BaseUrl") {
                    TextField("Base URL (e.g. /jellyfin)", text: model.text("BaseUrl"))
                        .autocorrectionDisabled()
                }
            } footer: {
                Text("Turning remote connections off signs out everyone outside your network, which may include this device.")
            }
            Section {
                if model.has("InternalHttpPort") {
                    AdminNumberField(title: "HTTP Port", value: model.int("InternalHttpPort"))
                }
                if model.has("InternalHttpsPort") {
                    AdminNumberField(title: "HTTPS Port", value: model.int("InternalHttpsPort"))
                }
                if model.has("PublicHttpPort") {
                    AdminNumberField(title: "Public HTTP Port", value: model.int("PublicHttpPort"))
                }
                if model.has("PublicHttpsPort") {
                    AdminNumberField(title: "Public HTTPS Port", value: model.int("PublicHttpsPort"))
                }
            } header: {
                Text("Ports")
            } footer: {
                if !portsValid {
                    Text("Port numbers go from 1 to 65535.")
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
            }
            if let address = cutOffAddress {
                Section {
                    Label("After the restart, this device may not reach the server: Arcfin connects to it at \(address).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.palette("f59e0b"))
                }
            }
            Section {
                if model.has("EnableHttps") {
                    Toggle("HTTPS", isOn: model.bool("EnableHttps"))
                }
                if model.has("RequireHttps") {
                    Toggle("Require HTTPS", isOn: model.bool("RequireHttps"))
                }
            } header: {
                Text("Security")
            } footer: {
                Text("HTTPS needs a certificate set up on the server. Behind a reverse proxy, leave these off and let the proxy handle it.")
            }
            Section {
                if model.has("LocalNetworkSubnets") {
                    TextField("Local Networks", text: model.list("LocalNetworkSubnets"))
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                }
                if model.has("KnownProxies") {
                    TextField("Known Proxies", text: model.list("KnownProxies"))
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Addresses")
            } footer: {
                Text("Comma-separated, e.g. 192.168.1.0/24. Local networks don't count against the remote streaming limit; known proxies let the server see the real address behind a reverse proxy.")
            }
        }
    }
}
