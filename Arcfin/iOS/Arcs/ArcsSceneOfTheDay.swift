// SPDX-License-Identifier: AGPL-3.0-or-later

import JellyfinAPI
import SwiftUI
import AuthCore

/// Home's Scene of the Day: one scene picked for this person each day, opening Arcs from it.
struct ArcsSceneOfTheDay: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage(ArcsSettings.clipOfTheDayKey) private var isOn = true
    @State private var clip: ArcClip?
    @State private var opened: ArcClip?

    private var available: Bool { isOn && authManager.arcfinSyncStatus?.isOn("arcs") == true }

    var body: some View {
        // A stack rather than a Group, so the load below runs while there's nothing to show yet.
        VStack(spacing: 0) {
            if available, let clip {
                Button { opened = clip } label: { card(clip) }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.bottom, 20)
                    .accessibilityLabel(Text("Scene of the Day: \(clip.seriesName ?? clip.name)"))
                    .accessibilityHint(Text("Opens it in Arcs."))
            }
        }
        .task(id: available) { await load() }
        .fullScreenCover(item: $opened) { clip in
            ArcsCover(feed: .forYou, startingWith: [clip])
        }
    }

    private func card(_ clip: ArcClip) -> some View {
        HStack(spacing: 14) {
            backdrop(clip)
                .frame(width: 96, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                }
            VStack(alignment: .leading, spacing: 5) {
                Label("Scene of the Day", systemImage: "play.square.stack")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DT.Color.accent)
                Text(verbatim: clip.seriesName ?? clip.name)
                    .font(.headline)
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                if let line = ArcText.sceneLine(clip) {
                    Text(verbatim: line).font(.subheadline).foregroundStyle(DT.Color.textSecondary).lineLimit(1)
                }
                if let overview = clip.overview {
                    Text(verbatim: overview).font(.footnote).foregroundStyle(DT.Color.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DT.Color.textPrimary.opacity(0.06), in: RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
    }

    private func backdrop(_ clip: ArcClip) -> some View {
        CachedAsyncImage(url: imageURL(clip)) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFill() } else { DT.Color.backgroundTertiary }
        }
    }

    private func imageURL(_ clip: ArcClip) -> URL? {
        guard let credential = authManager.state.credential else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: clip.titleID, tag: "", type: .primary,
                                            fillWidth: 240, token: credential.accessToken)
    }

    private func load() async {
        guard let credential = authManager.state.credential else {
            clip = nil
            return
        }
        var today: ArcClip?
        if available {
            do {
                let header = authManager.authClient.authHeader(token: credential.accessToken)
                today = try await ArcsClient().clipOfTheDay(credential: credential, authHeader: header)
            } catch {
                clip = nil
                return
            }
        } else if isOn, authManager.arcfinSyncStatus == nil {
            // Arcfin Sync hasn't answered yet: the widget keeps its scene until it does.
            clip = nil
            return
        }
        clip = today
        await ArcsWidgetPublisher.publish(today, credential: credential)
    }
}
