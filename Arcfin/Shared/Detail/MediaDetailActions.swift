// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Play or Resume, with Start Over beside it when there's a resume point; for an episode not
/// out yet or missing from the server, why it can't be played.
struct DetailPlayButton: View {
    @Environment(DownloadManager.self) private var downloadManager
    let model: MediaDetailModel

    private var resumeUserData: UserData? {
        model.playTarget.userData
    }

    /// "S2E5" for whichever episode Play/Resume is about to start — nil for a movie.
    private var playEpisodeLabel: String? {
        let target = model.playTarget
        guard target.type == .episode else { return nil }
        let s = target.parentIndexNumber.map { "S\($0)" }
        let e = target.indexNumber.map { "E\($0)" }
        return [s, e].compactMap { $0 }.joined().nilIfEmpty
    }

    private var resumeTimeLabel: String? {
        guard let ud = resumeUserData, ud.playbackPositionTicks > 0,
              let runTimeTicks = model.detail?.runTimeTicks, runTimeTicks > ud.playbackPositionTicks
        else { return nil }
        let remainingMinutes = Int(Double(runTimeTicks - ud.playbackPositionTicks) / 10_000_000 / 60)
        if remainingMinutes >= 60 { return "\(remainingMinutes / 60)h \(remainingMinutes % 60)m left" }
        return "\(remainingMinutes)m left"
    }

    /// Resume only: "19m left • Ends 9:42 PM" on its own line (too long to share the title
    /// line). A fresh Play shows its end time inline on the title line instead. The bullet
    /// is a heavier, larger glyph than a middle dot so it reads as a separator against the
    /// gradient.
    private var playDetailLine: Text? {
        guard model.isResumable else { return nil }
        let ends = model.endTime.map { Text("Ends \($0.formatted(date: .omitted, time: .shortened))") }
        let left = resumeTimeLabel.map { Text($0) }
        switch (left, ends) {
        case let (left?, ends?):
            // .font, not .contentFont: it has to stay a Text to go inside the line below.
            let separator = Text("  •  ").font(PlatformMetrics.contentFont(.footnote, design: nil, weight: .heavy))
            return Text("\(left)\(separator)\(ends)")
        case let (left?, nil): return left
        case let (nil, ends?): return ends
        case (nil, nil): return nil
        }
    }

