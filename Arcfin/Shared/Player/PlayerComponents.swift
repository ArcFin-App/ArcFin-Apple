// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// Covers the video with a plain screen for listening. Playback is untouched, and taps
/// still reach the surface underneath so the controls behave as usual.
struct PlayerAudioOnlyCover: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                Text(item.type == .episode ? (item.seriesName ?? item.name) : item.name)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Audio Only")
                    .font(.system(.footnote))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 32)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

struct PlayerSeekFeedbackView: View {
    let feedback: PlayerView.SeekFeedback

    var body: some View {
        // Positioned by onRight (where the tap actually landed), not forward (which side now
        // seeks which direction) — the indicator shows up under your finger, just with
        // whichever icon/direction that side now performs. A LEADING Spacer pushes content to
        // the trailing edge, not the other way around — this was inverted before, putting the
        // indicator on the opposite side from the actual tap.
        HStack {
            if feedback.onRight { Spacer() }
            VStack(spacing: 4) {
                Image(systemName: skipIconName(seconds: feedback.seconds, forward: feedback.forward))
                    .font(.system(.title))
                Text("\(feedback.seconds)s")
                    .font(.system(.caption2, design: .default, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(.black.opacity(0.4), in: Circle())
            if !feedback.onRight { Spacer() }
        }
        .padding(.horizontal, 40)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

struct PlayerNetworkToast: View {
    let text: String

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(.footnote, weight: .semibold))
                Text(text)
                    .font(.system(.caption, design: .default, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.7), in: Capsule())
            .padding(.top, 60)
            Spacer()
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

struct PlayerSubtitleOverlay: View {
    let text: String
    let isControlsVisible: Bool

    @AppStorage("subtitleTextSize") private var subtitleTextSize = SubtitleTextSize.medium
    @AppStorage("subtitleTextColor") private var subtitleTextColor = SubtitleTextColorOption.white
    @AppStorage("subtitleBackgroundStyle") private var subtitleBackgroundStyle = SubtitleBackgroundStyle.outline

    var body: some View {
        // The fixed bottom padding below is only clearance ABOVE the safe area, not a
        // substitute for it — on a device where an ancestor's ignoresSafeArea() (the video
        // surface, Color.black) leaves no safe-area context to inherit, 32/110pt alone
        // wasn't enough to clear the home indicator, and long cues sat behind/under it.
        // Reading the real inset via GeometryReader and adding it explicitly guarantees
        // clearance regardless of what the rest of the hierarchy is doing with safe areas.
        GeometryReader { proxy in
            VStack {
                Spacer()
                SubtitleText(text: text, size: subtitleTextSize, color: subtitleTextColor, background: subtitleBackgroundStyle)
                    .padding(.horizontal, 24)
                    .padding(.bottom, (isControlsVisible ? 110 : 32) + proxy.safeAreaInsets.bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// AetherEngine's native PGS/DVB bitmap cue path — a track Jellyfin has no delivery URL
/// for, so this is additive to PlayerSubtitleOverlay above, not a replacement. `cue.position`
/// is already normalized [0, 1] against the source canvas, so it maps directly onto the
/// on-screen video rect without needing the exact video frame math a cropped-canvas rip
/// would technically call for (a simplification, not attempting canvas-to-video-rect
/// letterbox alignment for v1).
struct PlayerBitmapSubtitleOverlay: View {
    let cue: NativeBitmapCue
    let isControlsVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            Image(decorative: cue.cgImage, scale: 1)
                .resizable()
                .frame(
                    width: cue.position.width * proxy.size.width,
                    height: cue.position.height * proxy.size.height
                )
                .position(
                    x: cue.position.midX * proxy.size.width,
                    y: cue.position.midY * proxy.size.height
                )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(DT.Animation.fast, value: isControlsVisible)
    }
}

/// The frame under the scrubber while dragging, from the title's trickplay images.
struct TrickplayPreview: View {
    let image: PlatformImage?
    let size: CGSize

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 1))
        .shadow(radius: 8)
        .allowsHitTesting(false)
    }
}

// MARK: - Chapters

/// Reuses the scrubber's own TrickplayLoader so the chapter list doesn't need a separate
/// image source — Jellyfin's dedicated per-chapter image endpoint isn't wired into
/// MediaChapter at all today, and every title with trickplay already has frames at every
/// chapter's start time anyway.
struct ChapterThumbnailView: View {
    let loader: TrickplayLoader?
    let positionTicks: Int64
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(DT.Color.backgroundTertiary)
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 80, height: 45)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: positionTicks) {
            image = await loader?.thumbnail(forPositionTicks: positionTicks)
        }
    }
}

/// The chapter list the iPhone, iPad and Apple TV players show as a sheet.
struct ChapterListSheet: View {
    let model: PlayerModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(model.chapters.enumerated()), id: \.offset) { index, chapter in
                    let isCurrent = model.currentChapterIndex == index
                    Button {
                        onClose()
                        model.jumpToChapter(chapter)
                    } label: {
                        HStack(spacing: 12) {
                            ChapterThumbnailView(loader: model.trickplayLoader, positionTicks: chapter.startPositionTicks)
                            Text(chapter.name ?? "Chapter \(index + 1)")
                                .font(.system(.footnote, design: .default, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? DT.Color.accent : DT.Color.textPrimary)
                            Spacer()
                            Text(model.timeLabel(ticks: chapter.startPositionTicks))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                    .arcfinPlainButton()
                }
            }
            .sheetTitle("Chapters")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
    }
}

// MARK: - Media info

struct PlayerMediaInfoSheet: View {
    let model: PlayerModel
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
        List {
            if let info = model.playbackInfo {
                Section("Video") {
                    if let codec = info.videoStream?.codec {
                        LabeledContent("Codec", value: codec.uppercased()).tvReadOnlyRow()
                    }
                    if let width = info.videoStream?.width, let height = info.videoStream?.height {
                        LabeledContent("Resolution", value: "\(width)×\(height)").tvReadOnlyRow()
                    }
                    if let range = info.videoStream?.videoRange {
                        LabeledContent("Video Range", value: range).tvReadOnlyRow()
                    }
                }
                Section("Audio") {
                    if let stream = model.currentAudioStream {
                        if let codec = stream.codec {
                            LabeledContent("Codec", value: codec.uppercased()).tvReadOnlyRow()
                        }
                        LabeledContent("Track", value: mediaInfoTrackLabel(stream)).tvReadOnlyRow()
                    } else {
                        Text("No audio track selected.")
                            .foregroundStyle(DT.Color.textSecondary)
                            .tvReadOnlyRow()
                    }
                }
                Section("Subtitle") {
                    if let stream = model.currentSubtitleStream {
                        LabeledContent("Track", value: mediaInfoTrackLabel(stream)).tvReadOnlyRow()
                    } else {
                        Text("Off")
                            .foregroundStyle(DT.Color.textSecondary)
                            .tvReadOnlyRow()
                    }
                }
                Section("Stream") {
                    if let container = info.container {
                        LabeledContent("Container", value: container.uppercased()).tvReadOnlyRow()
                    }
                    LabeledContent("Play Method", value: info.playMethod.rawValue).tvReadOnlyRow()
                    if let bitrate = info.bitrate {
                        LabeledContent("Bitrate", value: mediaInfoBitrateLabel(bitrate)).tvReadOnlyRow()
                    }
                }
            } else {
                Text("No playback info available.")
                    .foregroundStyle(DT.Color.textSecondary)
                    .tvReadOnlyRow()
            }
        }
        .insetGroupedList()
        .screenBackground()
        .sheetTitle("Media Info")
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onClose() }
            }
        }
        }
    }

    private func mediaInfoTrackLabel(_ stream: JellyfinMediaStream) -> String {
        if let title = stream.displayTitle, !title.isEmpty { return title }
        let parts = [stream.language, stream.codec?.uppercased()].compactMap { $0 }
        return parts.isEmpty ? "Track \(stream.index)" : parts.joined(separator: " · ")
    }

    private func mediaInfoBitrateLabel(_ bitrate: Int) -> String {
        let mbps = Double(bitrate) / 1_000_000
        return mbps >= 1 ? String(format: "%.1f Mb/s", mbps) : String(format: "%.0f Kb/s", Double(bitrate) / 1000)
    }
}

