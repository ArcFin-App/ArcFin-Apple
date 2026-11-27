// SPDX-License-Identifier: AGPL-3.0-or-later

import JellyfinAPI
import SwiftUI
import AuthCore

/// Arcfin for Everyone › Arcs: the same controls as the Arcs section on the Arcfin Sync
/// plugin's page in the Jellyfin dashboard.
struct ArcsAdminView: View {
    let users: [ArcfinSyncAdminUser]

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @State private var settings: ArcsAdminSettings?
    @State private var stats: ArcsAdminStats?
    @State private var error: String?
    @State private var notice: LocalizedStringKey?
    @State private var confirmClear = false

    private let client = ArcsClient()

    private var videoLibraries: [JellyfinLibrary] {
        mediaRepo.libraries.filter { $0.collectionType == .movies || $0.collectionType == .tvshows || $0.collectionType == .unknown }
    }

    var body: some View {
        SettingsForm {
            if let settings {
                Section {
                    Toggle(isOn: bind(\.enabled)) { TVRowLabelText(title: "Arcs") }
                } footer: {
                    Text("A feed of short scenes from this server's films and shows, picked for each person, on iPhone and iPad. Each person only sees titles they're allowed to see.")
                }
                if settings.enabled {
                    usersSection(settings)
                    librariesSection(settings)
                    scenesSection(settings)
                    sharingSection
                    extrasSection
                    recommendationsSection
                    statsSection
                }
            } else {
                AdminPendingSection(error: error)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Arcs")
        .task { await load() }
        .confirmationDialog("Clear the Scene Cache?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { Task { await clearCache() } }
        } message: {
            Text("Scenes are made again the next time someone watches them, which takes a moment each.")
        }
    }

    // MARK: Sections

    private func usersSection(_ settings: ArcsAdminSettings) -> some View {
        Section {
            ForEach(users) { user in
                Toggle(isOn: Binding(get: { !settings.disabledUsers.contains { same($0, user.userId) } }, set: { on in
                    save { s in
                        s.disabledUsers.removeAll { same($0, user.userId) }
                        if !on { s.disabledUsers.append(user.userId) }
                    }
                })) { TVRowLabelText(verbatim: user.name) }
            }
        } header: {
            Text("Who Can Use It")
        } footer: {
            Text("Turned off for someone, Arcs is gone from their Arcfin and the server refuses it.")
        }
    }

    private func librariesSection(_ settings: ArcsAdminSettings) -> some View {
        Section {
            ForEach(videoLibraries) { library in
                Toggle(isOn: Binding(get: { settings.libraries.isEmpty || settings.libraries.contains { same($0, library.id) } }, set: { on in
                    save { s in
                        var chosen = s.libraries.isEmpty ? videoLibraries.map(\.id) : s.libraries
                        chosen.removeAll { same($0, library.id) }
                        if on { chosen.append(library.id) }
                        // Every library chosen is the same as none: new libraries are included too.
                        s.libraries = Set(chosen.map(ArcfinCompanionClient.normalized)) == Set(videoLibraries.map { ArcfinCompanionClient.normalized($0.id) }) ? [] : chosen
                    }
                })) { TVRowLabelText(verbatim: library.name) }
            }
        } header: {
            Text("Libraries")
        } footer: {
            Text("Scenes only come from the libraries turned on here.")
        }
    }

    private func scenesSection(_ settings: ArcsAdminSettings) -> some View {
        Section {
            Picker("Shortest Scene", selection: bind(\.minSeconds)) {
                ForEach([10, 15, 20, 30], id: \.self) { Text(seconds($0)).tag($0) }
            }
            Picker("Longest Scene", selection: bind(\.maxSeconds)) {
                ForEach([30, 45, 60, 90], id: \.self) { Text(seconds($0)).tag($0) }
            }
            Picker("Standard Length", selection: bind(\.defaultSeconds)) {
                ForEach([15, 30, 45, 60].filter { (settings.minSeconds...max(settings.minSeconds, settings.maxSeconds)).contains($0) }, id: \.self) {
                    Text(seconds($0)).tag($0)
                }
            }
            Picker(selection: bind(\.spoilers)) {
                Text("Each Person Chooses").tag(ArcsAvailability.Spoilers.userChoice)
                Text("Always Hidden").tag(ArcsAvailability.Spoilers.alwaysSafe)
            } label: {
                TVRowLabelText(title: "Spoilers", detail: "Hidden, scenes only come from episodes someone has reached, and never from the end of a film they haven't seen.")
            }
            Toggle(isOn: bind(\.useSceneDetection)) {
                TVRowLabelText(title: "Find Scenes Without Chapters", detail: "For files with no chapters, a scheduled task looks for scene changes. It takes a while on a big library.")
            }
            if settings.useSceneDetection {
                Picker(selection: bind(\.sceneScans)) {
                    ForEach(1...8, id: \.self) { Text($0, format: .number).tag($0) }
                } label: {
                    TVRowLabelText(title: "Titles Scanned at Once",
                                   detail: "On the server's GPU when it has one, otherwise its CPU. More at once finishes sooner but uses much more of it while the scan runs, which can slow playback for people watching. Start with 1 or 2.")
                }
            }
            Button("Find Scenes Now") { Task { await rebuild() } }
        } header: {
            Text("Scenes")
        } footer: {
            if let notice { Text(notice) }
        }
    }

    private var sharingSection: some View {
        Section {
            Picker("Sharing", selection: bind(\.sharing)) {
                Text("Allowed").tag(ArcsAvailability.Sharing.allowed)
                Text("Off").tag(ArcsAvailability.Sharing.off)
            }
            if settings?.sharing != .off {
                Picker("Watermark", selection: bind(\.watermark)) {
                    Text("Each Person Chooses").tag(ArcsAvailability.Watermark.optional)
                    Text("Always On").tag(ArcsAvailability.Watermark.forced)
                    Text("Off").tag(ArcsAvailability.Watermark.off)
                }
            }
            Toggle(isOn: bind(\.clipOfTheDay)) { TVRowLabelText(title: "Scene of the Day on Home") }
        } header: {
            Text("Sharing and Home")
        } footer: {
            Text("Shared scenes are the video itself, sent from the person's iPhone or iPad. They never link back to this server.")
        }
    }

    private var extrasSection: some View {
        Section {
            Toggle(isOn: bind(\.requestsInFeed)) {
                TVRowLabelText(title: "Titles to Request", detail: "Trailers of titles that aren't on this server yet, picked for each person, with a button to request them in Seerr. Needs Seerr set up in Arcfin Sync.")
            }
            if settings?.requestsInFeed == true {
                Toggle(isOn: bind(\.youTubeTrailers)) {
                    TVRowLabelText(title: "YouTube Trailers", detail: "Off, titles to request show their poster instead, for everyone, whatever they choose.")
                }
            }
            Picker("Sending Scenes", selection: bind(\.sending)) {
                Text("Everyone").tag("Everyone")
                Text("Off").tag("Off")
            }
            Toggle(isOn: bind(\.dialogueSearch)) {
                TVRowLabelText(title: "Search by What's Said", detail: "A scheduled task reads the text subtitles of films and episodes, so people can find a scene by a line in it.")
            }
            if settings?.dialogueSearch == true {
                Button("Read Subtitles Now") { Task { await rebuildDialogue() } }
            }
        } header: {
            Text("Requests, Sending and Search")
        } footer: {
            Text("Sent scenes show first in the other person's Arcs, with the sender's name and note. No one can send a title the other person can't see.")
        }
    }

    private func rebuildDialogue() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            try await client.rebuildDialogueIndex(credential: access.credential, authHeader: access.header)
            notice = "Reading subtitles. It carries on in the background on the server."
        } catch {
            notice = "Couldn't start reading subtitles."
        }
    }

