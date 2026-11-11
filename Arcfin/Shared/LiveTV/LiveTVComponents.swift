// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The red LIVE capsule on the player and on what's airing now.
struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(.caption2, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DT.Color.palette("F43F5E"), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live")
    }
}

/// How far through the programme on a channel is, with its start and end times either side.
/// Shown in the player where a seek bar would be.
struct LiveProgramBar: View {
    let program: LiveTVProgram?

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 10) {
                Text(program?.startDate.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                GeometryReader { proxy in
                    Capsule().fill(.white.opacity(0.25))
                        .overlay(alignment: .leading) {
                            Capsule().fill(DT.Color.accent)
                                .frame(width: proxy.size.width * (program?.progress(at: context.date) ?? 1))
                        }
                }
                .frame(height: 4)
                Text(program?.endDate.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(height: 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(program.map { "\($0.name), \(Self.timeRange($0))" } ?? String(localized: "Live"))
    }

    static func timeRange(_ program: LiveTVProgram) -> String {
        (program.startDate..<program.endDate).formatted(.interval.hour().minute())
    }
}

/// A channel's logo on a dark plate, or its number when it has none.
struct ChannelLogo: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let channel: LiveTVChannel
    var size: CGSize = CGSize(width: 72 * DT.Scale.font, height: 48 * DT.Scale.font)

    var body: some View {
        RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
            .fill(DT.Color.backgroundTertiary)
            .frame(width: size.width, height: size.height)
            .overlay {
                if let url = mediaRepo.primaryImageURL(itemID: channel.id, tag: channel.primaryImageTag, fillWidth: 200) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit().padding(6)
                        default: fallback
                        }
                    }
                } else {
                    fallback
                }
            }
            .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(channel.number ?? String(channel.name.prefix(3)))
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(DT.Color.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(4)
    }
}

/// A thin progress line for what's airing now.
struct ProgramProgressLine: View {
    let program: LiveTVProgram
    let now: Date

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(DT.Color.progressTrack)
                .overlay(alignment: .leading) {
                    Capsule().fill(DT.Color.progressFill)
                        .frame(width: proxy.size.width * program.progress(at: now))
                }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// The record dot shown on a programme that's set to record.
struct RecordingMark: View {
    let program: LiveTVProgram

    var body: some View {
        if program.seriesTimerId != nil {
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, DT.Color.palette("F43F5E"))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "repeat")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                        .offset(x: 3, y: 2)
                }
                .accessibilityLabel("Series recording")
        } else if program.timerId != nil {
            Image(systemName: "record.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, DT.Color.palette("F43F5E"))
                .accessibilityLabel("Recording")
        }
    }
}

extension LiveTVProgram {
    /// "S2 E5 · Episode title" or just the episode title, for a second line under the name.
    var detailLine: String? {
        var parts: [String] = []
        if let season = seasonNumber, let episode = episodeNumber { parts.append("S\(season) E\(episode)") }
        if let episodeTitle, !episodeTitle.isEmpty, episodeTitle != name { parts.append(episodeTitle) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var timeRange: String { LiveProgramBar.timeRange(self) }

    /// New, Premiere, Live: worth calling out in the guide.
    var highlight: LocalizedStringKey? {
        if isLive { return "Live" }
        if isPremiere { return "Premiere" }
        if isNew { return "New" }
        return nil
    }
}

/// LIVE while watching live; once behind, how far and a button back to live.
struct LivePositionBadge: View {
    let behindSeconds: Double?
    let goLive: () -> Void

    var body: some View {
        if let behindSeconds {
            Button(action: goLive) {
                HStack(spacing: 6) {
                    Text("-" + Duration.seconds(behindSeconds).formatted(.time(pattern: behindSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                        .monospacedDigit()
                    Text("Go Live")
                }
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.2), in: Capsule())
            }
            .arcfinPlainButton(cornerRadius: 12, prominent: false)
            .accessibilityLabel("Go to live")
        } else {
            LiveBadge()
        }
    }
}
