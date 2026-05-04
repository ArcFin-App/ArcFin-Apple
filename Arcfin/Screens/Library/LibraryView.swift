import SwiftUI
import AVKit
import JellyfinAPI

#if canImport(UIKit)
import UIKit
import AuthCore
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
            .navigationDestination(for: JellyfinLibrary.self) { library in
                LibraryDetailView(library: library)
            }
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
                    NavigationLink(value: library) {
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

// MARK: - Library detail

struct LibraryDetailView: View {
    let library: JellyfinLibrary

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(StreamystatsRepository.self) private var statsRepo

    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    private let client = JellyfinMediaClient()
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DT.Color.backgroundPrimary)
            } else if items.isEmpty {
                ContentUnavailableView(library.name,
                                      systemImage: library.collectionType.systemIcon,
                                      description: Text("Nothing found in this library."))
                .background(DT.Color.backgroundPrimary)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                libraryItemCard(item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                quickLookMenu(item)
                            } preview: {
                                quickLookPreview(item)
                            }
                        }
                    }
                    .padding(DT.Spacing.pagePad)
                }
                .background(DT.Color.backgroundPrimary)
            }
        }
        .navigationTitle(library.name)
        .navigationDestination(for: MediaItem.self) { item in
            MediaDetailView(item: item)
        }
#if !os(macOS)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
#endif
        .task { await load() }
    }

    private func libraryItemCard(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = mediaRepo.imageURL(for: item) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color(DT.Color.backgroundSecondary)
                    }
                }
                .clipped()
            } else {
                DT.Color.backgroundSecondary
            }
            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let year = item.productionYear {
                    Text(String(year))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(8)
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    @ViewBuilder
    private func quickLookMenu(_ item: MediaItem) -> some View {
        if statsRepo.isConfigured {
            Button {
                Task { try? await statsRepo.addToWatchlist(itemId: item.id) }
            } label: {
                Label("Add to Watchlist", systemImage: "bookmark")
            }
        }
        Label(item.name, systemImage: item.type == .series ? "tv" : "film")
        if let year = item.productionYear {
            Label(String(year), systemImage: "calendar")
        }
        if let rating = item.communityRating {
            Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
        }
    }

    private func quickLookPreview(_ item: MediaItem) -> some View {
        ZStack {
            if let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 600) {
                AsyncImage(url: url) { ph in
                    if case .success(let img) = ph { img.resizable().scaledToFill() }
                    else { DT.Color.backgroundSecondary }
                }
            } else { DT.Color.backgroundSecondary }
            LinearGradient(
                colors: [.black.opacity(0.65), .black.opacity(0.2)],
                startPoint: .bottom,
                endPoint: .top
            )
            if let url = mediaRepo.imageURL(for: item, type: .primary, fillWidth: 320) {
                AsyncImage(url: url) { ph in
                    if case .success(let img) = ph {
                        img.resizable().scaledToFill()
                    } else {
                        quickLookPosterPlaceholder
                    }
                }
                .frame(width: 120, height: 178)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 10, y: 6)
            } else {
                quickLookPosterPlaceholder
                    .frame(width: 120, height: 178)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(width: 360, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var quickLookPosterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(DT.Color.backgroundSecondary)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            )
    }

    private func load() async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoading = true
        items = (try? await client.getLibraryItems(credential: cred, authHeader: header, libraryId: library.id)) ?? []
        isLoading = false
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
