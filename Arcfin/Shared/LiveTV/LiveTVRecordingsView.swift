// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Recordings to watch, what's recording now, what's scheduled and the series being recorded.
struct LiveTVRecordingsView: View {
    let model: LiveTVModel

    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        horizontalSizeClass == .regular
            ? [GridItem(.adaptive(minimum: 240 * DT.Scale.font), spacing: 12 * DT.Scale.font)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    @State private var deletingRecording: LiveTVRecording?

    private var isEmpty: Bool {
        model.recordings.isEmpty && model.timers.isEmpty && model.seriesTimers.isEmpty
    }

    var body: some View {
        if model.isLoadingRecordings, isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            ContentUnavailableView("No Recordings", systemImage: "record.circle",
                                   description: ProfileRules.shared.canRecordLiveTV
                                       ? Text("Pick a programme in the guide to record it, or record every episode of a series.")
                                       : Text("Recordings on your server show up here."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !model.activeTimers.isEmpty {
                        section("Recording Now") {
                            ForEach(model.activeTimers) { timer in
                                LiveTVTimerRow(timer: timer, isActive: true) {
                                    Task { await model.cancel(timer, authManager: authManager) }
                                }
                            }
                        }
                    }

                    if !model.recordings.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            LibrarySectionHeader(title: "Recordings")
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(model.recordings) { recording in
                                    Button { model.play(recording) } label: {
                                        LiveTVRecordingCard(recording: recording)
                                    }
                                    .arcfinPlainButton(cornerRadius: DT.Radius.card, prominent: false)
                                    .contextMenu {
                                        Button { model.play(recording) } label: { Label("Play", systemImage: "play.fill") }
                                        if ProfileRules.shared.canRecordLiveTV {
                                            Button(role: .destructive) { deletingRecording = recording } label: {
                                                Label("Delete Recording", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !model.scheduledTimers.isEmpty {
                        section("Scheduled") {
                            ForEach(model.scheduledTimers) { timer in
                                LiveTVTimerRow(timer: timer, isActive: false) {
                                    Task { await model.cancel(timer, authManager: authManager) }
                                }
                            }
                        }
                    }

                    if !model.seriesTimers.isEmpty {
                        section("Series") {
                            ForEach(model.seriesTimers) { seriesTimer in
                                LiveTVSeriesTimerRow(seriesTimer: seriesTimer) {
                                    model.editingSeriesTimer = seriesTimer
                                } cancel: {
                                    Task { await model.cancel(seriesTimer, authManager: authManager) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .refreshable { await model.loadRecordings(authManager: authManager) }
            .confirmationDialog("Delete \(deletingRecording?.item.name ?? "")?",
                                isPresented: Binding(get: { deletingRecording != nil }, set: { if !$0 { deletingRecording = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Recording", role: .destructive) {
                    guard let recording = deletingRecording else { return }
                    Task { await model.delete(recording, authManager: authManager) }
                }
            } message: {
                Text("The recording is removed from your server for everyone.")
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: title)
            VStack(spacing: 0) { content() }
                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                    .stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
        }
    }
}

private struct LiveTVRecordingCard: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let recording: LiveTVRecording

    private var imageURL: URL? {
        mediaRepo.imageURL(for: recording.item, type: .thumb, fillWidth: 500)
            ?? mediaRepo.imageURL(for: recording.item, type: .primary, fillWidth: 500)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    CachedAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: BrowseTileFallback(systemImage: "record.circle")
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if recording.isRecording {
                        LiveBadge().padding(8)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let percent = recording.item.userData?.playedPercentage, percent > 0 {
                        GeometryReader { proxy in
                            Rectangle().fill(DT.Color.progressFill).frame(width: proxy.size.width * percent / 100)
                        }
                        .frame(height: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))

            Text(recording.item.name)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        [recording.channelName, recording.startDate?.formatted(date: .abbreviated, time: .shortened)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

private struct LiveTVTimerRow: View {
    let timer: LiveTVTimer
    let isActive: Bool
    let cancel: () -> Void

    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "record.circle.fill" : "clock")
                .font(.title3)
                .foregroundStyle(isActive ? DT.Color.palette("F43F5E") : DT.Color.accent)
                .symbolEffect(.pulse, isActive: isActive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(.caption))
                    .foregroundStyle(timer.hasProblem ? DT.Color.palette("F43F5E") : DT.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if ProfileRules.shared.canRecordLiveTV {
                Button(role: .destructive) { confirming = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DT.Color.textSecondary)
                        .frame(width: 44, height: 44)
            }
            .arcfinPlainButton(cornerRadius: 22 * DT.Scale.font)
            .accessibilityLabel(isActive ? "Stop Recording" : "Cancel Recording")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .confirmationDialog(isActive ? "Stop recording \(timer.name)?" : "Cancel the recording of \(timer.name)?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button(isActive ? "Stop Recording" : "Cancel Recording", role: .destructive, action: cancel)
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let episode = timer.episodeTitle, !episode.isEmpty { parts.append(episode) }
        if let channel = timer.channelName { parts.append(channel) }
        parts.append((timer.startDate..<timer.endDate).formatted(.interval.weekday().day().hour().minute()))
        if timer.hasProblem { parts.append(String(localized: "Another recording needs the tuner at this time")) }
        return parts.joined(separator: " · ")
    }
}

private struct LiveTVSeriesTimerRow: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let seriesTimer: LiveTVSeriesTimer
    let edit: () -> Void
    let cancel: () -> Void

    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            if ProfileRules.shared.canRecordLiveTV {
                Button(action: edit) { summary }
                    .arcfinPlainButton(cornerRadius: DT.Radius.sm, prominent: false)
                    .accessibilityHint("Changes how the series is recorded")
                Button(role: .destructive) { confirming = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DT.Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .arcfinPlainButton(cornerRadius: 22 * DT.Scale.font)
                .accessibilityLabel("Stop Recording Series")
            } else {
                summary
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .confirmationDialog("Stop recording \(seriesTimer.name)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Stop Recording Series", role: .destructive, action: cancel)
        } message: {
            Text("Episodes already recorded stay on your server.")
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Group {
                if let id = seriesTimer.imageItemId,
                   let url = mediaRepo.primaryImageURL(itemID: id, tag: seriesTimer.imageTag, fillWidth: 120) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: DT.Color.backgroundTertiary
                        }
                    }
                } else {
                    Image(systemName: "repeat.circle.fill")
                        .font(.title2)
                        .foregroundStyle(DT.Color.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DT.Color.backgroundTertiary)
                }
            }
            .frame(width: 40 * DT.Scale.font, height: 56 * DT.Scale.font)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xs, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(seriesTimer.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts: [String] = []
        parts.append(seriesTimer.recordNewOnly ? String(localized: "New episodes") : String(localized: "All episodes"))
        if seriesTimer.recordAnyChannel {
            parts.append(String(localized: "Any channel"))
        } else if let channel = seriesTimer.channelName {
            parts.append(channel)
        }
        return parts.joined(separator: " · ")
    }
}
