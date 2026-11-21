// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The Live TV library from Browse: channels, the guide and recordings. The segmented control
/// and search sit in the window's toolbar, as on other Mac apps.
struct LiveTVView: View {
    let library: JellyfinLibrary

    @Environment(AuthManager.self) private var authManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PlaybackPresenter.self) private var playbackPresenter
    @State private var model = LiveTVModel()
    @SceneStorage("liveTVTab") private var tab: LiveTVTab = .channels

    var body: some View {
        Group {
            if !model.searchQuery.isEmpty {
                LiveTVSearchResults(model: model)
            } else {
                switch tab {
                case .channels: LiveTVChannelsList(model: model)
                case .guide: LiveTVGuideView(model: model)
                case .recordings: LiveTVRecordingsView(model: model)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .navigationTitle(library.name)
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Channels and programmes")
        .onChange(of: model.searchQuery) { _, _ in model.search(authManager: authManager) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Live TV", selection: $tab) {
                    ForEach(LiveTVTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!model.searchQuery.isEmpty)
            }
            if tab != .recordings, model.searchQuery.isEmpty, model.hasFavorites || model.favoritesOnly {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $model.favoritesOnly.animation(DT.Animation.fast)) {
                        Label("Favorites Only", systemImage: model.favoritesOnly ? "star.fill" : "star")
                    }
                    .toggleStyle(.button)
                    .help("Favorites Only")
                }
            }
        }
        .task { await model.loadChannels(authManager: authManager) }
        .task { await model.loadRecordings(authManager: authManager) }
        // Not while the player covers the screen or the app is in the background.
        .task(id: scenePhase == .active && playbackPresenter.request == nil) {
            guard scenePhase == .active, playbackPresenter.request == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await model.refreshNowPlaying(authManager: authManager)
            }
        }
        .onChange(of: tab) { _, newTab in
            guard newTab == .recordings else { return }
            Task { await model.loadRecordings(authManager: authManager) }
        }
        .liveTVPresentations(model: model) {
            Task { await model.loadRecordings(authManager: authManager) }
        }
    }
}

// MARK: - Programme sheet and player

extension View {
    /// The programme sheet, the player for a channel or recording, and the recording error,
    /// for the Live TV screen and for Live TV results in Browse's search. The player fills the
    /// window through the app's PlaybackPresenter, like every other title on the Mac.
    func liveTVPresentations(model: LiveTVModel, onPlayerClosed: @escaping () -> Void = {}) -> some View {
        modifier(LiveTVPresentations(model: model, onPlayerClosed: onPlayerClosed))
    }
}

private struct LiveTVPresentations: ViewModifier {
    @Bindable var model: LiveTVModel
    let onPlayerClosed: () -> Void

    @Environment(PlaybackPresenter.self) private var playbackPresenter

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.selectedProgram) { program in
                LiveTVProgramSheet(model: model, program: program)
            }
            .sheet(item: $model.editingSeriesTimer) { seriesTimer in
                LiveTVSeriesEditor(model: model, seriesTimer: seriesTimer) { model.editingSeriesTimer = nil }
                    .padding(DT.Spacing.lg)
                    .frame(minWidth: 440, idealWidth: 480)
                    .screenBackground()
            }
            .onChange(of: model.playbackRequest) { _, request in
                guard let request else { return }
                playbackPresenter.present(request.item, startTicks: request.startTicks)
                model.playbackRequest = nil
            }
            .onChange(of: playbackPresenter.request == nil) { _, closed in
                guard closed else { return }
                PlayQueue.clear()
                LiveTVQueue.channels = []
                onPlayerClosed()
            }
            .alert("Live TV", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.actionError ?? "")
            }
    }
}

/// A programme's details in a sheet sized for a Mac window.
struct LiveTVProgramSheet: View {
    let model: LiveTVModel
    let program: LiveTVProgram

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LiveTVProgramDetails(model: model, program: program) { dismiss() }
                    .padding(DT.Spacing.lg)
            }
            .screenBackground()
            .navigationTitle(LiveTVProgramDetails.title(for: program, in: model))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 360, idealHeight: 460)
    }
}

// MARK: - Channels

struct LiveTVChannelsList: View {
    let model: LiveTVModel

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if model.isLoadingChannels {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.channelsFailed {
            ContentUnavailableView {
                Label("Couldn't Load Channels", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await model.loadChannels(authManager: authManager) } }
            }
        } else if model.visibleChannels.isEmpty {
            LiveTVEmptyChannels(favoritesOnly: model.favoritesOnly)
        } else {
            TimelineView(.everyMinute) { context in
                List {
                    ForEach(model.visibleChannels) { channel in
                        channelRow(channel, now: context.date)
                    }
                    if model.canLoadMore {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func channelRow(_ channel: LiveTVChannel, now: Date) -> some View {
        Button { model.play(channel) } label: {
            LiveTVChannelRow(channel: channel, now: now, showsGuide: model.hasGuide != false)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: DT.Spacing.pagePad, bottom: 8, trailing: DT.Spacing.pagePad))
        .swipeActions(edge: .leading) {
            Button { model.toggleFavorite(channel, authManager: authManager) } label: {
                Label(channel.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: channel.isFavorite ? "star.slash" : "star")
            }
            .tint(DT.Color.palette("F59E0B"))
        }
        .contextMenu {
            LiveTVChannelMenu(model: model, channel: channel)
        }
        .onAppear {
            Task { await model.loadMoreIfNeeded(after: channel, authManager: authManager) }
        }
    }
}
