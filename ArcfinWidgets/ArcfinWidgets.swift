// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import AppIntents
import WidgetKit
import SwiftUI
import UIKit
import LiveActivityKit
import ActivityKit

private enum WidgetDT {
    static let accent = Color(red: 0xFF / 255, green: 0x6A / 255, blue: 0x4D / 255)
    static let accentDeep = Color(red: 0xE5 / 255, green: 0x53 / 255, blue: 0x3A / 255)
    static let success = Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
    static let paused = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    static let background = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255)
    static let textSecondary = Color(white: 1, opacity: 0.7)
}

private typealias DownloadState = DownloadActivityAttributes.ContentState

private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func formattedSpeed(_ bytesPerSecond: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
}

private func percent(_ state: DownloadState) -> String {
    "\(Int((state.fractionComplete * 100).rounded(.down)))%"
}

private func statusColor(_ state: DownloadState) -> Color {
    if state.isFinished { return WidgetDT.success }
    return state.isPaused == true || state.isWaitingForWiFi == true || state.isWaitingForNetwork == true
        ? WidgetDT.paused : WidgetDT.accent
}

/// What's happening, in one short line: "Downloading 2 of 6", "Paused", "Ready to Watch".
private func statusLine(_ state: DownloadState) -> String {
    if state.isFinished {
        if state.isMusic == true {
            return state.totalCount > 1 ? String(localized: "\(state.totalCount) Ready to Play") : String(localized: "Ready to Play")
        }
        return state.totalCount > 1 ? String(localized: "\(state.totalCount) Ready to Watch") : String(localized: "Ready to Watch")
    }
    if state.isWaitingForNetwork == true { return String(localized: "Waiting for a connection") }
    if state.isWaitingForWiFi == true { return String(localized: "Waiting for Wi-Fi") }
    let base = state.isPaused == true ? String(localized: "Paused") : String(localized: "Downloading")
    return state.totalCount > 1 ? String(localized: "\(base) · \(state.position) of \(state.totalCount)") : base
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
                    Image(systemName: state.isMusic == true ? "music.note" : "film")
                        .font(.system(size: width * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        // An album cover is square; a poster is two by three.
        .frame(width: width, height: state.isMusic == true ? width : width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.16, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A ring that fills as the title downloads (on its own, from the estimate, while the app is
/// suspended); a checkmark once everything is done.
private struct ProgressRing: View {
    let state: DownloadState
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            if let estimate = state.estimate {
                ProgressView(timerInterval: estimate, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(statusColor(state))
            } else {
                Circle().stroke(statusColor(state).opacity(0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: state.isFinished ? 1 : max(state.fractionComplete, 0.02))
                    .stroke(statusColor(state), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: state.isFinished ? "checkmark"
                  : state.isWaitingForNetwork == true ? "wifi.slash"
                  : state.isWaitingForWiFi == true ? "wifi"
                  : (state.isPaused == true ? "pause.fill" : "arrow.down"))
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(statusColor(state))
        }
        .accessibilityElement()
        .accessibilityLabel(statusLine(state))
        .accessibilityValue(state.isFinished ? "" : percent(state))
    }
}

/// Runs off the estimate while there is one, so it keeps moving with the app suspended.
private struct ProgressBar: View {
    let state: DownloadState

    var body: some View {
        Group {
            if let estimate = state.estimate {
                ProgressView(timerInterval: estimate, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: state.fractionComplete)
            }
        }
        .progressViewStyle(.linear)
        .tint(statusColor(state))
        .accessibilityHidden(true)
    }
}

/// The headline figure: time left while it's moving (it counts down on its own), the
/// percentage otherwise, Done at the end.
private struct HeadlineFigure: View {
    let state: DownloadState
    let font: Font

    var body: some View {
        Group {
            if state.isFinished {
                Text("Done")
            } else if let estimate = state.estimate {
                Text(timerInterval: estimate, countsDown: true)
            } else {
                Text(percent(state)).contentTransition(.numericText())
            }
        }
        .font(font)
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

/// The title's size and when it'll finish while it's moving; why it's stopped when paused.
private struct TransferLine: View {
    let state: DownloadState

    var body: some View {
        HStack(spacing: 6) {
            if state.estimate != nil, state.totalBytes > 0 {
                Text(formattedBytes(state.totalBytes))
            } else if state.totalBytes > 0 {
                Text("\(formattedBytes(state.bytesWritten)) of \(formattedBytes(state.totalBytes))")
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            if state.isWaitingForWiFi == true {
                Text("Open Arcfin to use mobile data")
            } else if state.isPaused == true {
                Text("Open Arcfin to resume")
            } else if let estimate = state.estimate {
                Text("Done by \(estimate.upperBound, style: .time)")
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
        HeadlineFigure(state: state, font: .system(.footnote, design: .rounded, weight: .bold))
            .foregroundStyle(statusColor(state))
            .frame(maxWidth: 52)
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
                    HeadlineFigure(state: state, font: .system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(statusColor(state))
                        .frame(maxWidth: 80, alignment: .trailing)
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
                              : state.isWaitingForNetwork == true ? "wifi.slash"
                              : state.isWaitingForWiFi == true ? "wifi"
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
                    HeadlineFigure(state: state, font: .system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 96, alignment: .trailing)
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
                     state.isFinished ? String(localized: "Ready to watch offline")
                        : state.nextItemTitle.map { String(localized: "Up next: \($0)") }]
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
    static let waitingForWiFi = DownloadState(
        currentItemTitle: "The Long Way Home", bytesWritten: 0, totalBytes: 0,
        bytesPerSecond: 0, completedCount: 0, totalCount: 3, seasonNumber: 2, episodeNumber: 5,
        nextItemTitle: "Crossing Over", isWaitingForWiFi: true)
    static let finished = DownloadState(
        currentItemTitle: "Crossing Over", bytesWritten: 3_400_000_000, totalBytes: 3_400_000_000,
        bytesPerSecond: 0, completedCount: 6, totalCount: 6, isFinished: true, seasonNumber: 2, episodeNumber: 6)
}

#Preview("Lock Screen", as: .content, using: DownloadActivityAttributes()) {
    DownloadLiveActivity()
} contentStates: {
    DownloadState.downloading
    DownloadState.paused
    DownloadState.waitingForWiFi
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
// MARK: - Another device playing

private typealias RemoteState = RemotePlaybackActivityAttributes.ContentState

/// Another device playing while this iPhone is its remote (#457): what and where, the
/// position, and play and pause, skip and volume, which run in the app.
struct RemotePlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RemotePlaybackActivityAttributes.self) { context in
            RemoteLockScreenView(state: context.state, sessionID: context.attributes.sessionID)
                .activityBackgroundTint(WidgetDT.background)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(remoteURL(context.attributes.sessionID))
        } dynamicIsland: { context in
            let state = context.state
            let sessionID = context.attributes.sessionID
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RemoteArtwork(state: state, width: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    RemoteTitle(state: state)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        RemoteProgress(state: state)
                        RemoteButtons(state: state, sessionID: sessionID)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "av.remote")
                    .foregroundStyle(WidgetDT.accent)
            } compactTrailing: {
                Image(systemName: state.isPaused ? "pause.fill" : "play.fill")
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "av.remote")
                    .foregroundStyle(WidgetDT.accent)
            }
            .keylineTint(WidgetDT.accent)
            .widgetURL(remoteURL(sessionID))
        }
    }
}

private func remoteURL(_ sessionID: String) -> URL? {
    URL(string: "arcfin://remote/\(sessionID)")
}

private struct RemoteLockScreenView: View {
    let state: RemoteState
    let sessionID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RemoteArtwork(state: state, width: 48)
                RemoteTitle(state: state)
                Spacer(minLength: 0)
            }
            RemoteProgress(state: state)
            RemoteButtons(state: state, sessionID: sessionID)
        }
        .padding(14)
    }
}

private struct RemoteArtwork: View {
    let state: RemoteState
    let width: CGFloat

    var body: some View {
        Group {
            if let data = state.artwork, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [WidgetDT.accentDeep, WidgetDT.background], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct RemoteTitle: View {
    let state: RemoteState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text("Playing on \(state.deviceName)")
            } icon: {
                Image(systemName: "av.remote")
            }
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(WidgetDT.accent)
            .lineLimit(1)
            Text(state.title)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            if let subtitle = state.subtitle {
                Text(subtitle)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(WidgetDT.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Runs by itself while the title plays, so it stays right with the app suspended.
private struct RemoteProgress: View {
    let state: RemoteState

    var body: some View {
        Group {
            if let span = state.playbackSpan {
                ProgressView(timerInterval: span, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            } else {
                ProgressView(value: state.fraction)
            }
        }
        .progressViewStyle(.linear)
        .tint(WidgetDT.accent)
        .labelsHidden()
    }
}

private struct RemoteButtons: View {
    let state: RemoteState
    let sessionID: String

    var body: some View {
        HStack(spacing: 0) {
            button(.volumeDown, "speaker.minus.fill", "Volume Down")
            Spacer()
            button(.skipBackward, "gobackward", "Skip Back")
            Spacer()
            button(.playPause, state.isPaused ? "play.fill" : "pause.fill", state.isPaused ? "Play" : "Pause", large: true)
            Spacer()
            button(.skipForward, "goforward", "Skip Forward")
            Spacer()
            button(.volumeUp, "speaker.plus.fill", "Volume Up")
        }
        .foregroundStyle(.white)
    }

    private func button(_ action: RemotePlaybackAction, _ symbol: String, _ label: LocalizedStringKey, large: Bool = false) -> some View {
        Button(intent: RemotePlaybackIntent(action: action, sessionID: sessionID)) {
            Image(systemName: symbol)
                .font(large ? .title2 : .body)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private extension RemoteState {
    static let playing = RemoteState(
        title: "Crossing Over", subtitle: "The Long Way Home · S2 E5", deviceName: "Living Room",
        isPaused: false, positionSeconds: 1_240, durationSeconds: 2_700, updatedAt: .now, artwork: nil)
    static let paused = RemoteState(
        title: "Crossing Over", subtitle: "The Long Way Home · S2 E5", deviceName: "Living Room",
        isPaused: true, positionSeconds: 1_240, durationSeconds: 2_700, updatedAt: .now, artwork: nil)
}

#Preview("Remote · Lock Screen", as: .content, using: RemotePlaybackActivityAttributes(sessionID: "preview")) {
    RemotePlaybackLiveActivity()
} contentStates: {
    RemoteState.playing
    RemoteState.paused
}

#Preview("Remote · Expanded", as: .dynamicIsland(.expanded), using: RemotePlaybackActivityAttributes(sessionID: "preview")) {
    RemotePlaybackLiveActivity()
} contentStates: {
    RemoteState.playing
}
#endif
