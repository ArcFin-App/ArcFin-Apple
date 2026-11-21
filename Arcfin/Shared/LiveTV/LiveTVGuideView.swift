// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The programme grid: channels down the side, time across the top, scrolling both ways.
/// The channel column and the time row stay put while the grid moves under them.
struct LiveTVGuideView: View {
    let model: LiveTVModel

    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var offsetX: CGFloat = 0
    @State private var position = ScrollPosition()

    private var isWide: Bool { horizontalSizeClass == .regular }
    // Scaled up on Apple TV, where the grid is read from across the room.
    private var channelWidth: CGFloat { (isWide ? 132 : 84) * DT.Scale.font }
    private var rowHeight: CGFloat { (isWide ? 76 : 68) * DT.Scale.font }
    private let headerHeight: CGFloat = 34 * DT.Scale.font
    private var pointsPerMinute: CGFloat { (isWide ? 7 : 5) * DT.Scale.font }
    private var gridWidth: CGFloat { CGFloat(LiveTVModel.guideHours * 60) * pointsPerMinute }

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
        } else if model.hasGuide == false {
            ContentUnavailableView("No Guide", systemImage: "calendar.badge.exclamationmark",
                                   description: Text("Your server has channels but no programme guide. Add a listings provider, such as an XMLTV file or Schedules Direct, in the Jellyfin dashboard under Live TV."))
        } else {
            VStack(spacing: 0) {
                if model.hasGuide == true { categoryBar }
                if model.isLoadingCategory {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.categoryFailed {
                    ContentUnavailableView {
                        Label("Couldn't Load Channels", systemImage: "antenna.radiowaves.left.and.right.slash")
                    } description: {
                        Text("Check your connection and try again.")
                    } actions: {
                        Button("Try Again") { model.retryCategory(authManager: authManager) }
                    }
                } else if model.guideChannels.isEmpty, let category = model.guideCategory {
                    ContentUnavailableView("Nothing Found", systemImage: category.systemImage,
                                           description: Text("Nothing of this kind is in the guide right now."))
                } else {
                    TimelineView(.everyMinute) { context in
                        grid(now: context.date)
                    }
                }
            }
        }
    }

    /// All, then each kind of programme the guide can be narrowed to.
    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8 * DT.Scale.font) {
                chip(title: String(localized: "All"), systemImage: "square.grid.2x2", category: nil)
                ForEach(LiveTVCategory.allCases) { category in
                    chip(title: category.title, systemImage: category.systemImage, category: category)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        .tvFocusSection()
    }

    private func chip(title: String, systemImage: String, category: LiveTVCategory?) -> some View {
        let selected = model.guideCategory == category
        return Button { model.selectCategory(category, authManager: authManager) } label: {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(selected ? DT.Color.onAccent : DT.Color.textPrimary)
                .padding(.horizontal, 14 * DT.Scale.font)
                .padding(.vertical, 7 * DT.Scale.font)
                .background(selected ? DT.Color.accent : DT.Color.backgroundSecondary, in: Capsule())
        }
        .arcfinPlainButton(cornerRadius: 40, prominent: false)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func grid(now: Date) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(model.guideChannels) { channel in
                        row(for: channel, now: now)
                    }
                } header: {
                    timeHeader
                }
            }
            .frame(width: channelWidth + gridWidth, alignment: .leading)
            .overlay(alignment: .topLeading) { nowLine(now: now) }
        }
        .scrollPosition($position)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x + $0.contentInsets.leading } action: { _, x in
            offsetX = max(x, 0)
        }
        .overlay(alignment: .bottomTrailing) {
            if offsetX > 200 {
                Button {
                    withAnimation(DT.Animation.standard) { position.scrollTo(x: 0) }
                } label: {
                    Label("Now", systemImage: "clock.arrow.circlepath")
                        .font(.system(.subheadline, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .padding(DT.Spacing.pagePad)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(DT.Animation.fast, value: offsetX > 200)
    }

    // MARK: - Time row

    private var timeHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: channelWidth)
            ForEach(0..<(LiveTVModel.guideHours * 2), id: \.self) { slot in
                let time = model.guideStart.addingTimeInterval(Double(slot) * 1800)
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.leading, 8)
                    .frame(width: 30 * pointsPerMinute, height: headerHeight, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(DT.Color.textPrimary.opacity(0.12)).frame(width: 1, height: 10)
                    }
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Text(model.guideStart.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
                .frame(width: channelWidth, height: headerHeight)
                .background(.regularMaterial)
                .offset(x: offsetX)
        }
    }

    // MARK: - Rows

    private func row(for channel: LiveTVChannel, now: Date) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: channelWidth)
            programStrip(for: channel, now: now)
        }
        .frame(height: rowHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DT.Color.textPrimary.opacity(0.06)).frame(height: 1)
        }
        .overlay(alignment: .leading) {
            channelCell(channel)
                .offset(x: offsetX)
        }
        .task(id: model.guideGeneration) {
            await model.loadGuide(around: channel, authManager: authManager)
        }
        .onAppear {
            Task { await model.loadMoreIfNeeded(after: channel, authManager: authManager) }
        }
    }

    private func channelCell(_ channel: LiveTVChannel) -> some View {
        Button { model.play(channel) } label: {
            VStack(spacing: 4) {
                ChannelLogo(channel: channel, size: CGSize(width: channelWidth - 24, height: rowHeight - 34))
                Text(channel.number ?? channel.name)
                    .font(.system(.caption2, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: channelWidth, height: rowHeight)
            .background(DT.Color.backgroundPrimary)
            .overlay(alignment: .trailing) {
                Rectangle().fill(DT.Color.textPrimary.opacity(0.08)).frame(width: 1)
            }
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.sm, prominent: false)
        .contextMenu { LiveTVChannelMenu(model: model, channel: channel) }
        .accessibilityLabel(channel.number.map { "\($0) \(channel.name)" } ?? channel.name)
        .accessibilityHint("Plays the channel")
    }

    @ViewBuilder
    private func programStrip(for channel: LiveTVChannel, now: Date) -> some View {
        let start = model.guideStart
        let end = model.guideEnd
        ZStack(alignment: .leading) {
            if let programs = model.guidePrograms(for: channel) {
                if programs.isEmpty {
                    placeholder("No programme information", width: gridWidth)
                }
                ForEach(programs) { program in
                    let from = max(program.startDate, start)
                    let to = min(program.endDate, end)
                    if to > from {
                        GuideProgramCell(program: program, now: now) { model.selectedProgram = program }
                            .frame(width: max(CGFloat(to.timeIntervalSince(from) / 60) * pointsPerMinute, 1),
                                   height: rowHeight)
                            .offset(x: CGFloat(from.timeIntervalSince(start) / 60) * pointsPerMinute)
                    }
                }
            } else {
                placeholder(nil, width: gridWidth)
            }
        }
        .frame(width: gridWidth, height: rowHeight, alignment: .leading)
    }

    private func placeholder(_ text: LocalizedStringKey?, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
            .fill(DT.Color.backgroundSecondary.opacity(0.6))
            .overlay(alignment: .leading) {
                if let text {
                    Text(text)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                        .padding(.leading, 12)
                        .offset(x: offsetX)
                }
            }
            .padding(3)
            .frame(width: width)
    }

    private func nowLine(now: Date) -> some View {
        let x = channelWidth + CGFloat(now.timeIntervalSince(model.guideStart) / 60) * pointsPerMinute
        return Rectangle()
            .fill(DT.Color.accent)
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .padding(.top, headerHeight - 6)
            .offset(x: x)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// One programme in the guide: its name, time and any New/Live mark, lit when it's on now.
private struct GuideProgramCell: View {
    let program: LiveTVProgram
    let now: Date
    let action: () -> Void

    private var isAiring: Bool { program.isAiring(at: now) }
    private var hasEnded: Bool { program.endDate <= now }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    RecordingMark(program: program).font(.caption2)
                    Text(program.name)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary.opacity(hasEnded ? 0.5 : 1))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let highlight = program.highlight {
                        Text(highlight)
                            .font(.system(.caption2, weight: .bold))
                            .foregroundStyle(DT.Color.accent)
                    }
                    Text(program.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(.caption2))
                        .monospacedDigit()
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                    .fill(isAiring ? DT.Color.accentSubtle : DT.Color.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                    .strokeBorder(isAiring ? DT.Color.accent.opacity(0.5) : DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
            .padding(3)
            .contentShape(Rectangle())
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.sm, prominent: false)
        .accessibilityLabel("\(program.name), \(program.timeRange)")
        .accessibilityHint("Shows details and recording options")
    }
}
