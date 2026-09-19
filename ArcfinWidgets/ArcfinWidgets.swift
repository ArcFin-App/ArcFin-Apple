import WidgetKit
import SwiftUI
import UIKit
import LiveActivityKit
import ActivityKit

private enum WidgetDT {
    static let accent = Color(red: 0x06 / 255, green: 0xB6 / 255, blue: 0xD4 / 255)
    static let textSecondary = Color(white: 1, opacity: 0.6)
}

private func formattedBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func formattedSpeed(_ bytesPerSecond: Double) -> String {
    guard bytesPerSecond > 0 else { return "" }
    return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
}

@ViewBuilder
private func posterOrIcon(_ state: DownloadActivityAttributes.ContentState, size: CGFloat) -> some View {
    if let data = state.posterImageData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    } else {
        Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(WidgetDT.accent)
            .font(.system(size: size * 0.8))
            .frame(width: size, height: size * 1.5)
    }
}

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            lockScreenView(context.state)
                .activityBackgroundTint(Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0F / 255))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "arcfin://downloads"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    posterOrIcon(context.state, size: 26)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completedCount + 1)/\(context.state.totalCount)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.state.currentItemTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let episodeLabel = context.state.episodeLabel {
                            Text(episodeLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WidgetDT.accent)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: context.state.fractionComplete)
                            .tint(WidgetDT.accent)
                        HStack {
                            Text(formattedBytes(context.state.bytesWritten) + " of " + formattedBytes(context.state.totalBytes))
                            Spacer()
                            Text(formattedSpeed(context.state.bytesPerSecond))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetDT.textSecondary)
                    }
                    // Matches the Dynamic Island's own rounded silhouette — content flush to
                    // the region's edge otherwise reads as clipped against the curve.
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                }
            } compactLeading: {
                posterOrIcon(context.state, size: 16)
            } compactTrailing: {
                Text("\(Int(context.state.fractionComplete * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(WidgetDT.accent)
            }
            .widgetURL(URL(string: "arcfin://downloads"))
        }
    }

    @ViewBuilder
    private func lockScreenView(_ state: DownloadActivityAttributes.ContentState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            posterOrIcon(state, size: 40)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(state.isFinished ? "Download Complete" : "Downloading")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(min(state.completedCount + (state.isFinished ? 0 : 1), state.totalCount))/\(state.totalCount)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetDT.textSecondary)
                }

                HStack(spacing: 6) {
                    Text(state.currentItemTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let episodeLabel = state.episodeLabel {
                        Text(episodeLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WidgetDT.accent)
                    }
                }

                if !state.isFinished {
                    ProgressView(value: state.fractionComplete)
                        .tint(WidgetDT.accent)
                    HStack {
                        Text(formattedBytes(state.bytesWritten) + " of " + formattedBytes(state.totalBytes))
                        Spacer()
                        Text(formattedSpeed(state.bytesPerSecond))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetDT.textSecondary)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255))
                        Text(state.totalCount > 1 ? "\(state.totalCount) items ready to watch offline" : "Ready to watch offline")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetDT.textSecondary)
                }
            }
        }
        .padding(14)
    }
}
