import SwiftUI
import JellyfinAPI
import AuthCore

struct PersonDetailView: View {
    let person: MediaPerson

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var selectedItem: MediaItem?

    private let client = JellyfinMediaClient()

    private var credential: ServerCredential? { authManager.state.credential }

    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DT.Spacing.md) {
                header

                if isLoading {
                    ProgressView()
                        .tint(DT.Color.accent)
                        .padding(.top, 40)
                } else if !items.isEmpty {
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
                            .buttonStyle(.plain)
#endif
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                }
            }
            .padding(.bottom, DT.Spacing.md)
        }
        .background(DT.Color.backgroundPrimary)
        .navigationTitle(person.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationDestination(item: $selectedItem) { item in
            MediaDetailView(item: item)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                if let tag = person.primaryImageTag,
                   let url = mediaRepo.personImageURL(personId: person.id, tag: tag, fillWidth: 300) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: personPlaceholder
                        }
                    }
                } else {
                    personPlaceholder
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

            Text(person.name)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)

            if let role = person.role, !role.isEmpty {
                Text(role)
                    .font(.system(size: 13))
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

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let cred = credential, let header = authHeader else { return }
        items = (try? await client.getPersonItems(credential: cred, authHeader: header, personId: person.id)) ?? []
    }
}

#Preview {
    NavigationStack {
        PersonDetailView(person: MediaPerson(id: "1", name: "Timothée Chalamet", role: "Paul Atreides"))
            .environment(MediaRepository())
            .environment(AuthManager())
    }
}
