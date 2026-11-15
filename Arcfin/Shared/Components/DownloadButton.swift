// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Compact circular download affordance — reused on a movie's detail page and on each
/// episode row. Cycles: not downloaded -> downloading (progress ring, tap to cancel) ->
/// downloaded (checkmark, tap to delete).
struct DownloadButton: View {
    let item: MediaItem
    /// The tappable square. A Mac toolbar sizes its own buttons, so it passes a smaller one.
    var hitSize: CGFloat = 44

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(AuthManager.self) private var authManager
    @State private var showDeleteConfirm = false
    @State private var showSmartCancelConfirm = false
    @State private var errorMessage: String?
    @State private var isSheetShown = false

    private var isDownloaded: Bool { downloadManager.isDownloaded(item.id) }
    private var progress: Double? { downloadManager.progress[item.id] }
    private var isQueued: Bool { downloadManager.activeItemTitles[item.id] != nil }

    private var downloadAccessibilityLabel: LocalizedStringKey {
        if isDownloaded { return "Downloaded, tap to delete" }
        if progress != nil || isQueued { return "Cancel download" }
        return "Download"
    }

    var body: some View {
        // A profile the server doesn't allow to download still sees, and can delete, what's
        // already on the device.
        if ProfileRules.shared.canDownload || isDownloaded || progress != nil || isQueued {
            button
        }
    }

    private var button: some View {
        Button {
            if isDownloaded {
                showDeleteConfirm = true
            } else if progress != nil || isQueued {
                if downloadManager.smartIgnoreTarget(itemId: item.id) != nil {
                    showSmartCancelConfirm = true
                } else {
                    downloadManager.cancelDownload(itemId: item.id)
                }
            } else {
                isSheetShown = true
            }
        } label: {
            ZStack {
                if let progress {
                    Circle().stroke(DT.Color.textPrimary.opacity(0.2), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(progress, 0.02))
                        .stroke(DT.Color.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "xmark")
                        .font(.system(.caption2, weight: .bold))
                } else if isQueued {
                    Image(systemName: "clock")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary.opacity(0.7))
                } else {
                    Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(isDownloaded ? DT.Color.palette("10b981") : DT.Color.textPrimary)
                }
            }
            .frame(width: min(30, hitSize), height: min(30, hitSize))
        }
        .accessibilityLabel(downloadAccessibilityLabel)
        .buttonStyle(.plain)
        // Visual size stays 30x30 (buttons.md's 28pt minimum); the tappable area grows to
        // the 44pt default. This button is the trailing-most element in its row with
        // nothing else to its right, so the extra hit area only reclaims mis-taps at this
        // one edge rather than overlapping a neighboring control.
        .frame(width: hitSize, height: hitSize)
        .contentShape(Rectangle())
        .alert("Delete this download?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                // The button only needs the itemId to remove files + the SwiftData row, but
                // DownloadManager's public delete takes the record itself — look it up.
                downloadManager.deleteDownload(itemId: item.id)
            }
            if downloadManager.smartIgnoreTarget(itemId: item.id) != nil {
                Button("Delete & Ignore in Smart Downloads", role: .destructive) { downloadManager.deleteAndIgnore(itemIds: [item.id]) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Smart Downloads fetched this. Cancel it?", isPresented: $showSmartCancelConfirm) {
            Button("Cancel Download", role: .destructive) { downloadManager.cancelDownload(itemId: item.id) }
            Button("Cancel & Ignore in Smart Downloads", role: .destructive) { downloadManager.deleteAndIgnore(itemIds: [item.id]) }
            Button("Keep Downloading", role: .cancel) {}
        }
        .alert("Download Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Retry") { isSheetShown = true }
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: downloadManager.errors[item.id]) { _, newValue in
            guard let newValue else { return }
            errorMessage = newValue
            downloadManager.errors[item.id] = nil
        }
        .appSheet(isPresented: $isSheetShown) {
            DownloadConfirmSheet(item: item, load: loadPreview) { choice in
                startDownload(choice)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func loadPreview() async -> DownloadManager.DownloadPreview? {
        guard case .authenticated(let credential) = authManager.state else { return nil }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        return await downloadManager.preview(for: item, credential: credential, authHeader: authHeader)
    }

    private func startDownload(_ choice: DownloadChoice) {
        guard case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        Task {
            await downloadManager.startDownload(item: item, credential: credential, authHeader: authHeader,
                                                bitrateCap: choice.bitrateCap, tracks: choice.tracks)
        }
    }
}
