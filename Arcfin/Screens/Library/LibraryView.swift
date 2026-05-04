import SwiftUI
import AVKit
import JellyfinAPI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Library screen

struct LibraryView: View {
    @Environment(MediaRepository.self) private var mediaRepo

    @State private var downloads: [DownloadedFile] = []
    @State private var playerItem: DownloadedFile?
    @State private var showDocPicker = false
    @State private var pickedURL: URL?
    @State private var navigateToLocalPlayer = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // ── Your Libraries ──────────────────────────────────────
                    if !mediaRepo.libraries.isEmpty {
                        librariesSection
                    }

                    // ── Downloads ───────────────────────────────────────────
                    downloadsSection

                    // ── On This Device ──────────────────────────────────────
                    onDeviceSection
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(DT.Color.backgroundPrimary)
            .navigationTitle("Library")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
#endif
            .onAppear { downloads = listDownloads() }
#if canImport(UIKit)
            .sheet(isPresented: $showDocPicker) {
                DocumentPickerView { url in
                    pickedURL = url
                    navigateToLocalPlayer = true
                }
            }
#endif
            .navigationDestination(isPresented: $navigateToLocalPlayer) {
                if let url = pickedURL {
#if !os(macOS)
                    LocalPlayerView(url: url)
                        .toolbar(.hidden, for: .tabBar)
#else
                    LocalPlayerView(url: url)
#endif
                }
            }
            .navigationDestination(item: $playerItem) { file in
#if !os(macOS)
                LocalPlayerView(url: file.url)
                    .toolbar(.hidden, for: .tabBar)
#else
                LocalPlayerView(url: file.url)
#endif
            }
        }
    }

    // MARK: - Libraries section

    private var librariesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Your Libraries")

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(mediaRepo.libraries) { library in
                    NavigationLink(destination: LibraryDetailView(library: library)) {
                        LibraryCard(library: library)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Downloads section

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Downloads")

            if downloads.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Downloaded content will appear here.")
                )
                .frame(height: 160)
            } else {
                VStack(spacing: 8) {
                    ForEach(downloads) { file in
                        Button {
                            playerItem = file
                        } label: {
                            DownloadRow(file: file)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - On this device section

    private var onDeviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("On This Device")

            Button {
                showDocPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(DT.Color.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse Files")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DT.Color.textPrimary)
                        Text("Pick a video file from Files app")
                            .font(.system(size: 12))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .fill(DT.Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DT.Radius.card)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DT.Font.cardTitle)
            .foregroundStyle(DT.Color.textPrimary)
            .tracking(-0.2)
    }

    private func listDownloads() -> [DownloadedFile] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ArcfinDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []
        return urls.map { url in
            let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return DownloadedFile(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                size: ByteCountFormatter.string(fromByteCount: Int64(attrs?.fileSize ?? 0), countStyle: .file),
                modifiedDate: attrs?.contentModificationDate ?? Date()
            )
        }.sorted { $0.modifiedDate > $1.modifiedDate }
    }
}

// MARK: - Library card

private struct LibraryCard: View {
    let library: JellyfinLibrary

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: library.collectionType.accentHex).opacity(0.25),
                            DT.Color.backgroundSecondary,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(Color(hex: library.collectionType.accentHex).opacity(0.18), lineWidth: 1)
                )

            VStack(spacing: 10) {
                Image(systemName: library.collectionType.systemIcon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color(hex: library.collectionType.accentHex))

                Text(library.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(16)
        }
        .frame(height: 110)
    }
}

// MARK: - Download row

private struct DownloadRow: View {
    let file: DownloadedFile

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(DT.Color.backgroundTertiary)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "film.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(DT.Color.accent)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(file.size)
                    .font(.system(size: 12))
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(DT.Color.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .fill(DT.Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Downloaded file model

struct DownloadedFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let size: String
    let modifiedDate: Date
}

// MARK: - Local player

struct LocalPlayerView: View {
    let url: URL

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .ignoresSafeArea()
            .background(Color.black)
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

// MARK: - Library detail placeholder

struct LibraryDetailView: View {
    let library: JellyfinLibrary

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            ContentUnavailableView(
                library.name,
                systemImage: library.collectionType.systemIcon,
                description: Text("Library browsing coming soon.")
            )
        }
        .navigationTitle(library.name)
#if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
#endif
    }
}

// MARK: - Document picker (UIKit bridge)

#if canImport(UIKit)
private struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            onPick(url)
        }
    }
}

import UniformTypeIdentifiers

private extension UTType {
    static let avi = UTType(filenameExtension: "avi") ?? .movie
}
#endif
