// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import WidgetKit
import SwiftUI
import UIKit
import LiveActivityKit
import ActivityKit

private enum WidgetDT {
    static let accent = Color(red: 0x06 / 255, green: 0xB6 / 255, blue: 0xD4 / 255)
    static let accentDeep = Color(red: 0x03 / 255, green: 0x7C / 255, blue: 0x93 / 255)
    static let success = Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
    static let paused = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    static let background = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0F / 255)
    static let textSecondary = Color(white: 1, opacity: 0.7)
}

private typealias DownloadState = DownloadActivityAttributes.ContentState

private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func formattedSpeed(_ bytesPerSecond: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
}

/// "About 4 min left", rounded the way people say it.
private func timeLeft(_ seconds: Double) -> String {
    if seconds < 60 { return "Less than a minute left" }
    let minutes = Int((seconds / 60).rounded())
    if minutes < 60 { return "About \(minutes) min left" }
    let hours = minutes / 60, rest = minutes % 60
    return rest == 0 ? "About \(hours) hr left" : "About \(hours) hr \(rest) min left"
}

private func percent(_ state: DownloadState) -> String {
    "\(Int((state.fractionComplete * 100).rounded(.down)))%"
}

private func statusColor(_ state: DownloadState) -> Color {
    if state.isFinished { return WidgetDT.success }
    return state.isPaused == true ? WidgetDT.paused : WidgetDT.accent
}

/// What's happening, in one short line: "Downloading 2 of 6", "Paused", "Ready to Watch".
private func statusLine(_ state: DownloadState) -> String {
    if state.isFinished {
        return state.totalCount > 1 ? "\(state.totalCount) Ready to Watch" : "Ready to Watch"
    }
    let base = state.isPaused == true ? "Paused" : "Downloading"
    return state.totalCount > 1 ? "\(base) · \(state.position) of \(state.totalCount)" : base
}

// MARK: - Pieces

private struct Poster: View {
    let state: DownloadState
    let width: CGFloat

