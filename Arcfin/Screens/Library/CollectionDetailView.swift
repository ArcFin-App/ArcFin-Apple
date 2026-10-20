// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Full detail for a Jellyfin BoxSet (Collection) — previously opened as a bare
/// LibraryDetailView (a bare item grid with library-style filter chips, meant for a real
/// library, not a curated collection), with no backdrop, overview, or cast. Same hero +
/// title-block treatment as MediaDetailView, then the collection's own titles as a grid
/// below instead of similar/recommended rows.
struct CollectionDetailView: View {
    let collection: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager

    @State private var detail: MediaItemDetail?
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedItem: MediaItem?
    @State private var selectedPerson: MediaPerson?
    #if !os(tvOS)
    @Namespace private var zoomNamespace
    #endif

    private let client = JellyfinMediaClient()

    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    private var columns: [GridItem] {
#if os(macOS)
        // Fixed 3-up stretches cards absurdly wide on a resizable Mac window — adaptive
        // reflows the grid as the window resizes instead. Same reasoning as PersonDetailView.
        [GridItem(.adaptive(minimum: 130), spacing: 12)]
#else
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
#endif
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                titleBlock

                if isLoading {
                    ProgressView()
                        .tint(DT.Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: DT.Spacing.md) {
                        if let overview = detail?.item.overview ?? collection.overview, !overview.isEmpty {
                            overviewSection(overview)
                        }

                        if let people = detail?.people, !people.isEmpty {
                            castSection(people)
                        }
                    }

                    if !items.isEmpty {
                        sectionTitle("\(items.count) Title\(items.count == 1 ? "" : "s")")
                            .padding(.horizontal, DT.Spacing.pagePad)
                            .padding(.top, DT.Spacing.md)
                            .padding(.bottom, DT.Spacing.sm)
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(items) { item in
                                Button { selectedItem = item } label: {
                                    PosterCard(
                                        title: item.name,
                                        subtitle: item.productionYear.map { String($0) },
                                        imageURL: mediaRepo.imageURL(for: item)
                                    )
                                }
#if os(tvOS)
                                .buttonStyle(TVCardButtonStyle())
                                .focusEffectDisabled()
#else
                                .buttonStyle(PressableButtonStyle())
                                .zoomTransitionSource(id: item.id, in: zoomNamespace)
#endif
                            }
                        }
                        .padding(.horizontal, DT.Spacing.pagePad)
                    }
                }

                Spacer().frame(height: DT.Size.tabBarHeight + 24)
            }
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .navigationDestination(item: $selectedItem) { item in
#if os(tvOS)
            MediaDetailView(item: item)
#else
            MediaDetailView(item: item, zoomNamespace: zoomNamespace)
                .navigationTransition(.zoom(sourceID: item.id, in: zoomNamespace))
#endif
        }
        .navigationDestination(item: $selectedPerson) { person in
            PersonDetailView(person: person)
        }
        .task { await load() }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            if let url = mediaRepo.imageURL(for: collection, type: .backdrop, fillWidth: 900) {
                RetryingAsyncImage(
                    url: url,
                    logCategory: "CollectionDetailView",
                    logContext: "backdrop collection=\(collection.name)",
                    content: { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    },
                    placeholder: { fallbackHero }
                )
            } else { fallbackHero }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.6),
                    .init(color: DT.Color.backgroundPrimary, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: 260)
        .clipped()
    }

    private var fallbackHero: some View {
        LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Title block

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            if let url = mediaRepo.imageURL(for: collection, type: .primary, fillWidth: 200) {
                RetryingAsyncImage(
                    url: url,
                    logCategory: "CollectionDetailView",
                    logContext: "poster collection=\(collection.name)",
                    content: { img in img.resizable().scaledToFill() },
                    placeholder: { RoundedRectangle(cornerRadius: 10).fill(DT.Color.backgroundSecondary) }
                )
                .frame(width: 90, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DT.Color.backgroundSecondary)
                    .frame(width: 90, height: 132)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.name)
                    .font(.system(.title3, design: .default, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text("Collection")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    if !items.isEmpty {
                        Text("·").foregroundStyle(.white.opacity(0.2))
                        Text("\(items.count) Title\(items.count == 1 ? "" : "s")")
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    if let rating = collection.communityRating {
                        Text("·").foregroundStyle(.white.opacity(0.2))
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(size: 9))
                            Text(String(format: "%.1f", rating))
                        }
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.accent)
                    }
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, -50)
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Overview / Cast

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.footnote, design: .default, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overviewSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Overview")
            Text(text)
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    private func castSection(_ people: [MediaPerson]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Cast").padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(people) { person in
                        Button { selectedPerson = person } label: {
                            CastPersonCard(
                                imageURL: person.primaryImageTag.flatMap {
                                    mediaRepo.personImageURL(personId: person.id, tag: $0, fillWidth: 120)
                                },
                                name: person.name,
                                role: person.role,
                                placeholder: { personPlaceholder }
                            )
                        }
#if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
#else
                        .buttonStyle(.plain)
#endif
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    private var personPlaceholder: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .font(.system(size: 22))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let cred = credential, let header = authHeader else { return }
        async let fetchedDetail = client.getItemDetail(credential: cred, authHeader: header, itemId: collection.id)
        async let fetchedItems = client.getLibraryItems(
            credential: cred, authHeader: header, libraryId: collection.id, limit: 200
        )
        detail = try? await fetchedDetail
        items = (try? await fetchedItems)?.items ?? []
    }
}
