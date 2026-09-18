import WidgetKit
import SwiftUI
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

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            lockScreenView(context.state)
                .activityBackgroundTint(Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0F / 255))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(WidgetDT.accent)
                        .font(.system(size: 22))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completedCount + 1)/\(context.state.totalCount)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.currentItemTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
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
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(WidgetDT.accent)
            } compactTrailing: {
                Text("\(Int(context.state.fractionComplete * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(WidgetDT.accent)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(_ state: DownloadActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: state.isFinished ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(WidgetDT.accent)
                    .font(.system(size: 18))
                Text(state.isFinished ? "Download Complete" : "Downloading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(min(state.completedCount + (state.isFinished ? 0 : 1), state.totalCount))/\(state.totalCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetDT.textSecondary)
            }

            Text(state.currentItemTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

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
            }
        }
        .padding(14)
    }
}
