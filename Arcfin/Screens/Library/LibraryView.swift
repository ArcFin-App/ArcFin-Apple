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
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
#endif
            .navigationDestination(for: JellyfinLibrary.self) { library in
                LibraryDetailView(library: library)
            }
            .navigationDestination(for: LibraryNavTarget.self) { target in
                switch target {
                case .media(let item):   MediaDetailView(item: item)
                case .collection(let item):
                    LibraryDetailView(library: JellyfinLibrary(
                        id: item.id, name: item.name,
                        collectionType: .unknown,
                        primaryImageTag: item.primaryImageTag))
                }
            }
            .onAppear { downloads = listDownloads() }
#if canImport(UIKit) && !os(tvOS)
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
#if os(tvOS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Spacing.shelfGap) {
                    ForEach(mediaRepo.libraries) { library in
                        NavigationLink(value: library) {
                            TVLibraryCard(library: library)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .focusSection()
            }
            .padding(.horizontal, -DT.Spacing.pagePad)
#else
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(mediaRepo.libraries) { library in
                    NavigationLink(value: library) {
                        LibraryCard(library: library)
                    }
                    .buttonStyle(.plain)
                }
            }
#endif
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

// MARK: - tvOS landscape library card

#if os(tvOS)
private struct TVLibraryCard: View {
    let library: JellyfinLibrary
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .fill(LinearGradient(
                    colors: [
                        Color(hex: library.collectionType.accentHex).opacity(0.3),
                        DT.Color.backgroundSecondary,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3)
                )

            HStack(spacing: 20) {
                Image(systemName: library.collectionType.systemIcon)
                    .font(.system(size: 40 * DT.Scale.font, weight: .light))
                    .foregroundStyle(Color(hex: library.collectionType.accentHex))

                Text(library.name)
                    .font(.system(size: 14 * DT.Scale.font, weight: .semibold))
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
            }
            .padding(24)
        }
        .frame(width: DT.Size.posterCard.width, height: DT.Size.posterCard.height)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 10)
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)
        .contentShape(Rectangle())
    }
}
#endif

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
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

// MARK: - Library detail

enum LibraryNavTarget: Hashable {
    case media(MediaItem)
    case collection(MediaItem)   // BoxSet item — routed to collection detail
}

struct LibraryDetailView: View {
    let library: JellyfinLibrary

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(StreamystatsRepository.self) private var statsRepo

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var totalItems = 0
    @State private var hasLoaded = false
    @State private var scrolledItemID: MediaItem.ID? = nil
    private let pageSize = 100

    private var hasMore: Bool { items.count < totalItems }
    private var isCollections: Bool { library.collectionType == .boxsets }

    // Maps the library type to the items it should show.
    // .unknown = BoxSet contents (Movie+Series from within a collection).
    private var includeTypes: String? {
        switch library.collectionType {
        case .movies:  return "Movie"
        case .tvshows: return "Series"
        case .boxsets: return "BoxSet"
        case .music:   return "MusicAlbum"
        case .unknown: return "Movie,Series"   // inside a BoxSet
        default:       return nil
        }
    }

    private let client = JellyfinMediaClient()
#if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: DT.Spacing.shelfGap)]
#else
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
#endif

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
#if !os(macOS) && !os(tvOS)
                    Text(library.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(DT.Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DT.Spacing.pagePad)
                        .padding(.top, DT.Spacing.pagePad)
#endif
                    LazyVGrid(columns: columns, spacing: DT.Spacing.shelfGap) {
                        ForEach(items) { item in
                            NavigationLink(value: navTarget(for: item)) {
#if os(tvOS)
                                PosterCard(
                                    title: item.name,
                                    subtitle: item.productionYear.map { String($0) },
                                    imageURL: mediaRepo.imageURL(for: item, type: .primary, fillWidth: 400),
                                    width: 200,
                                    height: 356
                                )
#else
                                libraryItemCard(item)
#endif
                            }
#if os(tvOS)
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .contextMenu { quickLookMenu(item) }
#else
                            .buttonStyle(.plain)
                            .contextMenu { quickLookMenu(item) } preview: { quickLookPreview(item) }
#endif
                            .onAppear {
                                if item.id == items.last?.id && hasMore && !isLoadingMore {
                                    Task { await loadMore() }
                                }
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(DT.Spacing.pagePad)
#if os(tvOS)
                    .focusSection()
                    .scrollClipDisabled()
#endif
                }
                .scrollPosition(id: $scrolledItemID)
                .background(DT.Color.backgroundPrimary)
            }
        }
        .navigationTitle("")
#if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
#endif
        .task { await load() }
    }

    private func navTarget(for item: MediaItem) -> LibraryNavTarget {
        item.type == .boxSet ? .collection(item) : .media(item)
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
                    if case .success(let img) = ph {
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    else { DT.Color.backgroundSecondary }
                }
            } else { DT.Color.backgroundSecondary }
            LinearGradient(
                colors: [.black.opacity(0.65), .black.opacity(0.2)],
                startPoint: .bottom,
                endPoint: .top
            )
            VStack(spacing: 0) {
                Spacer()
                if let url = mediaRepo.logoURL(for: item) {
                    AsyncImage(url: url) { ph in
                        if case .success(let img) = ph {
                            img.resizable().scaledToFit()
                        }
                    }
                    .frame(height: 80)
                    .padding(.horizontal, 20)
                } else {
                    Text(item.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                Spacer()
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
        guard !hasLoaded else { return }
        hasLoaded = true
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoading = true
        let fetched = try? await client.getLibraryItems(
            credential: cred, authHeader: header,
            libraryId: library.id, startIndex: 0, limit: pageSize,
            recursive: true,
            includeItemTypes: includeTypes
        )
        items = fetched?.items ?? []
        totalItems = fetched?.total ?? 0
        mediaRepo.prefetchQuickLookAssets(for: items)
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoadingMore = true
        let fetched = try? await client.getLibraryItems(
            credential: cred, authHeader: header,
            libraryId: library.id, startIndex: items.count, limit: pageSize,
            recursive: true,
            includeItemTypes: includeTypes
        )
        items.append(contentsOf: fetched?.items ?? [])
        if let total = fetched?.total { totalItems = total }
        isLoadingMore = false
    }
}

// MARK: - Document picker (UIKit bridge)

#if canImport(UIKit) && !os(tvOS)
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
