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
    @State private var selectedOption: DownloadBitrateOption

    init(item: MediaItem, preview: DownloadManager.DownloadPreview, onConfirm: @escaping (Int?) -> Void) {
        self.item = item
        self.preview = preview
        self.onConfirm = onConfirm
        self._selectedOption = State(initialValue: Self.options.first!)
    }

    /// Fixed quality tiers — always the same list regardless of what the server reports for
    /// this source (matching streamyfin's BitrateSelector), since gating this on server-
    /// reported bitrate metadata is unreliable: plenty of libraries never get a deep
    /// metadata scan and report no bitrate on either the source or its streams at all.
    private static let options: [DownloadBitrateOption] = [
        DownloadBitrateOption(label: "Max", bitrate: nil),
        DownloadBitrateOption(label: "8 Mb/s", bitrate: 8_000_000),
        DownloadBitrateOption(label: "4 Mb/s", bitrate: 4_000_000),
        DownloadBitrateOption(label: "2 Mb/s", bitrate: 2_000_000),
        DownloadBitrateOption(label: "1 Mb/s", bitrate: 1_000_000),
        DownloadBitrateOption(label: "500 Kb/s", bitrate: 500_000),
    ]

    private func estimatedSize(for option: DownloadBitrateOption) -> String {
        guard let bitrate = option.bitrate else {
            return preview.estimatedSizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Unknown"
        }
        guard let ticks = preview.runtimeTicks, ticks > 0 else { return "Estimated" }
        let seconds = Double(ticks) / 10_000_000
        let bytes = Int64((Double(bitrate) + 320_000) / 8 * seconds)
        return "~" + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                Text(item.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Quality")
                        .font(.system(size: 12, weight: .semibold))
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
                    Divider().overlay(.white.opacity(0.06))
                    row(label: "Subtitles", value: preview.subtitleLanguages.isEmpty ? "None" : preview.subtitleLanguages.joined(separator: ", "))
                    if preview.willRemux || selectedOption.bitrate != nil {
                        Divider().overlay(.white.opacity(0.06))
                        row(label: "Format", value: "Converted for offline playback")
                    }
                }
                .background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))

                if preview.willRemux || selectedOption.bitrate != nil {
                    Text("This download will be converted on your server before downloading — this may take longer than the file size alone suggests.")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.Color.textSecondary)
                }

                Spacer()

                Button {
                    onConfirm(selectedOption.bitrate)
                    dismiss()
                } label: {
                    Text("Download")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                }
                .buttonStyle(.plain)
            }
            .padding(DT.Spacing.pagePad)
            .background(DT.Color.backgroundPrimary)
            .navigationTitle("Download")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
    }
}