    private var recommendationsSection: some View {
        Section {
            weight("Watch History", \.history)
            weight("Likes", \.likes)
            weight("Watching Scenes Through", \.watchTime)
            weight("Watch from Here", \.watchFromHere)
            weight("Shares", \.shares)
            weight("Favourites", \.favorites)
            weight("Similar People's Likes", \.similar)
            weight("Popular on This Server", \.popular)
            weight("Newly Added", \.fresh)
            Picker(selection: bind(\.weights.exploration)) {
                Text("Rarely").tag(0.05)
                Text("Sometimes").tag(0.15)
                Text("Often").tag(0.3)
            } label: {
                TVRowLabelText(title: "Something Different", detail: "How often a scene from outside someone's usual taste is mixed in.")
            }
        } header: {
            Text("Recommendations")
        } footer: {
            Text("How much each signal counts when Arcs picks scenes. Popular and similar people's likes only count titles several people liked, so no one's viewing is shown to anyone else.")
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        Section {
            if let stats {
                LabeledContent("Scenes Found", value: stats.clips.formatted())
                LabeledContent("Titles with Scenes", value: stats.indexedTitles.formatted())
                LabeledContent("Likes", value: stats.likes.formatted())
                LabeledContent("Shares", value: stats.shares.formatted())
                LabeledContent("Watch from Here", value: stats.watchFromHere.formatted())
                LabeledContent("Cache") { Text(Measurement(value: stats.cacheMb, unit: UnitInformationStorage.megabytes).formatted(.byteCount(style: .file))) }
                ForEach(stats.topLiked.prefix(5)) { clip in
                    LabeledContent { Text(verbatim: ArcText.sceneLine(clip) ?? "") } label: { Text(verbatim: clip.seriesName ?? clip.name) }
                }
            }
            Picker("Cache Size", selection: bind(\.cacheMb)) {
                ForEach([512, 1024, 2048, 5120, 10240], id: \.self) { mb in
                    Text(Measurement(value: Double(mb), unit: UnitInformationStorage.megabytes).formatted(.byteCount(style: .file))).tag(mb)
                }
            }
            Button("Clear the Scene Cache", role: .destructive) { confirmClear = true }
        } header: {
            Text("On This Server")
        } footer: {
            Text("Scenes are made with the server's own ffmpeg and kept, so the next person to watch one doesn't wait. The most liked scenes are listed above.")
        }
    }

    private func weight(_ title: LocalizedStringKey, _ path: WritableKeyPath<ArcsAdminSettings.Weights, Double>) -> some View {
        let weights: WritableKeyPath<ArcsAdminSettings, ArcsAdminSettings.Weights> = \.weights
        return Picker(title, selection: bind(weights.appending(path: path))) {
            Text("Off").tag(0.0)
            Text("Less").tag(0.5)
            Text("Normal").tag(1.0)
            Text("More").tag(2.0)
        }
    }

    // MARK: Work

    private func bind<V>(_ path: WritableKeyPath<ArcsAdminSettings, V>) -> Binding<V> where V: Equatable {
        Binding(get: { settings![keyPath: path] }, set: { value in save { $0[keyPath: path] = value } })
    }

    private func same(_ a: String, _ b: String) -> Bool {
        ArcfinCompanionClient.normalized(a) == ArcfinCompanionClient.normalized(b)
    }

    private func seconds(_ value: Int) -> String {
        Duration.seconds(value).formatted(.units(allowed: [.seconds], width: .abbreviated))
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            settings = try await client.adminSettings(credential: access.credential, authHeader: access.header)
            stats = try? await client.adminStats(credential: access.credential, authHeader: access.header)
        } catch {
            self.error = String(localized: "Couldn't load the Arcs settings. Check your connection, and that this profile is still an admin.")
        }
    }

    /// Changes the setting straight away, and puts it back if the server doesn't take it.
    private func save(_ change: (inout ArcsAdminSettings) -> Void) {
        guard var next = settings, let access = authManager.arcfinSyncDevicesSession else { return }
        let before = next
        change(&next)
        settings = next
        Task {
            do {
                settings = try await client.saveAdminSettings(next, credential: access.credential, authHeader: access.header)
            } catch {
                settings = before
            }
        }
    }

    private func rebuild() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            try await client.rebuildIndex(credential: access.credential, authHeader: access.header)
            notice = "Finding scenes. It carries on in the background on the server."
        } catch {
            notice = "Couldn't start finding scenes."
        }
    }

    private func clearCache() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        try? await client.clearCache(credential: access.credential, authHeader: access.header)
        stats = try? await client.adminStats(credential: access.credential, authHeader: access.header)
    }
}
