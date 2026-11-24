// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// What the download sheet hands back: the quality tier (nil is the original file), the
/// tracks to keep and, for a season, the episodes ticked in episode order.
struct DownloadChoice {
    let bitrateCap: Int?
    let tracks: DownloadTracks
    var episodes: [MediaItem] = []
}

/// A quality the sheet offers. `tier` is what H.264 needs for its picture; `videoBitrate` is
/// what it's converted at. Both nil for the original file.
private struct DownloadQualityOption: Identifiable, Hashable {
    let quality: DownloadQuality
    let tier: Int?
    let videoBitrate: Int?
    var id: DownloadQuality { quality }
}

/// Opens straight away with what's known about the title and fills in the file's details
/// (size, tracks, qualities) once `load` has them from the server.
struct DownloadConfirmSheet: View {
    let item: MediaItem
    /// A season's episodes, listed to tick; `load` then previews one of them.
    var episodes: [MediaItem] = []
    let load: () async -> DownloadManager.DownloadPreview?
    let onConfirm: (DownloadChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(AuthManager.self) private var authManager
    @AppStorage("seasonDownloadUnwatchedOnly") private var unwatchedOnly = false
    @State private var loadedPreview: DownloadManager.DownloadPreview?
    @State private var picked: Set<String> = []
    @State private var hasPicked = false
    @State private var isLoading = true
    /// The server didn't answer for the file (offline, an error, no permission).
    @State private var loadFailed = false
    @State private var quality = DownloadQuality.original
    @State private var audioKeys: Set<String> = []
    @State private var subtitleKeys: Set<String> = []
    @State private var isAtEnd = true
    @State private var hasReachedEnd = false
    /// Read once the details are in: working it out reads the running downloads' progress and
    /// the volume's capacity, which on every render redrew the sheet with each progress tick.
    @State private var room: Int64?

    private var isSeason: Bool { !SeasonEpisodePicks.listed(episodes).isEmpty }

    private var taken: Set<String> {
        Set(episodes.map(\.id).filter { downloadManager.isDownloaded($0) || downloadManager.isInProgress($0) })
    }

    private var pickedEpisodes: [MediaItem] {
        SeasonEpisodePicks.ordered(episodes, picked: picked, taken: taken)
    }

    /// For a season, the one episode's figures scaled to the episodes ticked.
    private var preview: DownloadManager.DownloadPreview? {
        guard var preview = loadedPreview, isSeason else { return loadedPreview }
        let picks = pickedEpisodes
        let count = Int64(picks.count)
        let runtimes = picks.compactMap(\.runTimeTicks)
        preview.estimatedSizeBytes = preview.estimatedSizeBytes.map { $0 * count }
        preview.runtimeTicks = runtimes.count == picks.count ? runtimes.reduce(0, +) : preview.runtimeTicks.map { $0 * count }
        preview.episodeCount = picks.count
        return preview
    }

    private var options: [DownloadQualityOption] {
        guard let preview else { return [DownloadQualityOption(quality: .original, tier: nil, videoBitrate: nil)] }
        return DownloadQuality.allCases.compactMap { quality in
            guard let tier = quality.tier else { return DownloadQualityOption(quality: quality, tier: nil, videoBitrate: nil) }
            let encoding = preview.encoding
            guard !encoding.keepsOriginal(forTier: tier, sourceBitrate: preview.sourceBitrate, sourceCodec: preview.videoCodec) else { return nil }
            return DownloadQualityOption(quality: quality, tier: tier,
                                         videoBitrate: encoding.videoBitrate(forTier: tier, sourceBitrate: preview.sourceBitrate, sourceCodec: preview.videoCodec))
        }
    }

    private var selected: DownloadQualityOption {
        options.first { $0.quality == quality } ?? options[0]
    }

    private var isConverted: Bool { selected.videoBitrate != nil }

    private var keptAudioCount: Int {
        isConverted ? max(audioKeys.count, 1) : max(preview?.audioStreams.count ?? 1, 1)
    }

    private func sizeBytes(for option: DownloadQualityOption) -> Int64? {
        guard let preview else { return nil }
        guard let bitrate = option.videoBitrate else { return preview.estimatedSizeBytes }
        guard let ticks = preview.runtimeTicks, ticks > 0 else { return nil }
        let audio = Double(320_000 * keptAudioCount)
        return Int64((Double(bitrate) + audio) / 8 * (Double(ticks) / 10_000_000))
    }

    private var sizeLabel: String {
        guard let bytes = sizeBytes(for: selected) else { return String(localized: "Unknown") }
        let approximate = isConverted || preview?.estimatedSizeIsApproximate == true
        return (approximate ? "~" : "") + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Whether it fits, worked out before anything starts. A movie or episode that doesn't fit
    /// can't be started; a season downloads the episodes that fit and the rest wait for room.
    private var space: (message: String, blocks: Bool)? {
        guard let bytes = sizeBytes(for: selected), bytes > 0, let room,
              bytes > room else { return nil }
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let free = ByteCountFormatter.string(fromByteCount: room, countStyle: .file)
        guard let count = preview?.episodeCount, count > 1 else {
            return (String(localized: "This needs about \(size), and only \(free) is free for downloads. Delete some downloads, or pick a lower quality."), true)
        }
        let fits = min(Int(room / max(bytes / Int64(count), 1)), count)
        if fits == 0 {
            return (String(localized: "There's no room for these episodes yet (\(free) free for downloads). They'll download once there's space."), false)
        }
        return (String(localized: "Only \(fits) of \(count) episodes fit right now (\(free) free for downloads). The rest download once there's space."), false)
    }

    private var choice: DownloadChoice {
        let allAudio = Set(preview?.audioStreams.map(DownloadTracks.key) ?? [])
        let audio: [String]? = !isConverted || audioKeys == allAudio ? nil : preview?.audioStreams.map(DownloadTracks.key).filter(audioKeys.contains)
        let subtitles = preview?.subtitleStreams.map(DownloadTracks.key).filter(subtitleKeys.contains) ?? []
        return DownloadChoice(bitrateCap: selected.tier, tracks: DownloadTracks(audio: audio, subtitles: subtitles), episodes: pickedEpisodes)
    }

    private var blocksDownload: Bool {
        isLoading || loadFailed || space?.blocks == true || (isSeason && pickedEpisodes.isEmpty)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                        header
                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Getting the file's details…")
                                    .font(.system(.footnote))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DT.Spacing.xl)
                        } else if loadFailed {
                            loadFailedNotice
                        } else {
                            details
                        }
                    }
                    .padding(DT.Spacing.pagePad)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.maxY >= geometry.contentSize.height - 8
                } action: { _, atEnd in
                    isAtEnd = atEnd
                    if atEnd && !isLoading { hasReachedEnd = true }
                }
                .overlay(alignment: .bottom) {
                    if !isLoading && !isAtEnd && !hasReachedEnd {
                        scrollHint
                    }
                }
                .animation(.easeOut(duration: 0.2), value: hasReachedEnd)

                Button {
                    onConfirm(choice)
                    dismiss()
                } label: {
                    Text(space?.blocks == true ? "Not Enough Space" : "Download")
                        .font(.system(.subheadline, design: .default, weight: .bold))
                        .foregroundStyle(DT.Color.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                        .opacity(blocksDownload ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(blocksDownload)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.pagePad)
            }
            .background(DT.Color.backgroundPrimary)
            .navigationTitle("Download")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            if !hasPicked {
                picked = SeasonEpisodePicks.defaults(episodes, taken: taken, unwatchedOnly: unwatchedOnly)
                hasPicked = true
            }
            await loadPreview()
        }
    }

    private var loadFailedNotice: some View {
        VStack(spacing: 10) {
            Text("Couldn't load this title's details.")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Check your connection and try again.")
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
            Button("Try Again") { Task { await loadPreview() } }
                .buttonStyle(.bordered)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.Spacing.xl)
    }

    private func loadPreview() async {
        isLoading = true
        loadFailed = false
        guard let loaded = await load() else {
            loadFailed = true
            isLoading = false
            return
        }
        loadedPreview = loaded
        room = downloadManager.roomForDownloads()
        audioKeys = Set(loaded.audioStreams.map(DownloadTracks.key))
        subtitleKeys = Set(DownloadManager.subtitlesFromSettings(loaded.subtitleStreams).map(DownloadTracks.key))
        quality = options.contains { $0.quality == DownloadQuality.saved } ? DownloadQuality.saved : .original
        isLoading = false
    }

    // MARK: - Header

    private var isWide: Bool { item.type == .episode }

    private var artworkURL: URL? {
        guard case .authenticated(let credential) = authManager.state else { return nil }
        let (id, tag) = item.primaryImageTag.map { (item.id, $0) }
            ?? item.seriesPrimaryImageTag.flatMap { tag in item.seriesId.map { ($0, tag) } }
            ?? (item.id, "")
        guard !tag.isEmpty else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: id, tag: tag, fillWidth: 300, token: credential.accessToken)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DT.Spacing.md) {
            PosterCardArtwork(title: item.name, imageURL: artworkURL, accentHue: DT.Color.backgroundTertiary)
                .frame(width: isWide ? 128 : 76, height: isWide ? 72 : 114)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let context = contextLine {
                    Text(context)
                        .font(.system(.caption, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                Text(item.name)
                    .font(.system(.headline, design: .default, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                if let meta = metaLine {
                    Text(meta)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var contextLine: String? {
        switch item.type {
        case .episode:
            let number = item.parentIndexNumber.flatMap { season in item.indexNumber.map { String(localized: "S\(season) E\($0)") } }
            return [item.seriesName, number].compactMap(\.self).joined(separator: " · ").nilIfEmpty
        case .season:
            return item.seriesName
        default:
            return nil
        }
    }

    private var metaLine: String? {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        if let count = preview?.episodeCount, count > 1 {
            parts.append(String(localized: "\(count) episodes"))
        } else if let ticks = preview?.runtimeTicks ?? item.runTimeTicks, ticks > 0 {
            parts.append(Self.runtimeLabel(ticks: ticks))
        }
        if let rating = item.communityRating { parts.append("★ " + rating.formatted(.number.precision(.fractionLength(1)))) }
        if !item.genres.isEmpty { parts.append(item.genres.prefix(2).joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Details

    @ViewBuilder
    private var details: some View {
        if let preview {
            section("Quality") {
                Picker("Quality", selection: $quality) {
                    ForEach(options) { option in
                        Text(qualityLabel(option)).tag(option.quality)
                    }
                }
                .pickerStyle(.menu)
                .tint(DT.Color.textPrimary)
                .padding(.horizontal, 4)
                if let space {
                    spaceNote(space.message, blocks: space.blocks)
                }
            }

            card {
                row("Size", sizeLabel)
                if let ticks = preview.runtimeTicks, ticks > 0 {
                    divider
                    row(preview.episodeCount ?? 0 > 1 ? "Total Runtime" : "Runtime", Self.runtimeLabel(ticks: ticks))
                }
                if isConverted {
                    divider
                    row("Converted", preview.encoding.codec.map { String(localized: "Yes, to \($0.uppercased())") } ?? String(localized: "Yes"))
                }
            }

            if isSeason {
                episodeSection
            }

            if let video = videoLines(preview) , !video.isEmpty {
                section("Video") {
                    card {
                        ForEach(Array(video.enumerated()), id: \.offset) { index, line in
                            if index > 0 { divider }
                            row(line.label, line.value)
                        }
                    }
                }
            }

            audioSection(preview)
            subtitleSection(preview)

            if isConverted {
                Text(keptAudioCount > 1
                     ? "Your server converts this before it downloads, so it can take longer than its size suggests. Each extra audio track is fetched on its own and added to the file afterwards."
                     : "Your server converts this before it downloads, so it can take longer than its size suggests.")
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    private var episodeSection: some View {
        let taken = taken
        let listed = SeasonEpisodePicks.listed(episodes)
        return section("Episodes") {
            HStack(spacing: DT.Spacing.md) {
                Button("Select All") { picked = Set(SeasonEpisodePicks.selectable(episodes, taken: taken).map(\.id)) }
                Button("Select None") { picked = [] }
                Button("Next 3 Unwatched") { picked = SeasonEpisodePicks.nextUnwatched(episodes, taken: taken) }
            }
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(DT.Color.accent)
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            card {
                ForEach(Array(listed.enumerated()), id: \.element.id) { index, episode in
                    if index > 0 { divider }
                    episodeRow(episode, isTaken: taken.contains(episode.id))
                }
            }
        }
    }

    private func episodeRow(_ episode: MediaItem, isTaken: Bool) -> some View {
        let isOn = isTaken || picked.contains(episode.id)
        return Button {
            if picked.contains(episode.id) { picked.remove(episode.id) } else { picked.insert(episode.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(.body))
                    .foregroundStyle(isOn && !isTaken ? DT.Color.accent : DT.Color.textSecondary)
                    .accessibilityHidden(true)
                if let number = episode.indexNumber {
                    Text(verbatim: "\(number)")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DT.Color.textSecondary)
                        .frame(minWidth: 20, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: episode.name)
                        .font(.system(.footnote, design: .default, weight: .medium))
                        .foregroundStyle(isTaken ? DT.Color.textSecondary : DT.Color.textPrimary)
                        .lineLimit(1)
                    if let detail = episodeDetail(episode, isTaken: isTaken) {
                        Text(verbatim: detail)
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTaken)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func episodeDetail(_ episode: MediaItem, isTaken: Bool) -> String? {
        var parts: [String] = []
        if isTaken {
            parts.append(downloadManager.isDownloaded(episode.id) ? String(localized: "Downloaded") : String(localized: "Downloading"))
        } else if episode.userData?.played == true {
            parts.append(String(localized: "Watched"))
        }
        if let ticks = episode.runTimeTicks, ticks > 0 { parts.append(Self.runtimeLabel(ticks: ticks)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func qualityLabel(_ option: DownloadQualityOption) -> String {
        guard let rate = option.videoBitrate else { return option.quality.label }
        return "\(option.quality.label) · \(Self.rateLabel(rate))"
    }

    private func videoLines(_ preview: DownloadManager.DownloadPreview) -> [(label: LocalizedStringKey, value: String)]? {
        var lines: [(label: LocalizedStringKey, value: String)] = []
        if let width = preview.videoWidth, let height = preview.videoHeight {
            lines.append(("Resolution", Self.resolutionLabel(width: width, height: height)))
        }
        if let range = preview.videoRange, !range.isEmpty, range.uppercased() != "SDR" {
            lines.append(("Dynamic Range", Self.rangeLabel(range)))
        }
        if let codec = preview.videoCodec {
            let stream = preview.videoStream
            let extra = [stream?.profile, stream?.bitDepth.map { String(localized: "\($0)-bit") }].compactMap(\.self)
            lines.append(("Codec", ([codec.uppercased()] + extra).joined(separator: " · ")))
        }
        if let bitrate = preview.sourceBitrate { lines.append(("Bitrate", Self.rateLabel(bitrate))) }
        if let container = preview.container { lines.append(("Format", container.uppercased())) }
        return lines
    }

    @ViewBuilder
    private func audioSection(_ preview: DownloadManager.DownloadPreview) -> some View {
        if !preview.audioStreams.isEmpty {
            section("Audio") {
                card {
                    ForEach(Array(preview.audioStreams.enumerated()), id: \.offset) { index, stream in
                        if index > 0 { divider }
                        trackToggle(stream, isOn: isConverted ? audioBinding(stream) : .constant(true), isLocked: !isConverted || isOnlyAudio(stream))
                    }
                }
                Text(isConverted
                     ? "Keep at least one. The first goes into the converted file and the others are added to it."
                     : "The original file keeps every audio track. Pick a lower quality to choose which to keep.")
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func subtitleSection(_ preview: DownloadManager.DownloadPreview) -> some View {
        section("Subtitles") {
            if preview.subtitleStreams.isEmpty {
                card { row("Subtitles", String(localized: "None")) }
            } else {
                card {
                    ForEach(Array(preview.subtitleStreams.enumerated()), id: \.offset) { index, stream in
                        if index > 0 { divider }
                        trackToggle(stream, isOn: subtitleBinding(stream), isLocked: false)
                    }
                }
            }
        }
    }

    private func isOnlyAudio(_ stream: JellyfinMediaStream) -> Bool {
        audioKeys.count == 1 && audioKeys.contains(DownloadTracks.key(stream))
    }

    private func audioBinding(_ stream: JellyfinMediaStream) -> Binding<Bool> {
        let key = DownloadTracks.key(stream)
        return Binding(
            get: { audioKeys.contains(key) },
            set: { isOn in
                if isOn { audioKeys.insert(key) } else if audioKeys.count > 1 { audioKeys.remove(key) }
            })
    }

    private func subtitleBinding(_ stream: JellyfinMediaStream) -> Binding<Bool> {
        let key = DownloadTracks.key(stream)
        return Binding(
            get: { subtitleKeys.contains(key) },
            set: { isOn in
                if isOn { subtitleKeys.insert(key) } else { subtitleKeys.remove(key) }
            })
    }

    private func trackToggle(_ stream: JellyfinMediaStream, isOn: Binding<Bool>, isLocked: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Self.trackTitle(stream))
                    .font(.system(.footnote, design: .default, weight: .medium))
                    .foregroundStyle(DT.Color.textPrimary)
                let tags = [stream.isDefault ? String(localized: "Default") : nil,
                            stream.isForced ? String(localized: "Forced") : nil].compactMap(\.self)
                if !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
        .tint(DT.Color.accent)
        .disabled(isLocked)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(DT.Color.textPrimary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }

    private var divider: some View {
        Divider().overlay(DT.Color.textPrimary.opacity(0.06))
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            Spacer()
            Text(verbatim: value)
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
    }

    /// Only a nudge: it never blocks a tap, and it goes for good once the end has been seen.
    private var scrollHint: some View {
        Label("Scroll for more", systemImage: "chevron.down")
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(DT.Color.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, DT.Spacing.sm)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private func spaceNote(_ message: String, blocks: Bool) -> some View {
        Label {
            Text(message)
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textPrimary)
        } icon: {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(blocks ? DT.Color.palette("F43F5E") : DT.Color.palette("F59E0B"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((blocks ? DT.Color.palette("F43F5E") : DT.Color.palette("F59E0B")).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }

    // MARK: - Labels

    private static func trackTitle(_ stream: JellyfinMediaStream) -> String {
        let title = (stream.displayTitle ?? "").replacingOccurrences(of: " - Default", with: "")
        if !title.isEmpty { return title }
        return stream.language.flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? String(localized: "Unknown")
    }

    private static func rateLabel(_ bitsPerSecond: Int) -> String {
        bitsPerSecond >= 1_000_000
            ? "\((Double(bitsPerSecond) / 1_000_000).formatted(.number.precision(.fractionLength(0...1)))) Mb/s"
            : "\(bitsPerSecond / 1000) Kb/s"
    }

    private static func resolutionLabel(width: Int, height: Int) -> String {
        switch height {
        case 2000...: "4K (\(width)×\(height))"
        case 1000..<2000: "1080p (\(width)×\(height))"
        case 700..<1000: "720p (\(width)×\(height))"
        default: "\(width)×\(height)"
        }
    }

    private static func rangeLabel(_ range: String) -> String {
        switch range.lowercased() {
        case "dolbyvision", "dovi": "Dolby Vision"
        default: range
        }
    }

    private static func runtimeLabel(ticks: Int64) -> String {
        let totalMinutes = Int(Double(ticks) / 10_000_000 / 60)
        return Duration.seconds(totalMinutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