    var body: some View {
        let isResumable = model.isResumable
        if model.playTarget.isVirtual {
            Label(MediaDetailView.unavailableText(model.playTarget), systemImage: "calendar")
                .contentFont(.callout, design: .default, weight: .bold)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.md)
        } else {
        HStack(spacing: 10) {
            Button {
                model.requestPlayback(startTicks: isResumable ? (resumeUserData?.playbackPositionTicks ?? 0) : 0,
                                      downloadManager: downloadManager)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").contentFont(.subheadline)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(isResumable ? "Resume" : "Play")
                                .contentFont(.callout, design: .default, weight: .bold)
                            if let playEpisodeLabel {
                                Text(playEpisodeLabel)
                                    .contentFont(.callout, design: .default, weight: .semibold)
                                    .opacity(0.85)
                            }
                            if !isResumable, let endsAt = model.endTime {
                                Text("•")
                                    .contentFont(.callout, design: .default, weight: .heavy)
                                    .opacity(0.9)
                                Text("Ends \(endsAt.formatted(date: .omitted, time: .shortened))")
                                    .contentFont(.callout, design: .default, weight: .semibold)
                                    .opacity(0.85)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        if let playDetailLine {
                            playDetailLine
                                .contentFont(.caption2, design: .default, weight: .semibold)
                                .opacity(0.85)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
                .foregroundStyle(DT.Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, playDetailLine == nil ? 14 : 10)
                .background(LinearGradient(
                    colors: [DT.Color.accentDeep, DT.Color.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .shadow(color: DT.Color.accent.opacity(0.35), radius: 12)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("detail.play")

            if isResumable {
                Button {
                    model.requestPlayback(startTicks: 0, isExplicitStartOver: true, downloadManager: downloadManager)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .contentFont(.body, weight: .semibold)
                        .foregroundStyle(DT.Color.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(DT.Color.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                        .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
                }
                .accessibilityLabel("Start over")
                .buttonStyle(.plain)
                .accessibilityLabel("Start Over")
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
        }
    }
}

/// Play Trailer: the server's trailer, a choice when it has several, or the YouTube one.
struct DetailTrailerButton: View {
    let model: MediaDetailModel
    let playYouTube: (RemoteTrailer) -> Void

    @State private var showTrailerPicker = false

    var body: some View {
        Button {
            if model.trailers.count > 1 {
                showTrailerPicker = true
            } else if let single = model.trailers.first {
                model.play(single)
            } else if let remoteTrailer = model.remoteTrailer {
                playYouTube(remoteTrailer)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "film").contentFont(.subheadline)
                Text("Play Trailer").contentFont(.subheadline, design: .default, weight: .semibold)
            }
            .foregroundStyle(DT.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DT.Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
        .confirmationDialog("Play Trailer", isPresented: $showTrailerPicker, titleVisibility: .visible) {
            ForEach(model.trailers) { trailer in
                Button(trailer.name) { model.play(trailer) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// A show's season picker, watched and download actions for the season, and its episodes.
struct DetailSeriesSection: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadManager.self) private var downloadManager
    let model: MediaDetailModel
    let spoilerProtection: Bool
    let openEpisode: (MediaItem) -> Void
    @State private var pendingScopeChange: MediaDetailModel.WatchScopeChange?

    private var isSeasonFullyDownloaded: Bool {
        model.isSeasonFullyDownloaded(in: downloadManager)
    }

    private func markScopeWatched(_ scope: MediaDetailModel.WatchScope, watched: Bool) {
        let change = MediaDetailModel.WatchScopeChange(scope: scope, watched: watched)
        if change.needsConfirmation {
            pendingScopeChange = change
        } else {
            model.markScopeWatched(scope, watched: watched, update: .inPlace, authManager: authManager)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Menu {
                    ForEach(model.seasons) { season in
                        Button(season.name) { model.selectedSeason = season }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(model.selectedSeason?.name ?? "Season")
                            .contentFont(.callout, design: .default, weight: .bold)
                            .foregroundStyle(DT.Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .contentFont(.caption2, weight: .semibold)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()

                Menu {
                    Button { markScopeWatched(.season, watched: true) } label: {
                        Label("Mark Season Watched", systemImage: "checkmark.circle")
                    }
                    Button { markScopeWatched(.season, watched: false) } label: {
                        Label("Mark Season Unwatched", systemImage: "circle")
                    }
                    Divider()
                    Button { markScopeWatched(.series, watched: true) } label: {
                        Label("Mark Series Watched", systemImage: "checkmark.circle.fill")
                    }
                    Button { markScopeWatched(.series, watched: false) } label: {
                        Label("Mark Series Unwatched", systemImage: "circle.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .contentFont(.body, weight: .semibold)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .accessibilityLabel("Mark watched options")
                .buttonStyle(.plain)

                Spacer()

                Button {
                    model.openSeasonDownload(downloadManager: downloadManager)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isSeasonFullyDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        Text(isSeasonFullyDownloaded ? "Season Downloaded" : "Download Season")
                    }
                    .contentFont(.caption, design: .default, weight: .semibold)
                    // A hardcoded accent color didn't dim when disabled (episodes still
                    // loading, or the whole season already downloaded) — tapping it then
                    // did nothing with zero visual feedback, which read as "no confirm
                    // popup ever shows up". Tapping an already-fully-downloaded season's
                    // button was also what produced the -1017 "Download Failed" error.
                    .foregroundStyle(model.episodes.isEmpty || isSeasonFullyDownloaded ? DT.Color.accent.opacity(0.35) : DT.Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(model.episodes.isEmpty || isSeasonFullyDownloaded)
                .shown(ProfileRules.shared.canDownload)
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            LazyVStack(spacing: 8) {
                if model.episodesLoadFailed {
                    EpisodesLoadFailedRow { model.retryEpisodes(authManager: authManager) }
                }
                ForEach(model.episodes) { ep in
                    EpisodeRow(
                        episode: ep,
                        badge: model.episodeBadge(ep, marksUnavailable: true),
                        spoilerProtection: spoilerProtection,
                        onSelect: { openEpisode(ep) },
                        onToggleWatched: {
                            model.markEpisodeWatched(ep, watched: ep.userData?.played != true,
                                                     update: .inPlace, authManager: authManager)
                        }
                    )
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .padding(.bottom, DT.Spacing.md)
        .watchScopeConfirmation($pendingScopeChange) { change in
            model.markScopeWatched(change.scope, watched: change.watched, update: .inPlace, authManager: authManager)
        }
    }
}

extension View {
    /// Asks before a season or series watched-state change that's hard to undo.
    func watchScopeConfirmation(_ pending: Binding<MediaDetailModel.WatchScopeChange?>,
                                confirm: @escaping (MediaDetailModel.WatchScopeChange) -> Void) -> some View {
        confirmationDialog(
            pending.wrappedValue.map { Text($0.question) } ?? Text(verbatim: ""),
            isPresented: Binding(get: { pending.wrappedValue != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { change in
            Button(change.actionLabel, role: change.watched ? nil : .destructive) { confirm(change) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// A season whose episodes couldn't be fetched, with a way to ask again.
struct EpisodesLoadFailedRow: View {
    let retry: () -> Void

    var body: some View {
        HStack {
            Text("Couldn't load this season's episodes.")
                .contentFont(.callout)
                .foregroundStyle(DT.Color.textSecondary)
            Spacer()
            Button("Try Again", action: retry)
        }
    }
}

/// Add to a playlist, find subtitles, and keep a show's next episodes downloaded.
struct DetailMoreMenu: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(AuthManager.self) private var authManager
    let model: MediaDetailModel
    let searchSubtitles: () -> Void

    var body: some View {
        let item = model.item
        let isWatched = model.isWatched
        Menu {
            if item.type == .movie || item.type == .episode {
                Button { model.markWatched(!isWatched, authManager: authManager) } label: {
                    Label(isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: isWatched ? "eye.slash" : "checkmark")
                }
                Divider()
            }
            Button { PlaylistStore.shared.addingItem = item } label: {
                Label("Add to Playlist…", systemImage: "text.badge.plus")
            }
            OpenInPlayerMenu(item: item)
            PlayOnDeviceMenu(item: item)
            CopyItemMenu(item: model.detail?.item ?? item)
            EditTagsButton(item: item)
            EditMetadataButton(item: item)
            if (item.type == .movie || item.type == .episode) && ProfileRules.shared.canManageSubtitles {
                Button { searchSubtitles() } label: {
                    Label("Search for Subtitles…", systemImage: "captions.bubble")
                }
            }
            if model.seasonSeriesId != nil, ProfileRules.shared.canDownload {
                Picker(selection: Binding(
                    get: { model.keptEpisodeCount },
                    set: { model.setKeptEpisodeCount($0, downloadManager: downloadManager) }
                )) {
                    Text("Off").tag(0)
                    ForEach([1, 2, 3, 5], id: \.self) { count in
                        Text(count == 1 ? "Next Episode" : "Next \(count) Episodes").tag(count)
                    }
                } label: {
                    Label("Keep Downloaded", systemImage: "arrow.down.circle.dotted")
                }
                .pickerStyle(.menu)
            }
            if ProfileRules.shared.canDownload, let target = model.smartDownloadsTarget {
                SmartDownloadsIgnoreButton(id: target.id, name: target.name)
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(DT.Color.textPrimary)
        }
        .accessibilityLabel("More")
    }
}

/// Like or dislike; picking the current rating again clears it.
struct DetailRatingMenu: View {
    @Environment(AuthManager.self) private var authManager
    let model: MediaDetailModel

    var body: some View {
        let likes = model.likes
        Menu {
            Button { model.setRating(true, authManager: authManager) } label: {
                Label(likes == true ? "Remove Like" : "Like", systemImage: likes == true ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            Button { model.setRating(false, authManager: authManager) } label: {
                Label(likes == false ? "Remove Dislike" : "Dislike", systemImage: likes == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
        } label: {
            Image(systemName: likes == true ? "hand.thumbsup.fill" : likes == false ? "hand.thumbsdown.fill" : "hand.thumbsup")
                .foregroundStyle(DT.Color.textPrimary)
        }
        .accessibilityLabel("Rate")
        .accessibilityValue(likes == true ? "Liked" : likes == false ? "Disliked" : "Not rated")
    }
}

/// Ignore in Smart Downloads, or Include again, for a movie or a show.
struct SmartDownloadsIgnoreButton: View {
    @Environment(DownloadManager.self) private var downloadManager
    let id: String
    let name: String

    var body: some View {
        let ignored = downloadManager.ignoredTitles[id] != nil
        Button {
            if ignored { downloadManager.setIgnored(id: id, name: name, ignored: false) }
            else { downloadManager.requestIgnore(id: id, name: name) }
        } label: {
            Label(ignored ? "Include in Smart Downloads" : "Ignore in Smart Downloads",
                  systemImage: ignored ? "arrow.down.circle" : "nosign")
        }
    }
}

extension View {
    /// Asks whether ignoring a title in Smart Downloads should remove its downloads too.
    /// Shown from the app's root, since the button that asks sits inside a menu.
    func smartDownloadsIgnorePrompt(_ downloadManager: DownloadManager) -> some View {
        alert("Ignore \(downloadManager.pendingIgnore?.name ?? "") in Smart Downloads?",
                     isPresented: Binding(get: { downloadManager.pendingIgnore != nil },
                                          set: { if !$0 { downloadManager.pendingIgnore = nil } }),
                     presenting: downloadManager.pendingIgnore) { request in
            Button("Ignore & Delete Downloads", role: .destructive) { downloadManager.ignoreAndDelete(request) }
            Button("Ignore, Keep Downloads") { downloadManager.setIgnored(id: request.id, name: request.name, ignored: true) }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("This also removes its downloads from Arcfin on this device. Keep them to still watch them offline.")
        }
    }
}
