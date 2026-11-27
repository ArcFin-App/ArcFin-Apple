// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import JellyfinAPI
import SwiftUI

/// Stats' Your Arcs card: what this profile has done in Arcs, from Arcfin Sync.
struct ArcsStatsSection: View {
    let stats: ArcsMyStats
    @State private var opened: ArcClip?

    /// Nil when Arcs is off or there's nothing to show yet, which hides the card.
    @MainActor
    static func load(authManager: AuthManager) async -> ArcsMyStats? {
        guard authManager.arcfinSyncStatus?.isOn("arcs") == true, let credential = authManager.state.credential,
              let stats = try? await ArcsClient().myStats(credential: credential,
                                                          authHeader: authManager.authClient.authHeader(token: credential.accessToken)),
              stats.scenes > 0
        else { return nil }
        return stats
    }

    var body: some View {
        StatsCard(title: String(localized: "Your Arcs"), subtitle: subtitle, isFocusTarget: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140 * StatsMetrics.scale), spacing: 12)], spacing: 12) {
                StatTile(value: stats.scenes.formatted(), unit: nil, label: String(localized: "Scenes watched"),
                         icon: "play.square.stack", hex: "FF6A4D")
                StatTile(value: stats.minutes.formatted(), unit: nil, label: String(localized: "Minutes"), icon: "clock.fill", hex: "60A5FA")
                StatTile(value: stats.likes.formatted(), unit: nil, label: String(localized: "Likes"), icon: "heart.fill", hex: "EC4899")
                StatTile(value: stats.shares.formatted(), unit: nil, label: String(localized: "Shares"),
                         icon: "square.and.arrow.up.fill", hex: "10b981")
                StatTile(value: stats.watchFromHere.formatted(), unit: nil, label: String(localized: "Watch from Here"),
                         icon: "play.circle.fill", hex: "F97316")
            }
            if !stats.topTitles.isEmpty { topTitles }
            if stats.mostRewatched != nil || stats.topReaction != nil {
                VStack(spacing: 14) {
                    if let clip = stats.mostRewatched { rewatched(clip) }
                    if let reaction = stats.topReaction { topReaction(reaction) }
                }
            }
        }
        .fullScreenCover(item: $opened) { clip in
            ArcsCover(feed: .forYou, startingWith: [clip])
        }
    }

    private var subtitle: String? {
        stats.since.map { String(localized: "Since \($0.formatted(.dateTime.month(.wide).day().year()))") }
    }

    private var topTitles: some View {
        let most = max(stats.topTitles.map(\.scenes).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Most Watched in Arcs")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            ForEach(Array(stats.topTitles.prefix(5).enumerated()), id: \.element.id) { index, title in
                RankedBar(name: title.name, detail: String(localized: "\(title.scenes) scenes"),
                          fraction: Double(title.scenes) / Double(most),
                          color: StatsFormat.palette[index % StatsFormat.palette.count])
            }
        }
    }

    private func rewatched(_ clip: ArcClip) -> some View {
        Button { opened = clip } label: {
            FactRow(icon: "arrow.counterclockwise", hex: "FF6A4D", title: String(localized: "Most rewatched scene"),
                    value: [clip.seriesName ?? clip.name, ArcText.sceneLine(clip)].compactMap { $0 }.joined(separator: " · "))
                .contentShape(Rectangle())
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
        .accessibilityHint(Text("Opens it in Arcs."))
    }

    private func topReaction(_ reaction: ArcReaction) -> some View {
        let label = String(localized: ArcText.label(reaction))
        return FactRow(icon: "face.smiling", hex: "EAB308", title: String(localized: "Your top reaction"),
                       value: "\(ArcText.emoji(reaction)) \(label)")
            .accessibilityLabel(Text("Your top reaction: \(label)"))
    }
}
