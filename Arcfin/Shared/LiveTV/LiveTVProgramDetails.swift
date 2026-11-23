// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// What a programme is, when it's on, and Watch, Record and Record Series: the body of each
/// platform's programme sheet. `dismiss` closes the sheet before playing.
struct LiveTVProgramDetails: View {
    let model: LiveTVModel
    let program: LiveTVProgram
    let dismiss: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @State private var isWorking = false
    /// Set while the series options show, before the series is recorded.
    @State private var seriesOptions: LiveTVSeriesOptions?
    @State private var confirmingCancel = false
    @State private var confirmingStopSeries = false

    /// The programme with any timer change made while the sheet is open.
    private var current: LiveTVProgram { model.selectedProgram?.id == program.id ? model.selectedProgram ?? program : program }
    private var channel: LiveTVChannel? { model.channel(for: current) }
    private var hasEnded: Bool { current.endDate <= .now }

    /// The sheet's title: the channel it's on.
    static func title(for program: LiveTVProgram, in model: LiveTVModel) -> String {
        model.channel(for: program)?.name ?? program.channelName ?? ""
    }

    var body: some View {
        if PlatformMetrics.sheetsSideBySide {
            // Apple TV: what's on, on the left; what to do with it, on the right.
            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    overview
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions
                    .task { await model.loadReminders() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .loginFocusSection()
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                    .task { await model.loadReminders() }
                overview
            }
        }
    }

    @ViewBuilder
    private var overview: some View {
        if let overview = current.overview, !overview.isEmpty {
            Text(overview)
                .font(DT.Font.body)
                .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            if let url = mediaRepo.primaryImageURL(itemID: current.id, tag: current.primaryImageTag, fillWidth: 300) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: DT.Color.backgroundTertiary
                    }
                }
                .frame(width: 96 * DT.Scale.font, height: 96 * DT.Scale.font * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
                .accessibilityHidden(true)
            } else if let channel {
                ChannelLogo(channel: channel, size: CGSize(width: 96 * DT.Scale.font, height: 54 * DT.Scale.font))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(current.name)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                if let detail = current.detailLine {
                    Text(detail)
                        .font(.system(.subheadline))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                HStack(spacing: 6) {
                    if current.isAiring() { LiveBadge() }
                    Text(current.startDate.formatted(.dateTime.weekday(.wide).hour().minute()) + " – "
                         + current.endDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(.caption, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(DT.Color.textSecondary)
                    if let rating = current.officialRating {
                        Text(rating)
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(DT.Color.textSecondary, lineWidth: 1))
                    }
                }
                if current.isAiring() {
                    TimelineView(.everyMinute) { context in
                        ProgramProgressLine(program: current, now: context.date)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if current.isAiring(), let channel {
                Button {
                    dismiss()
                    // Opening the player while the sheet is still closing can drop it, where
                    // both are full-screen covers (Apple TV).
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        model.play(channel)
                    }
                } label: {
                    Label("Watch Now", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)
                .controlSize(.large)
            }

            if NotificationManager.supportsReminders, current.startDate > .now {
                let isSet = model.reminders.contains(current.id)
                Button {
                    Task { await model.toggleReminder(for: current) }
                } label: {
                    Label(isSet ? "Reminder Set" : "Remind Me", systemImage: isSet ? "bell.fill" : "bell")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(isSet ? DT.Color.accent : nil)
                .controlSize(.large)
                .accessibilityHint(isSet ? "Cancels the reminder" : "Sends a notification just before it starts")
            }

            if !hasEnded, ProfileRules.shared.canRecordLiveTV {
                HStack(spacing: 10) {
                    recordButton
                    if current.isSeries { seriesButton }
                }
                .disabled(isWorking)
                if let binding = Binding($seriesOptions) {
                    seriesOptionsPanel(binding)
                }
            }
        }
        .alert(current.isAiring() ? "Stop recording \(current.name)?" : "Cancel the recording of \(current.name)?",
               isPresented: $confirmingCancel) {
            Button(current.isAiring() ? "Stop Recording" : "Cancel Recording", role: .destructive) {
                run { await model.cancelRecording(of: current, series: false, authManager: authManager) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Stop recording \(current.name)?", isPresented: $confirmingStopSeries) {
            Button("Stop Recording Series", role: .destructive) {
                run { await model.cancelRecording(of: current, series: true, authManager: authManager) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Episodes already recorded stay on your server.")
        }
    }

    private var recordButton: some View {
        Button {
            if current.timerId != nil {
                confirmingCancel = true
            } else {
                run { await model.record(current, series: false, authManager: authManager) }
            }
        } label: {
            Label(current.timerId != nil ? "Cancel Recording" : "Record",
                  systemImage: current.timerId != nil ? "record.circle.fill" : "record.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(current.timerId != nil ? DT.Color.palette("F43F5E") : nil)
        .controlSize(.large)
    }

    private var seriesButton: some View {
        Button {
            if current.seriesTimerId != nil {
                confirmingStopSeries = true
            } else if seriesOptions == nil {
                // The options come first, with the server's defaults filled in.
                run { seriesOptions = await model.seriesDefaults(for: current, authManager: authManager) }
            } else {
                seriesOptions = nil
            }
        } label: {
            Label(current.seriesTimerId != nil ? "Stop Series" : "Record Series",
                  systemImage: current.seriesTimerId != nil ? "repeat.circle.fill" : "repeat.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(current.seriesTimerId != nil ? DT.Color.palette("F43F5E") : nil)
        .controlSize(.large)
    }

    private func seriesOptionsPanel(_ options: Binding<LiveTVSeriesOptions>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LiveTVSeriesOptionsForm(options: options)
            Button {
                let chosen = options.wrappedValue
                run {
                    await model.record(current, series: true, options: chosen, authManager: authManager)
                    seriesOptions = nil
                }
            } label: {
                Label("Record Every Episode", systemImage: "repeat.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(DT.Color.accent)
            .foregroundStyle(DT.Color.onAccent)
            .controlSize(.large)
            .disabled(isWorking)
        }
        .padding(16)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
    }

    private func run(_ work: @escaping () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }
}
