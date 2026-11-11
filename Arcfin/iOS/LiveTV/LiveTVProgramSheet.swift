// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A programme from the guide or a channel: what it is, when it's on, and watch or record it.
struct LiveTVProgramSheet: View {
    let model: LiveTVModel
    let program: LiveTVProgram

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    /// The sheet's programme with any timer change made while it's open.
    private var current: LiveTVProgram { model.selectedProgram?.id == program.id ? model.selectedProgram ?? program : program }
    private var channel: LiveTVChannel? { model.channel(for: current) }
    private var hasEnded: Bool { current.endDate <= .now }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    actions
                    if let overview = current.overview, !overview.isEmpty {
                        Text(overview)
                            .font(DT.Font.body)
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(DT.Spacing.pagePad)
            }
            .screenBackground()
            .navigationTitle(channel?.name ?? current.channelName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                .frame(width: 96, height: 96 * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
                .accessibilityHidden(true)
            } else if let channel {
                ChannelLogo(channel: channel, size: CGSize(width: 96, height: 54))
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
                    TimelineView(.periodic(from: .now, by: 30)) { context in
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
                    model.play(channel)
                } label: {
                    Label("Watch Now", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .controlSize(.large)
            }

            if !hasEnded, ProfileRules.shared.canRecordLiveTV {
                HStack(spacing: 10) {
                    recordButton
                    if current.isSeries { seriesButton }
                }
                .disabled(isWorking)
            }
        }
    }

    private var recordButton: some View {
        Button {
            run { current.timerId != nil
                ? await model.cancelRecording(of: current, series: false, authManager: authManager)
                : await model.record(current, series: false, authManager: authManager) }
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
            run { current.seriesTimerId != nil
                ? await model.cancelRecording(of: current, series: true, authManager: authManager)
                : await model.record(current, series: true, authManager: authManager) }
        } label: {
            Label(current.seriesTimerId != nil ? "Stop Series" : "Record Series",
                  systemImage: current.seriesTimerId != nil ? "repeat.circle.fill" : "repeat.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .tint(current.seriesTimerId != nil ? DT.Color.palette("F43F5E") : nil)
        .controlSize(.large)
    }

    private func run(_ work: @escaping () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }
}
