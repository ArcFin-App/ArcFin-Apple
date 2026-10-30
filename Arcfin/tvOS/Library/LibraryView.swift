// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

struct LibraryView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager

    private let columns = [GridItem(.adaptive(minimum: 400), spacing: 20)]

    private var libraries: [JellyfinLibrary] { LibraryModel.libraries(in: mediaRepo) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if libraries.isEmpty {
                        ContentUnavailableView(
                            "No Libraries",
                            systemImage: "square.grid.2x2",
                            description: Text("Your Jellyfin libraries will appear here.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 400)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(libraries) { library in
                                NavigationLink(value: library) {
                                    TVBigLibraryCard(library: library)
                                }
                                .buttonStyle(TVCardButtonStyle())
                                .focusEffectDisabled()
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.top, 48)
                        .padding(.bottom, 60)
                        .focusSection()
                    }
                }
            }
            .screenBackground()
            .navigationDestination(for: JellyfinLibrary.self) { library in
                LibraryDetailView(library: library)
            }
            .navigationDestination(for: MediaItem.self) { item in
                TVMediaDetailView(item: item)
            }
            .navigationDestination(for: LibraryNavTarget.self) { target in
                switch target {
                case .media(let item):       TVMediaDetailView(item: item)
                case .collection(let item):  CollectionDetailView(collection: item)
                case .playlist(let item):    LibraryDetailView(playlistItem: item)
                }
            }
        }
    }
}

// MARK: - Big library card for tvOS

private struct TVBigLibraryCard: View {
    let library: JellyfinLibrary
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .fill(LinearGradient(
                    colors: [
                        Color(hex: library.collectionType.accentHex).opacity(0.25),
                        DT.Color.backgroundSecondary,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.lg)
                        .stroke(isFocused ? DT.Color.accent : Color.white.opacity(0.06), lineWidth: isFocused ? 3 : 1)
                )

            VStack(spacing: 20) {
                Image(systemName: library.collectionType.systemIcon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(
                        isFocused
                            ? DT.Color.accent
                            : Color(hex: library.collectionType.accentHex)
                    )
                    .animation(DT.Animation.fast, value: isFocused)

                Text(library.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
            }
            .padding(32)
        }
        .frame(height: 225)
        .scaleEffect(isFocused ? 1.04 : 1.0)
        .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 14)
        .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)
        .contentShape(Rectangle())
    }
}
