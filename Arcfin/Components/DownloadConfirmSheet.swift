import SwiftUI
import JellyfinAPI

struct DownloadConfirmSheet: View {
    let item: MediaItem
    let preview: DownloadManager.DownloadPreview
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                Text(item.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)

                VStack(spacing: 0) {
                    row(label: "Size", value: preview.estimatedSizeBytes.map {
                        ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                    } ?? "Unknown")
                    Divider().overlay(.white.opacity(0.06))
                    row(label: "Subtitles", value: preview.subtitleLanguages.isEmpty ? "None" : preview.subtitleLanguages.joined(separator: ", "))
                    if preview.willRemux {
                        Divider().overlay(.white.opacity(0.06))
                        row(label: "Format", value: "Converted for offline playback")
                    }
                }
                .background(.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))

                if preview.willRemux {
                    Text("This item's format isn't directly playable offline, so it'll be converted on your server before downloading — this may take longer than the file size alone suggests.")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.Color.textSecondary)
                }

                Spacer()

                Button {
                    onConfirm()
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
