// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Channels and programmes matching the Live TV screen's search: every match, channels first.
struct LiveTVSearchResults: View {
    let model: LiveTVModel

    var body: some View {
        if model.searchQuery.isEmpty {
            Color.clear
        } else if model.isSearching, !model.hasSearchResults {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.hasSearchResults {
            ContentUnavailableView.search(text: model.searchQuery)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DT.Spacing.xl) {
                    if !model.searchChannels.isEmpty {
                        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                            SearchSectionHeader(title: String(localized: "Channels"), count: model.searchChannels.count)
                            LiveTVSearchRows(model: model, channels: model.searchChannels, programs: [])
                                .padding(.horizontal, DT.Spacing.pagePad)
                        }
                    }
                    if !model.searchPrograms.isEmpty {
                        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                            SearchSectionHeader(title: String(localized: "Programmes"), count: model.searchPrograms.count)
                            LiveTVSearchRows(model: model, channels: [], programs: model.searchPrograms)
                                .padding(.horizontal, DT.Spacing.pagePad)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
    }
}

/// Live TV in Browse's search: a few channels and programmes below the library results and
/// above Discover. Laid out like the other sections, with the antenna marking it as live.
struct LiveTVSearchSection: View {
    let model: LiveTVModel
    static let shownPerKind = 4

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityHidden(true)
                Text("Live TV")
                    .font(DT.Font.sectionTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Text("\(model.searchChannels.count + model.searchPrograms.count)")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                Spacer(minLength: 0)
                if model.isSearching { ProgressView() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, DT.Spacing.pagePad)

            LiveTVSearchRows(model: model,
                             channels: Array(model.searchChannels.prefix(Self.shownPerKind)),
                             programs: Array(model.searchPrograms.prefix(Self.shownPerKind)))
                .padding(.horizontal, DT.Spacing.pagePad)
        }
    }
}

/// Channel rows play the channel; programme rows open the programme's details.
private struct LiveTVSearchRows: View {
    let model: LiveTVModel
    let channels: [LiveTVChannel]
    let programs: [LiveTVProgram]

    /// Search results are short-lived; they read the time once rather than ticking.
    var body: some View {
        let now = Date()
        VStack(spacing: 0) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                if index > 0 { divider }
                Button { model.play(channel, among: model.searchChannels) } label: {
                    LiveTVChannelRow(channel: channel, now: now, showsGuide: model.hasGuide == true)
                        .padding(.vertical, 8)
                }
                .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
                .contextMenu { LiveTVChannelMenu(model: model, channel: channel) }
            }
            ForEach(Array(programs.enumerated()), id: \.element.id) { index, program in
                if index > 0 || !channels.isEmpty { divider }
                Button { model.selectedProgram = program } label: {
                    LiveTVProgramRow(program: program, now: now)
                        .padding(.vertical, 8)
                }
                .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
            }
        }
    }

    private var divider: some View {
        Divider().overlay(DT.Color.textPrimary.opacity(0.06)).padding(.leading, 86)
    }
}

/// A programme found by search: when it's on, what it is and which channel.
struct LiveTVProgramRow: View {
    let program: LiveTVProgram
    let now: Date

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                if program.isAiring(at: now) {
                    LiveBadge()
                } else {
                    Text(program.startDate.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    Text(program.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DT.Color.textPrimary)
                }
            }
            .frame(width: 72 * DT.Scale.font)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(program.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                    RecordingMark(program: program).font(.caption2)
                }
                Text([program.channelName, program.detailLine].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.footnote))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
                if program.isAiring(at: now) {
                    ProgramProgressLine(program: program, now: now).frame(maxWidth: 140)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(DT.Color.textSecondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details and recording options")
    }
}