// MARK: - SyncPlay

struct SyncPlaySheet: View {
    @Bindable var model: PlayerModel
    let onClose: () -> Void

    @Environment(SyncPlayManager.self) private var syncPlayManager

    var body: some View {
        NavigationStack {
            Group {
                if syncPlayManager.isInGroup {
                    List {
                        Section("Group") {
                            LabeledContent("Name", value: syncPlayManager.groupName ?? "—")
                        }
                        Section {
                            Button(role: .destructive) {
                                model.leaveSyncPlayGroup()
                            } label: {
                                Text("Leave Group")
                            }
                        }
                    }
                } else {
                    List {
                        Section("Create a Group") {
                            TextField("Group name", text: $model.syncPlayGroupNameInput)
                            Button {
                                model.createSyncPlayGroup()
                            } label: {
                                if model.isSyncPlayBusy { ProgressView() } else { Text("Create") }
                            }
                            .disabled(model.syncPlayGroupNameInput.trimmingCharacters(in: .whitespaces).isEmpty || model.isSyncPlayBusy)
                        }
                        Section {
                            if syncPlayManager.availableGroups.isEmpty {
                                Text(syncPlayManager.isRefreshingGroups ? "Looking for groups…" : "No joinable groups right now.")
                                    .font(.system(.footnote))
                                    .foregroundStyle(DT.Color.textSecondary)
                            } else {
                                ForEach(syncPlayManager.availableGroups) { group in
                                    Button {
                                        model.joinSyncPlayGroup(group)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.groupName).foregroundStyle(DT.Color.textPrimary)
                                            Text("\(group.participants.count) watching" + (group.playingItemName.map { " · \($0)" } ?? ""))
                                                .font(.system(.caption2))
                                                .foregroundStyle(DT.Color.textSecondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Join a Group")
                        } footer: {
                            Text("Everyone in a group needs \(model.item.name) already open in their own player — SyncPlay keeps play, pause, and seek in sync from there.")
                        }
                    }
                    .task { await model.refreshSyncPlayGroups() }
                    .refreshable { await model.refreshSyncPlayGroups() }
                }
            }
            .sheetTitle("SyncPlay")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                }
            }
            .alert("SyncPlay", isPresented: Binding(
                get: { syncPlayManager.lastError != nil }, set: { if !$0 { syncPlayManager.lastError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(syncPlayManager.lastError ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Credits panel pieces

/// One of the Up Next card's buttons: Play Next, Like or Dislike.
struct CreditsActionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var countdown: PlayerView.AutoActionCountdown? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "\(systemImage).fill" : systemImage)
                .font(.system(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if let countdown { CountdownFill(countdown: countdown, color: .black.opacity(0.18)) }
                }
                .background(
                    isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)),
                    in: RoundedRectangle(cornerRadius: DT.Radius.md))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
        }
        .playerOverlayButton(cornerRadius: DT.Radius.md)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Skip Credits, Like or Dislike along the bottom of the More Like This panel.
struct CreditsRatingButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "\(systemImage).fill" : systemImage)
                .font(.system(.body, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)),
                    in: RoundedRectangle(cornerRadius: DT.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.md).stroke(.white.opacity(0.3), lineWidth: 1))
        }
        .playerOverlayButton(cornerRadius: DT.Radius.md)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SuggestionThumb: View {
    let suggestion: MediaItem
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        CachedAsyncImage(url: suggestionImageURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
        }
    }

    private var suggestionImageURL: URL? {
        mediaRepo.imageURL(for: suggestion, type: .thumb, fillWidth: 400)
            ?? mediaRepo.imageURL(for: suggestion, type: .backdrop, fillWidth: 400)
            ?? mediaRepo.imageURL(for: suggestion, type: .primary, fillWidth: 400)
    }
}

/// A suggestion in the More Like This row.
struct SuggestionCard: View {
    let suggestion: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SuggestionThumb(suggestion: suggestion)
                .frame(width: 176, height: 99)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
            Text(suggestion.name)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 176, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play \(suggestion.name)")
    }
}

/// A suggestion in the More Like This list, upright.
struct SuggestionRow: View {
    let suggestion: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            SuggestionThumb(suggestion: suggestion)
                .frame(width: 128, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let year = suggestion.productionYear {
                    Text(String(year))
                        .font(.system(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .font(.system(.footnote))
                .foregroundStyle(.white.opacity(0.8))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play \(suggestion.name)")
    }
}

// MARK: - Cast & Characters

/// Someone in the Cast & Characters panel: a column of photo and name, or a row in the side panel.
struct CastPanelPersonRow: View {
    let person: MediaPerson
    let compact: Bool
    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        let photo = CachedAsyncImage(url: person.primaryImageTag.flatMap {
            mediaRepo.personImageURL(personId: person.id, tag: $0, fillWidth: 160)
        }) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        return Group {
            if compact {
                VStack(spacing: 6) {
                    photo.frame(width: 72, height: 72).clipShape(Circle())
                    Text(person.name)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .frame(width: 88)
            } else {
                HStack(spacing: 12) {
                    photo.frame(width: 48, height: 48).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                        if let role = person.role, !role.isEmpty {
                            Text(role)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens their page")
    }
}

// MARK: - Audio & subtitle track selection

struct TrackSelectionSheet: View {
    let audioStreams: [JellyfinMediaStream]
    let subtitleStreams: [JellyfinMediaStream]
    let selectedAudioIndex: Int?
    let selectedSubtitleIndex: Int?
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int?) -> Void
    /// Set to offer a search of the server's subtitle providers for this item.
    var subtitleSearchItemId: String? = nil
    var onSubtitleDownloaded: () -> Void = {}
    /// Stream indexes of the audio tracks the engine reports as audio description.
    var audioDescriptionIndices: Set<Int> = []
    var rowBackground: Color = DT.Color.backgroundSecondary
    /// Darkens the focused row's text, for Apple TV's light focus platter.
    var followsFocus = false
    /// Set where the engine can lift speech above music and effects.
    var dialogueBoost: Binding<Bool>? = nil
    /// Set where the engine can raise a quiet source.
    var raiseQuietAudio: Binding<Bool>? = nil
    /// Set for anime and cartoons where the engine can upscale line art.
    var lineArt: Binding<Bool>? = nil

    var body: some View {
        List {
            if !audioStreams.isEmpty {
                Section {
                    ForEach(audioStreams, id: \.index) { stream in
                        trackRow(audioLabel(for: stream), isSelected: stream.index == selectedAudioIndex) {
                            onSelectAudio(stream.index)
                        }
                    }
                    if let dialogueBoost {
                        Toggle(isOn: dialogueBoost) {
                            Label("Dialogue Boost", systemImage: "waveform.badge.plus")
                                .foregroundStyle(DT.Color.textPrimary)
                        }
                        .tint(DT.Color.accent)
                        .listRowBackground(rowBackground)
                    }
                    if let raiseQuietAudio {
                        Toggle(isOn: raiseQuietAudio) {
                            Label("Raise Quiet Audio", systemImage: "speaker.wave.3")
                                .foregroundStyle(DT.Color.textPrimary)
                        }
                        .tint(DT.Color.accent)
                        .listRowBackground(rowBackground)
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    if dialogueBoost != nil {
                        Text("Dialogue Boost makes speech easier to hear over music and effects. Raise Quiet Audio brings a quiet film up to an everyday volume, without making loud ones louder. With Aether, Atmos plays as surround sound while either is on.")
                    }
                }
            }
            if let lineArt {
                Section {
                    Toggle(isOn: lineArt) {
                        Label("Animation Upscaling", systemImage: "sparkles.tv")
                            .foregroundStyle(DT.Color.textPrimary)
                    }
                    .tint(DT.Color.accent)
                    .listRowBackground(rowBackground)
                } header: {
                    Text("Video")
                } footer: {
                    Text("Sharpens the lines of anime and cartoons on a larger screen. It's heavy on the graphics chip: if playback stutters or drops frames, turn it off.")
                }
            }
            Section("Subtitles") {
                trackRow("Off", isSelected: selectedSubtitleIndex == nil) {
                    onSelectSubtitle(nil)
                }
                ForEach(subtitleStreams, id: \.index) { stream in
                    trackRow(label(for: stream), isSelected: stream.index == selectedSubtitleIndex) {
                        onSelectSubtitle(stream.index)
                    }
                }
                if let subtitleSearchItemId {
                    NavigationLink {
                        SubtitleSearchView(itemId: subtitleSearchItemId, onDownloaded: onSubtitleDownloaded)
                    } label: {
                        Label("Search for Subtitles…", systemImage: "magnifyingglass")
                            .foregroundStyle(DT.Color.accent)
                    }
                    .listRowBackground(DT.Color.backgroundSecondary)
                }
            }
        }
        .insetGroupedList()
        .screenBackground()
    }

    private func trackRow(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TrackRowLabel(label: label, isSelected: isSelected, followsFocus: followsFocus)
        }
        .listRowBackground(rowBackground)
    }

    private func label(for stream: JellyfinMediaStream) -> String {
        if let title = stream.displayTitle, !title.isEmpty { return title }
        let parts = [stream.language, stream.codec?.uppercased()].compactMap { $0 }
        return parts.isEmpty ? "Track \(stream.index)" : parts.joined(separator: " · ")
    }

    private func audioLabel(for stream: JellyfinMediaStream) -> String {
        guard audioDescriptionIndices.contains(stream.index) else { return label(for: stream) }
        return String(localized: "\(label(for: stream)) · Audio Description")
    }
}

/// tvOS draws a light platter behind the focused row, which white text disappears into.
private struct TrackRowLabel: View {
    let label: String
    let isSelected: Bool
    let followsFocus: Bool
    @Environment(\.isFocused) private var isFocusedHere

    private var isFocused: Bool { followsFocus && isFocusedHere }

    var body: some View {
        HStack {
            Text(label).foregroundStyle(isFocused ? Color.black : DT.Color.textPrimary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark").foregroundStyle(isFocused ? Color.black : DT.Color.accent)
            }
        }
    }
}
