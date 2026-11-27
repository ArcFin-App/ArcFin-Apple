// SPDX-License-Identifier: AGPL-3.0-or-later

import JellyfinAPI
import SwiftUI
import AuthCore

/// Settings › Arcs: how the feed plays and picks, sharing, and this person's Arcs history.
struct ArcsSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(ArcsSettings.clipSecondsKey) private var clipSeconds = 30
    @AppStorage(ArcsSettings.spoilerSafeKey) private var spoilerSafe = true
    @AppStorage(ArcsSettings.showReasonsKey) private var showReasons = true
    @AppStorage(ArcsSettings.clipEndKey) private var clipEnd = ArcsClipEnd.loop
    @AppStorage(ArcsSettings.framingKey) private var framing = ArcsFraming.fill
    @AppStorage(ArcsSettings.subtitlesKey) private var subtitles = false
    @AppStorage(ArcsSettings.dataSaverKey) private var dataSaver = ArcsDataSaver.mobile
    @AppStorage(ArcsSettings.watermarkKey) private var watermark = true
    @AppStorage(ArcsSettings.clipOfTheDayKey) private var clipOfTheDay = true
    @AppStorage(ArcsSettings.preloadKey) private var preload = true
    @AppStorage(ArcsSettings.showRequestsKey) private var showRequests = true
    @AppStorage(ArcsSettings.youTubeTrailersKey) private var youTubeTrailers = true
    @Environment(SeerrRepository.self) private var seerrRepo
    @State private var offline = ArcsOfflineStore.shared
    @State private var confirmRemoveSaved = false
    @State private var availability: ArcsAvailability?
    @State private var confirmReset = false
    @State private var resetDone = false

    private let client = ArcsClient()

    var body: some View {
        List {
            Section {
                SettingsPicker("Scene Length", detail: "How long each scene runs. A scene can be shorter when the part of the film it's from is.",
                               selection: $clipSeconds, options: lengths) { Text(Duration.seconds($0).formatted(.units(allowed: [.seconds], width: .wide))) }
                    .syncLocked(ArcsSettings.clipSecondsKey, authManager)
                Toggle(isOn: spoilerBinding) {
                    TVRowLabelText(title: "Hide Spoilers", detail: "Only scenes from episodes you've reached, the first few episodes of shows you haven't started, and nothing from the end of a film you haven't seen.")
                }
                .disabled(availability?.spoilers == .alwaysSafe)
                .syncLocked(ArcsSettings.spoilerSafeKey, authManager)
                Toggle(isOn: $showReasons) {
                    TVRowLabelText(title: "Say Why", detail: "A line under each scene's title, such as \u{201C}Because you liked\u{2026}\u{201D}")
                }
                .syncLocked(ArcsSettings.showReasonsKey, authManager)
                SettingsPicker("When a Scene Ends", selection: $clipEnd, options: ArcsClipEnd.allCases) { Text($0.label) }
                    .syncLocked(ArcsSettings.clipEndKey, authManager)
                Toggle(isOn: $preload) {
                    TVRowLabelText(title: "Preload Arcs", detail: "When Arcfin opens, your server starts getting your first scenes ready, so Arcs plays at once. Uses a little of your server's time each time Arcfin opens.")
                }
                .syncLocked(ArcsSettings.preloadKey, authManager)
                if seerrRepo.isConfigured {
                    Toggle(isOn: $showRequests) {
                        TVRowLabelText(title: "Titles to Request", detail: "Now and then, the trailer of a title that isn't on your server yet, picked for you, with a button to request it.")
                    }
                    .syncLocked(ArcsSettings.showRequestsKey, authManager)
                    if showRequests, availability?.youTubeTrailers != false {
                        Toggle(isOn: $youTubeTrailers) {
                            TVRowLabelText(title: "YouTube Trailers", detail: "Plays each title's trailer from YouTube. Off, you see its poster instead.")
                        }
                        .syncLocked(ArcsSettings.youTubeTrailersKey, authManager)
                    }
                }
            } header: {
                Text("Feed")
            }

            Section {
                SettingsPicker("Framing", detail: "How a widescreen scene fills an upright screen.",
                               selection: $framing, options: ArcsFraming.allCases) { Text($0.label) }
                    .syncLocked(ArcsSettings.framingKey, authManager)
                Toggle(isOn: $subtitles) {
                    TVRowLabelText(title: "Subtitles", detail: "In your subtitle language, when the scene has them.")
                }
                .syncLocked(ArcsSettings.subtitlesKey, authManager)
                SettingsPicker("Data Saver", detail: "Scenes come in at a lower quality, using less data.",
                               selection: $dataSaver, options: ArcsDataSaver.allCases) { Text($0.label) }
                    .syncLocked(ArcsSettings.dataSaverKey, authManager)
            } header: {
                Text("Picture and Sound")
            }

            if availability?.sharing != .off {
                Section {
                    Toggle(isOn: $watermark) {
                        TVRowLabelText(title: "Arcfin Watermark", detail: "A small Arcfin logo in the corner of scenes you share. You can still turn it off for one scene when you share it.")
                    }
                    .disabled(availability.map { $0.watermark != .optional } ?? false)
                    .syncLocked(ArcsSettings.watermarkKey, authManager)
                } header: {
                    Text("Sharing")
                } footer: {
                    if availability?.watermark == .forced {
                        Text("Your server's admin has the watermark always on.")
                    } else if availability?.watermark == .off {
                        Text("Your server's admin has turned the watermark off.")
                    }
                }
            }

            if availability?.clipOfTheDay != false {
                Section {
                    Toggle(isOn: $clipOfTheDay) {
                        TVRowLabelText(title: "Scene of the Day on Home", detail: "One scene picked for you each day, at the top of Home.")
                    }
                    .syncLocked(ArcsSettings.clipOfTheDayKey, authManager)
                }
            }

            Section {
                if offline.isSaving {
                    HStack {
                        TVRowLabelText(title: "Saving Scenes", detail: "\(offline.saved) of \(ArcsOfflineStore.packSize)")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Button {
                        Task { await offline.save(authManager: authManager, spoilerSafe: spoilerBinding.wrappedValue, seconds: clipSeconds,
                                                  quality: dataSaver == .always ? .low : .high) }
                    } label: {
                        TVRowLabelText(title: offline.clips.isEmpty ? "Save Scenes for Offline" : "Save New Scenes",
                                       detail: "Twenty scenes picked for you, to watch without a connection. Saving again replaces them.")
                    }
                }
                if !offline.clips.isEmpty, !offline.isSaving {
                    LabeledContent {
                        Text(Measurement(value: Double(offline.bytes), unit: UnitInformationStorage.bytes).formatted(.byteCount(style: .file)))
                    } label: {
                        Text("\(offline.clips.count) Scenes Saved")
                    }
                    Button("Remove Saved Scenes", role: .destructive) { confirmRemoveSaved = true }
                }
            } header: {
                Text("Offline")
            } footer: {
                if offline.failed { Text("Couldn't save scenes. Check your connection, then try again.") }
            }

            Section {
                NavigationLink {
                    ArcsLikedView()
                } label: {
                    TVRowLabelText(title: "Liked Scenes", detail: "Every scene you've liked, to watch again.")
                }
                NavigationLink {
                    ArcsFriendsView()
                } label: {
                    TVRowLabelText(title: "Friends", detail: "Your code, and the people you can send scenes to.")
                }
                NavigationLink {
                    ArcsHiddenView()
                } label: {
                    TVRowLabelText(title: "Hidden Titles", detail: "Titles you've hidden or asked to see less of.")
                }
                Button(role: .destructive) { confirmReset = true } label: {
                    TVRowLabelText(title: "Reset Recommendations", detail: "Arcs forgets your likes, what you skipped and what you hid, and starts learning again.")
                }
            } header: {
                Text("Your Arcs")
            } footer: {
                if resetDone { Text("Your Arcs history has been reset.") }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Arcs")
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("Reset Recommendations?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { Task { await reset() } }
        } message: {
            Text("Your likes, hidden titles and what you've watched in Arcs are forgotten. Favourites and your watch history stay.")
        }
        .task {
            if let profile = authManager.state.credential?.id { offline.load(profile: profile) }
            await loadAvailability()
        }
        .confirmationDialog("Remove Saved Scenes?", isPresented: $confirmRemoveSaved, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { offline.removeAll() }
        }
    }

    private var lengths: [Int] {
        guard let availability else { return ArcsSettings.clipSecondsOptions }
        let allowed = ArcsSettings.clipSecondsOptions.filter { (availability.minSeconds...availability.maxSeconds).contains($0) }
        return allowed.contains(clipSeconds) ? allowed : (allowed + [clipSeconds]).sorted()
    }

    private var spoilerBinding: Binding<Bool> {
        Binding(get: { availability?.spoilers == .alwaysSafe || spoilerSafe }, set: { spoilerSafe = $0 })
    }

    private func loadAvailability() async {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        availability = try? await client.availability(credential: credential, authHeader: header)
    }

    private func reset() async {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        do {
            try await client.reset(credential: credential, authHeader: header)
            resetDone = true
        } catch {
            resetDone = false
        }
    }
}
