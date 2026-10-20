// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore

struct PersonDetailView: View {
    let person: MediaPerson

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedItem: MediaItem?
    #if !os(tvOS)
    @Namespace private var zoomNamespace
    #endif
    @State private var detail: MediaPersonDetail?
    @State private var seerrCredits: [SeerrPersonCredit] = []
    @State private var requestingCredit: SeerrItem?

    private let client = JellyfinMediaClient()

    /// Titles Seerr knows this person appears in that aren't already in the Jellyfin library,
    /// already available/processing there, or already requested — tmdbId-matched throughout
    /// (see SeerrRepository.matchingRequest), never by title string.
    private var missingCredits: [SeerrPersonCredit] {
        let libraryTmdbIds = Set(items.compactMap(\.tmdbId))
        return seerrCredits.filter { credit in
            !libraryTmdbIds.contains(credit.id)
                && credit.mediaStatus != .available
                && credit.mediaStatus != .processing
                && credit.mediaStatus != .partiallyAvailable
                && seerrRepo.matchingRequest(for: credit.asSeerrItem) == nil
        }
    }

    private var credential: ServerCredential? { authManager.state.credential }

    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    private var columns: [GridItem] {
#if os(macOS)
        // Fixed 3-up stretches cards absurdly wide on a resizable Mac window — adaptive
        // reflows the grid as the window resizes instead.
        [GridItem(.adaptive(minimum: 130), spacing: 12)]
#else
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
#endif
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DT.Spacing.md) {
                header

                if isLoading {
                    ProgressView()
                        .tint(DT.Color.accent)
                        .padding(.top, 40)
                } else {
                    if let overview = detail?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DT.Spacing.pagePad)
                    }

                    if !items.isEmpty {
                        sectionHeader("In Your Library")
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

                    if !missingCredits.isEmpty {
                        sectionHeader("Also Appears In")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(missingCredits) { credit in
                                    creditCard(credit)
                                }
                            }
                            .padding(.horizontal, DT.Spacing.pagePad)
                        }
                    }
                }
            }
            .padding(.bottom, DT.Spacing.md)
        }
        .background(DT.Color.backgroundPrimary)
        .navigationTitle(person.name)
        .sheet(item: $requestingCredit) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingCredit)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selectedItem) { item in
#if os(tvOS)
            MediaDetailView(item: item)
#else
            MediaDetailView(item: item, zoomNamespace: zoomNamespace)
                .navigationTransition(.zoom(sourceID: item.id, in: zoomNamespace))
#endif
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                if let tag = person.primaryImageTag,
                   let url = mediaRepo.personImageURL(personId: person.id, tag: tag, fillWidth: 300) {
                    RetryingAsyncImage(
                        url: url,
                        logCategory: "PersonDetailView",
                        logContext: "header name=\(person.name)",
                        content: { img in img.resizable().scaledToFill() },
                        placeholder: { personPlaceholder }
                    )
                } else {
                    personPlaceholder
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

            Text(person.name)
                .font(.system(.title3, design: .default, weight: .heavy))
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)

            if let role = person.role, !role.isEmpty {
                Text(role)
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .padding(.top, DT.Spacing.md)
    }

    private var personPlaceholder: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .font(.system(size: 44))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.footnote, design: .default, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DT.Spacing.pagePad)
            .accessibilityAddTraits(.isHeader)
    }

    private func creditCard(_ credit: SeerrPersonCredit) -> some View {
        Button { requestingCredit = credit.asSeerrItem } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let url = credit.posterURL {
                            RetryingAsyncImage(
                                url: url,
                                logCategory: "PersonDetailView",
                                logContext: "credit title=\(credit.title)",
                                content: { img in img.resizable().scaledToFill() },
                                placeholder: { DT.Color.backgroundSecondary }
                            )
                        } else {
                            DT.Color.backgroundSecondary
                        }
                    }
                    .frame(width: 110, height: 165)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))

                    Image(systemName: "plus.circle.fill")
                        .font(.system(.title3))
                        .foregroundStyle(.white, DT.Color.accent)
                        .background(Circle().fill(.black.opacity(0.3)))
                        .padding(6)
                }
                Text(credit.title)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                if let role = credit.role, !role.isEmpty {
                    Text(role)
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 110)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let cred = credential, let header = authHeader else { return }
        async let fetchedItems = client.getPersonItems(credential: cred, authHeader: header, personId: person.id)
        async let fetchedDetail = client.getPersonDetail(credential: cred, authHeader: header, personId: person.id)
        items = (try? await fetchedItems) ?? []
        detail = try? await fetchedDetail
        if let tmdbId = detail?.tmdbId, seerrRepo.isConfigured {
            seerrCredits = await seerrRepo.personCredits(tmdbId: tmdbId) ?? []
        }
    }
}

#Preview {
    NavigationStack {
        PersonDetailView(person: MediaPerson(id: "1", name: "Timothée Chalamet", role: "Paul Atreides"))
            .environment(MediaRepository())
            .environment(AuthManager())
            .environment(SeerrRepository())
    }
}
