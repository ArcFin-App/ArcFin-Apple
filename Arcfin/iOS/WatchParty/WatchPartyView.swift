// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A watch party: the host starts one from a title's page, the others join with its QR code
/// or code. Full screen on iPhone and iPad, with nothing presented over it.
struct WatchPartyView: View {
    enum Launch: Equatable {
        /// Start a party for this title, now or at a time the host picks.
        case host(MediaItem, officialRating: String?)
        /// Join one, straight away when a code came with it.
        case join(code: String?)
    }

    let launch: Launch
    /// Opens the player once the party has started, after this screen has closed.
    var play: (PlaybackRequest) -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var model: WatchPartyModel?
    @State private var path: [WatchPartyRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    WatchPartyContent(model: model, launch: launch, path: $path) { dismiss() } play: { request in
                        model.stopPolling()
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .seconds(0.4))
                            play(request)
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DT.Color.backgroundPrimary)
            .navigationDestination(for: WatchPartyRoute.self) { route in
                if let model {
                    switch route {
                    case .scan: WatchPartyScanView(model: model) { path.removeAll() }
                    case .schedule:
                        WatchPartyScheduleView(initial: model.state?.scheduledFor, others: model.others, confirmTitle: "Save") { date in
                            await model.schedule(date)
                            if model.error == nil { path.removeAll() }
                        }
                        .navigationTitle("Change Time")
                        .navigationBarTitleDisplayMode(.inline)
                    case .pick:
                        WatchPartyPickView { item in
                            path.append(item.type == .series ? .episodes(item) : .host(item))
                        }
                    case .episodes(let series):
                        WatchPartyEpisodePicker(series: series) { path.append(.host($0)) }
                    case .host(let item):
                        WatchPartyScheduleView(item: item, confirmTitle: "Start") { date in
                            await model.create(itemID: item.id, scheduledFor: date)
                            if model.state != nil { path.removeAll() }
                        }
                        .navigationTitle("Watch Party")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
        .task {
            if model == nil { model = WatchPartyModel(authManager: authManager) }
        }
    }
}

/// A watch party screen to open.
struct WatchPartyLaunch: Identifiable {
    let id = UUID()
    let launch: WatchPartyView.Launch

    init(_ launch: WatchPartyView.Launch) { self.launch = launch }
}

enum WatchPartyRoute: Hashable {
    case scan, schedule, pick
    case episodes(MediaItem)
    case host(MediaItem)
}

private struct WatchPartyContent: View {
    @Bindable var model: WatchPartyModel
    let launch: WatchPartyView.Launch
    @Binding var path: [WatchPartyRoute]
    var close: () -> Void
    var play: (PlaybackRequest) -> Void

    @State private var showEnterCode = false
    @State private var code = ""
    @State private var showLeave = false

    private var hosted: (item: MediaItem, officialRating: String?)? {
        if case .host(let item, let officialRating) = launch { return (item, officialRating) }
        return nil
    }

    private var joinCode: String? {
        if case .join(let code) = launch { return code }
        return nil
    }

    var body: some View {
        content
            .navigationTitle("Watch Party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Waiting for a scheduled start, this can close and be opened again later.
                ToolbarItem(placement: .cancellationAction) {
                    if let party = model.state, !party.isWaiting {
                        Button("Leave") { HapticManager.warning(); showLeave = true }
                    } else {
                        Button("Close", action: close)
                    }
                }
            }
            .alert("Leave This Watch Party?", isPresented: $showLeave) {
                Button("Leave", role: .destructive) {
                    model.leave()
                    close()
                }
                Button("Stay", role: .cancel) {}
            } message: {
                Text(model.isHost
                     ? "Someone else in the party becomes the host."
                     : "You can join again with the code while the party is open.")
            }
            .alert("Watch Party", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
            .alert("Enter the Code", isPresented: $showEnterCode) {
                TextField("Code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join") { Task { await model.join(code: code) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It's shown under the QR code on the host's screen.")
            }
            .onAppear { model.start(joinCode: joinCode) }
            .onChange(of: model.error) { _, new in if new != nil { HapticManager.error() } }
            .onChange(of: model.state?.code) { old, new in if old == nil, new != nil { HapticManager.success() } }
    }

    @ViewBuilder private var content: some View {
        if let availability = model.availability, !availability.enabled {
            ContentUnavailableView("Watch Parties Are Off", systemImage: "person.2.slash",
                                   description: Text("Your server's admin has turned off watch parties for you."))
        } else if model.availability == nil && model.error == nil {
            ProgressView()
        } else if model.state != nil {
            WatchPartyLobbyView(model: model, play: play, changeTime: { path.append(.schedule) },
                                leave: { HapticManager.warning(); showLeave = true }, close: close)
        } else if let hosted, hosted.item.type == .series {
            WatchPartyEpisodePicker(series: hosted.item) { path.append(.host($0)) }
        } else if let hosted {
            WatchPartyScheduleView(item: hosted.item, officialRating: hosted.officialRating, confirmTitle: "Start") { date in
                await model.create(itemID: hosted.item.id, scheduledFor: date)
            }
        } else {
            WatchPartyJoinView(parties: model.myParties, start: { path.append(.pick) }, scan: { path.append(.scan) },
                               enterCode: { code = ""; showEnterCode = true }) { party in
                Task { await model.reopen(party) }
            }
        }
    }
}