    var body: some View {
        Group {
            if let data = state.posterImageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [WidgetDT.accentDeep, WidgetDT.accent],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "film")
                        .font(.system(size: width * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.16, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A ring that fills as the title downloads; a checkmark once everything is done.
private struct ProgressRing: View {
    let state: DownloadState
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(statusColor(state).opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: state.isFinished ? 1 : max(state.fractionComplete, 0.02))
                .stroke(statusColor(state), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: state.isFinished ? "checkmark" : (state.isPaused == true ? "pause.fill" : "arrow.down"))
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(statusColor(state))
        }
        .accessibilityElement()
        .accessibilityLabel(statusLine(state))
        .accessibilityValue(state.isFinished ? "" : percent(state))
    }
}

private struct ProgressBar: View {
    let state: DownloadState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(state.isPaused == true
                          ? AnyShapeStyle(WidgetDT.paused)
                          : AnyShapeStyle(LinearGradient(colors: [WidgetDT.accentDeep, WidgetDT.accent],
                                                         startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(geo.size.width * state.fractionComplete, 6))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Size so far and, while moving, the speed and time left; why it's stopped when paused.
private struct TransferLine: View {
    let state: DownloadState

    var body: some View {
        HStack(spacing: 6) {
            if state.totalBytes > 0 {
                Text("\(formattedBytes(state.bytesWritten)) of \(formattedBytes(state.totalBytes))")
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            if state.isPaused == true {
                Text("Open Arcfin to resume")
            } else if let seconds = state.secondsRemaining {
                Text(timeLeft(seconds))
            } else if state.bytesPerSecond > 0 {
                Text(formattedSpeed(state.bytesPerSecond))
            }
        }
        .font(.system(.footnote, weight: .medium))
        .foregroundStyle(WidgetDT.textSecondary)
        .lineLimit(1)
    }
}

/// The compact trailing side: the percentage, or nothing where the Dynamic Island is
/// narrow, leaving the ring alone on the leading side.
private struct CompactTrailing: View {
    let state: DownloadState

    var body: some View {
        if #available(iOS 27.0, *) {
            LimitedWidthAware(state: state)
        } else {
            label
        }
    }

    fileprivate var label: some View {
        Text(state.isFinished ? "Done" : percent(state))
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(statusColor(state))
    }

    @available(iOS 27.0, *)
    private struct LimitedWidthAware: View {
        let state: DownloadState
        @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited

        var body: some View {
            if !isLimited { CompactTrailing(state: state).label }
        }
    }
}

// MARK: - Live Activity

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(WidgetDT.background)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "arcfin://downloads"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Poster(state: state, width: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.isFinished ? "Done" : percent(state))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(statusColor(state))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusLine(state))
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(statusColor(state))
                        Text(state.currentItemTitle)
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let episode = state.episodeLabel {
                            Text(episode)
                                .font(.system(.footnote, weight: .medium))
                                .foregroundStyle(WidgetDT.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !state.isFinished {
                        VStack(spacing: 6) {
                            ProgressBar(state: state)
                            TransferLine(state: state)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    }
                }
            } compactLeading: {
                ProgressRing(state: state)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                CompactTrailing(state: state)
            } minimal: {
                ProgressRing(state: state, lineWidth: 2.5)
                    .frame(width: 20, height: 20)
            }
            .keylineTint(WidgetDT.accent)
            .widgetURL(URL(string: "arcfin://downloads"))
        }
    }
}

/// The Lock Screen and StandBy banner, laid out like the expanded Dynamic Island so the two
/// read as one design: poster, status, title and percentage, then the bar and what's left.
private struct LockScreenView: View {
    let state: DownloadState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Poster(state: state, width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Label {
                        Text(statusLine(state))
                    } icon: {
                        Image(systemName: state.isFinished ? "checkmark.circle.fill"
                              : (state.isPaused == true ? "pause.circle.fill" : "arrow.down.circle.fill"))
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(statusColor(state))
                    Text(state.currentItemTitle)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    subtitle
                }
                Spacer(minLength: 8)
                if !state.isFinished {
                    Text(percent(state))
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                }
            }
            if !state.isFinished {
                ProgressBar(state: state)
                TransferLine(state: state)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var subtitle: some View {
        let parts = [state.episodeLabel,
                     state.isFinished ? "Ready to watch offline" : state.nextItemTitle.map { "Up next: \($0)" }]
            .compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(WidgetDT.textSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Previews

private extension DownloadState {
    static let downloading = DownloadState(
        currentItemTitle: "The Long Way Home", bytesWritten: 1_240_000_000, totalBytes: 3_400_000_000,
        bytesPerSecond: 12_600_000, completedCount: 1, totalCount: 6, seasonNumber: 2, episodeNumber: 5,
        nextItemTitle: "Crossing Over")
    static let paused = DownloadState(
        currentItemTitle: "The Long Way Home", bytesWritten: 1_240_000_000, totalBytes: 3_400_000_000,
        bytesPerSecond: 0, completedCount: 1, totalCount: 6, seasonNumber: 2, episodeNumber: 5, isPaused: true)
    static let finished = DownloadState(
        currentItemTitle: "Crossing Over", bytesWritten: 3_400_000_000, totalBytes: 3_400_000_000,
        bytesPerSecond: 0, completedCount: 6, totalCount: 6, isFinished: true, seasonNumber: 2, episodeNumber: 6)
}

#Preview("Lock Screen", as: .content, using: DownloadActivityAttributes()) {
    DownloadLiveActivity()
} contentStates: {
    DownloadState.downloading
    DownloadState.paused
    DownloadState.finished
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: DownloadActivityAttributes()) {
    DownloadLiveActivity()
} contentStates: {
    DownloadState.downloading
    DownloadState.paused
}

#Preview("Compact", as: .dynamicIsland(.compact), using: DownloadActivityAttributes()) {
    DownloadLiveActivity()
} contentStates: {
    DownloadState.downloading
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: DownloadActivityAttributes()) {
    DownloadLiveActivity()
} contentStates: {
    DownloadState.downloading
}
#endif
