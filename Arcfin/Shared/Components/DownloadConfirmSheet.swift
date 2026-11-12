// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A selectable download quality — nil bitrate means "Original" (no forced re-encode
/// unless one was already needed for container/codec reasons).
struct DownloadBitrateOption: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let bitrate: Int?
}

struct DownloadConfirmSheet: View {
    let item: MediaItem
    let preview: DownloadManager.DownloadPreview
    let onConfirm: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloadManager
    @State private var selectedOption: DownloadBitrateOption

    init(item: MediaItem, preview: DownloadManager.DownloadPreview, onConfirm: @escaping (Int?) -> Void) {
        self.item = item
        self.preview = preview
        self.onConfirm = onConfirm
        self._selectedOption = State(initialValue: Self.options.first!)
    }

    /// Fixed quality tiers — always the same list regardless of what the server reports for
    /// this source, since gating this on server-reported bitrate metadata is unreliable:
    /// plenty of libraries never get a deep metadata scan and report no bitrate on either
    /// the source or its streams at all.
    private static let options: [DownloadBitrateOption] = [
        DownloadBitrateOption(label: "Max", bitrate: nil),
        DownloadBitrateOption(label: "8 Mb/s", bitrate: 8_000_000),
        DownloadBitrateOption(label: "4 Mb/s", bitrate: 4_000_000),
        DownloadBitrateOption(label: "2 Mb/s", bitrate: 2_000_000),
        DownloadBitrateOption(label: "1 Mb/s", bitrate: 1_000_000),
        DownloadBitrateOption(label: "500 Kb/s", bitrate: 500_000),
    ]

    private func sizeBytes(for option: DownloadBitrateOption) -> Int64? {
        guard let bitrate = option.bitrate else { return preview.estimatedSizeBytes }
        guard let ticks = preview.runtimeTicks, ticks > 0 else { return nil }
        return Int64((Double(bitrate) + 320_000) / 8 * (Double(ticks) / 10_000_000))
    }

    /// Whether it fits, worked out before anything starts. A movie or episode that doesn't fit
    /// can't be started; a season downloads the episodes that fit and the rest wait for room.
    private var space: (message: String, blocks: Bool)? {
        guard let bytes = sizeBytes(for: selectedOption), bytes > 0, let room = downloadManager.roomForDownloads(),
              bytes > room else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let free = ByteCountFormatter.string(fromByteCount: room, countStyle: .file)
        guard let count = preview.episodeCount, count > 1 else {
            return (String(localized: "This needs about \(size), and only \(free) is free for downloads. Delete some downloads, or pick a lower quality."), true)
        }
        let fits = min(Int(room / max(bytes / Int64(count), 1)), count)
        if fits == 0 {
            return (String(localized: "There's no room for these episodes yet (\(free) free for downloads). They'll download once there's space."), false)
        }
        return (String(localized: "Only \(fits) of \(count) episodes fit right now (\(free) free for downloads). The rest download once there's space."), false)
    }

    private func spaceNote(_ message: String, blocks: Bool) -> some View {
        Label {
            Text(message)
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textPrimary)
        } icon: {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(blocks ? DT.Color.palette("F43F5E") : .orange)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((blocks ? DT.Color.palette("F43F5E") : Color.orange).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }

    private func estimatedSize(for option: DownloadBitrateOption) -> String {
        guard let bitrate = option.bitrate else {
            guard let bytes = preview.estimatedSizeBytes else { return "Unknown" }
            let prefix = preview.estimatedSizeIsApproximate ? "~" : ""
            return prefix + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        guard let ticks = preview.runtimeTicks, ticks > 0 else { return "Estimated" }
        let seconds = Double(ticks) / 10_000_000
        let bytes = Int64((Double(bitrate) + 320_000) / 8 * seconds)
        return "~" + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var resolutionLabel: String? {
        guard let width = preview.videoWidth, let height = preview.videoHeight else { return nil }
        switch height {
        case 2000...: return "4K (\(width)×\(height))"
        case 1000..<2000: return "1080p (\(width)×\(height))"
        case 700..<1000: return "720p (\(width)×\(height))"
        default: return "\(width)×\(height)"
        }
    }

    private var isHDR: Bool {
        (preview.videoRange ?? "").localizedCaseInsensitiveContains("hdr")
            || (preview.videoRange ?? "").localizedCaseInsensitiveContains("dolby")
    }

    private var runtimeLabel: String? {
        guard let ticks = preview.runtimeTicks, ticks > 0 else { return nil }
        let totalMinutes = Int(Double(ticks) / 10_000_000 / 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private var divider: some View {
        Divider().overlay(DT.Color.textPrimary.opacity(0.06))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DT.Spacing.md) {
                        Text(item.name)
                            .font(.system(.body, design: .default, weight: .bold))
                            .foregroundStyle(DT.Color.textPrimary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Quality")
                                .font(.system(.caption, design: .default, weight: .semibold))
                                .foregroundStyle(DT.Color.textSecondary)
                            Picker("Quality", selection: $selectedOption) {
                                ForEach(Self.options) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(DT.Color.textPrimary)
                        }

                        VStack(spacing: 0) {
                            row(label: "Size", value: estimatedSize(for: selectedOption))
                            if let runtimeLabel {
                                divider
                                row(label: "Runtime", value: runtimeLabel)
                            }
                            if let resolutionLabel {
                                divider
                                row(label: "Resolution", value: resolutionLabel + (isHDR ? " · HDR" : ""))
                            }
                            if let videoCodec = preview.videoCodec {
                                divider
                                row(label: "Video", value: videoCodec.uppercased())
                            }
                            divider
                            row(label: "Audio", value: preview.audioLanguages.isEmpty ? "Unknown" : preview.audioLanguages.joined(separator: ", "))
                            divider
                            row(label: "Subtitles", value: preview.subtitleLanguages.isEmpty ? "None" : preview.subtitleLanguages.joined(separator: ", "))
                            if let container = preview.container {
                                divider
                                row(label: "Format", value: container.uppercased())
                            }
                            if preview.willRemux || selectedOption.bitrate != nil {
                                divider
                                row(label: "Converted", value: "Yes — offline quality change")
                            }
                        }
                        .background(DT.Color.textPrimary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))

                        if let space {
                            spaceNote(space.message, blocks: space.blocks)
                        }

                        if preview.willRemux || selectedOption.bitrate != nil {
                            Text("This download will be converted on your server before downloading — this may take longer than the file size alone suggests.")
                                .font(.system(.caption))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                    .padding(DT.Spacing.pagePad)
                }

                Button {
                    onConfirm(selectedOption.bitrate)
                    dismiss()
                } label: {
                    Text(space?.blocks == true ? "Not Enough Space" : "Download")
                        .font(.system(.subheadline, design: .default, weight: .bold))
                        .foregroundStyle(DT.Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                        .opacity(space?.blocks == true ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(space?.blocks == true)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.pagePad)
            }
            .background(DT.Color.backgroundPrimary)
            .navigationTitle("Download")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
    }
}
