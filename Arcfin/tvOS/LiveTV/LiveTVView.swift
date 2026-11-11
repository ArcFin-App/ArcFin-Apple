// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The Live TV library from Browse: channels, the guide and recordings, switched with a
/// segmented control at the top that the remote reaches by moving up.
struct LiveTVView: View {
    let library: JellyfinLibrary

    @Environment(AuthManager.self) private var authManager
    @State private var model = LiveTVModel()
    @SceneStorage("liveTVTab") private var tab: LiveTVTab = .channels

    var body: some View {
        // One slim row of controls: on Apple TV a search field stays on screen as a large bar,
        // and with a title row above it the two took a third of the screen, leaving the list
        // to scroll in what was left. Search opens its own screen instead.
        VStack(spacing: 0) {
            header
            Group {
                switch tab {
                case .channels: LiveTVChannelsList(model: model)
                case .guide: LiveTVGuideView(model: model)
                case .recordings: LiveTVRecordingsView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .screenBackground()
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

    private var header: some View {
        HStack(spacing: 32) {
            Text(library.name)
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(DT.Color.textSecondary)
                .frame(minWidth: 240, alignment: .leading)
            Spacer()
            Picker("Live TV", selection: $tab) {
                ForEach(LiveTVTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 820)
            Spacer()
            NavigationLink {
                LiveTVSearchScreen(model: model)
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Search Channels and Programmes")
            if tab != .recordings, model.hasFavorites || model.favoritesOnly {
                Button {
                    withAnimation(DT.Animation.fast) { model.favoritesOnly.toggle() }
                } label: {
                    Label("Favorites Only", systemImage: model.favoritesOnly ? "star.fill" : "star")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(model.favoritesOnly ? DT.Color.palette("F59E0B") : DT.Color.textPrimary)
                }
                .accessibilityLabel("Favorites Only")
            }
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 12)
        .focusSection()
    }
}

/// Search for channels and programmes, on its own screen so the field doesn't sit over the
/// channel list.
private struct LiveTVSearchScreen: View {
    @Bindable var model: LiveTVModel

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        LiveTVSearchResults(model: model)
            .screenBackground()
            .searchable(text: $model.searchQuery, prompt: "Channels and programmes")
            .onChange(of: model.searchQuery) { _, _ in model.search(authManager: authManager) }
            .onDisappear { model.searchQuery = "" }
    }
}

// MARK: - Programme panel and player

extension View {
    /// The programme panel, the player for a channel or recording, and the recording error,
    /// for the Live TV screen and for Live TV results in Search.
    func liveTVPresentations(model: LiveTVModel, onPlayerClosed: @escaping () -> Void = {}) -> some View {
        modifier(LiveTVPresentations(model: model, onPlayerClosed: onPlayerClosed))
    }
}

private struct LiveTVPresentations: ViewModifier {
    @Bindable var model: LiveTVModel
    let onPlayerClosed: () -> Void

    func body(content: Content) -> some View {
        content
            .appSheet(item: $model.selectedProgram) { program in
                ScrollView {
                    LiveTVProgramDetails(model: model, program: program) { model.selectedProgram = nil }
                        .padding(.vertical, 24)
                }
            }
            .appSheet(item: $model.editingSeriesTimer) { seriesTimer in
                ScrollView {
                    LiveTVSeriesEditor(model: model, seriesTimer: seriesTimer) { model.editingSeriesTimer = nil }
                        .padding(.vertical, 24)
                }
            }
            .fullScreenCover(item: $model.playbackRequest, onDismiss: {
                PlayQueue.clear()
                onPlayerClosed()
            }) { request in
                PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
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
            TimelineView(.everyMinute) { context in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.visibleChannels) { channel in
                            channelRow(channel, now: context.date)
                        }
                        if model.canLoadMore {
                            ProgressView().padding(.vertical, 24)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 24)
                }
                // Clipped, so rows scrolling up stay under the controls row instead of
                // sliding over it; the padding above leaves room for the focus ring.
            }
        }
    }

    private func channelRow(_ channel: LiveTVChannel, now: Date) -> some View {
        Button { model.play(channel) } label: {
            LiveTVChannelRow(channel: channel, now: now, showsGuide: model.hasGuide != false)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.lg, prominent: false)
        // A long press, as the remote's way to reach a context menu.
        .contextMenu {
            LiveTVChannelMenu(model: model, channel: channel)
        }
        .onAppear {
            Task { await model.loadMoreIfNeeded(after: channel, authManager: authManager) }
        }
    }
}
