import SwiftUI
import JellyfinAPI
import AuthCore

/// Compact circular download affordance — reused on a movie's detail page and on each
/// episode row. Cycles: not downloaded -> downloading (progress ring, tap to cancel) ->
/// downloaded (checkmark, tap to delete).
struct DownloadButton: View {
    let item: MediaItem

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(AuthManager.self) private var authManager
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var isLoadingPreview = false
    @State private var previewSheet: DownloadManager.DownloadPreview?

    private var isDownloaded: Bool { downloadManager.isDownloaded(item.id) }
    private var progress: Double? { downloadManager.progress[item.id] }
    private var isQueued: Bool { downloadManager.activeItemTitles[item.id] != nil }

    var body: some View {
        Button {
            if isDownloaded {
                showDeleteConfirm = true
            } else if progress != nil || isQueued {
                downloadManager.cancelDownload(itemId: item.id)
            } else {
                loadPreview()
            }
        } label: {
            ZStack {
                if isLoadingPreview {
                    ProgressView().tint(.white)
                } else if let progress {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(progress, 0.02))
                        .stroke(DT.Color.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                } else if isQueued {
                    Image(systemName: "clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isDownloaded ? Color(hex: "10b981") : .white)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Delete this download?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // The button only needs the itemId to remove files + the SwiftData row, but
                // DownloadManager's public delete takes the record itself — look it up.
                downloadManager.deleteDownload(itemId: item.id)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Download Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: downloadManager.errors[item.id]) { _, newValue in
            guard let newValue else { return }
            errorMessage = newValue
            downloadManager.errors[item.id] = nil
        }
        .sheet(item: $previewSheet) { preview in
            DownloadConfirmSheet(item: item, preview: preview) { bitrateCap in
                startDownload(bitrateCap: bitrateCap)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func loadPreview() {
        guard case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        isLoadingPreview = true
        Task {
            let preview = await downloadManager.preview(for: item, credential: credential, authHeader: authHeader)
            isLoadingPreview = false
            previewSheet = preview ?? DownloadManager.DownloadPreview(subtitleLanguages: [], estimatedSizeBytes: nil, willRemux: false)
        }
    }

    private func startDownload(bitrateCap: Int? = nil) {
        guard case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        Task { await downloadManager.startDownload(item: item, credential: credential, authHeader: authHeader, bitrateCap: bitrateCap) }
    }
}
