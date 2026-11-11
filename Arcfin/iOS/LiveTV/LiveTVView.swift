// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The Live TV library from Browse: channels, the guide and recordings, under one segmented control.
struct LiveTVView: View {
    let library: JellyfinLibrary

    @Environment(AuthManager.self) private var authManager
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
        .safeAreaBar(edge: .top, spacing: 0) {
            if model.searchQuery.isEmpty { tabPicker }
        }
        .navigationTitle(library.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchQuery, prompt: "Channels and programmes")
        .onChange(of: model.searchQuery) { _, _ in model.search(authManager: authManager) }
        .toolbar {
            if tab != .recordings, model.searchQuery.isEmpty, model.hasFavorites || model.favoritesOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $model.favoritesOnly.animation(DT.Animation.fast)) {
                        Label("Favorites Only", systemImage: model.favoritesOnly ? "star.fill" : "star")
                    }
                    .toggleStyle(.button)
                }
            }
        }
        .task { await model.loadChannels(authManager: authManager) }
        .task { await model.loadRecordings(authManager: authManager) }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
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

    private var tabPicker: some View {
        Picker("Live TV", selection: $tab) {
            ForEach(LiveTVTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.vertical, 8)
    }
}

// MARK: - Programme sheet and player

extension View {
    /// The programme sheet, the player for a channel or recording, and the recording error,
    /// for the Live TV screen and for Live TV results in Browse's search.
    func liveTVPresentations(model: LiveTVModel, onPlayerClosed: @escaping () -> Void = {}) -> some View {
        modifier(LiveTVPresentations(model: model, onPlayerClosed: onPlayerClosed))
    }
}

private struct LiveTVPresentations: ViewModifier {
    @Bindable var model: LiveTVModel
    let onPlayerClosed: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.selectedProgram) { program in
                LiveTVProgramSheet(model: model, program: program)
            }
            .fullScreenCover(item: $model.playbackRequest, onDismiss: {
                PlayQueue.clear()
                onPlayerClosed()
            }) { request in
                PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                    PlayerView.keepOrientationOnNextDisappear = true
                    model.playbackRequest = MediaDetailView.PlaybackRequest(item: next, startTicks: 0)
                }
                .id(request.item.id)
            }
            .alert("Live TV", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.actionError ?? "")
            }
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
            TimelineView(.periodic(from: .now, by: 30)) { context in
                List {
                    ForEach(model.visibleChannels) { channel in
                        channelRow(channel, now: context.date)
                    }
                    if model.canLoadMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await model.loadChannels(authManager: authManager) }
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

/// Play, favourite and what's on, for a channel's context menu.
struct LiveTVChannelMenu: View {
    let model: LiveTVModel
    let channel: LiveTVChannel

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Button { model.play(channel) } label: { Label("Watch", systemImage: "play.fill") }
        if let program = channel.currentProgram {
            Button { model.selectedProgram = program } label: { Label("About This Programme", systemImage: "info.circle") }
        }
        Button { model.toggleFavorite(channel, authManager: authManager) } label: {
            Label(channel.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: channel.isFavorite ? "star.slash" : "star")
        }
    }
}

struct LiveTVChannelRow: View {
    let channel: LiveTVChannel
    let now: Date
    /// Off when the server has no guide, so rows don't all say there's no information.
    var showsGuide = true

    var body: some View {
        HStack(spacing: 14) {
            ChannelLogo(channel: channel)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let number = channel.number {
                        Text(number)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    Text(channel.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                    if channel.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(DT.Color.palette("F59E0B"))
                            .accessibilityLabel("Favorite")
                    }
                }

                if let program = channel.currentProgram, program.isAiring(at: now) {
                    HStack(spacing: 6) {
                        Text(program.name)
                            .font(.system(.footnote))
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineLimit(1)
                        RecordingMark(program: program).font(.caption2)
                    }
                    HStack(spacing: 8) {
                        ProgramProgressLine(program: program, now: now)
                            .frame(maxWidth: 140)
                        Text(program.timeRange)
                            .font(.system(.caption2))
                            .monospacedDigit()
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineLimit(1)
                    }
                } else if showsGuide {
                    Text("No programme information")
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(DT.Color.accent)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays the channel")
    }
}

struct LiveTVEmptyChannels: View {
    let favoritesOnly: Bool

    var body: some View {
        if favoritesOnly {
            ContentUnavailableView("No Favorite Channels", systemImage: "star",
                                   description: Text("Swipe right on a channel, or touch and hold it, to add it to your favorites."))
        } else {
            ContentUnavailableView("No Channels", systemImage: "antenna.radiowaves.left.and.right",
                                   description: Text("Your server hasn't found any channels. Add a tuner or an M3U playlist in the Jellyfin dashboard under Live TV."))
        }
    }
}
