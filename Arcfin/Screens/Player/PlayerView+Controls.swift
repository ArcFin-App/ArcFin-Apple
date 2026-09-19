import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine
import CastKit

extension PlayerView {

    // MARK: - Controls overlay

    var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.7),
                    .init(color: .black.opacity(0.65), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let hdrLabel {
                        Text(hdrLabel)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(hdrIsToneMapped ? .black : .white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(
                                hdrIsToneMapped ? Color(hex: "F59E0B") : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(.white.opacity(hdrIsToneMapped ? 0 : 0.4), lineWidth: 1)
                            )
                    }
                }
                if let subtitle = episodeSubtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            #if canImport(GoogleCast)
            if castEnabled, CastManager.shared.isCastAvailable {
                CastButton()
                    .frame(width: 24, height: 24)
            }
            #endif

            #if canImport(UIKit) && !os(tvOS)
            AirPlayButton()
                .frame(width: 30, height: 30)

            if isPiPSupported {
                Button { togglePiP() } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
            }
            #endif

            #if canImport(UIKit) && !os(tvOS)
            Button { toggleOrientation() } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }

            Button { isFillScreen.toggle() } label: {
                Image(systemName: isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isFillScreen ? DT.Color.accent : .white)
                    .frame(width: 32, height: 32)
            }
            #endif

            if chapterListEnabled, !chapters.isEmpty {
                Button { showChapterMenu = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
            }

            #if !os(tvOS)
            if syncPlayEnabled {
                Button { showSyncPlayMenu = true } label: {
                    Image(systemName: syncPlayManager.isInGroup ? "person.2.wave.2.fill" : "person.2.wave.2")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(syncPlayManager.isInGroup ? DT.Color.accent : .white)
                        .frame(width: 32, height: 32)
                }
            }
            #endif

            Button { showTrackMenu = true } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }

            Button { showRateMenu = true } label: {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }

            Button { showQualityMenu = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
    }

    private var episodeSubtitle: String? {
        guard item.type == .episode, let series = item.seriesName else { return nil }
        let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
        let e = item.indexNumber.map { "E\($0)" } ?? ""
        return [series, [s, e].joined()].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - HDR / Dolby Vision badge

    /// The transcode profile only ever outputs h264/SDR (see JellyfinPlaybackClient's
    /// TranscodingProfiles) — an HDR/DV source that gets transcoded is always tone-mapped
    /// down to SDR, which is worth surfacing since it's a visible quality loss the user
    /// didn't ask for.
    private var hdrIsToneMapped: Bool {
        (playbackInfo?.isHDR ?? false) && playbackInfo?.playMethod == .transcode
    }

    private var hdrLabel: String? {
        guard let info = playbackInfo, info.isHDR else { return nil }
        if hdrIsToneMapped { return "HDR → SDR" }
        return info.isDolbyVision ? "DOLBY VISION" : "HDR"
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            scrubber

            HStack {
                Text(timeLabel(ticks: isScrubbing ? Int64(scrubTicks) : player.positionTicks))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))

                Spacer()

                HStack(spacing: 28) {
                    Button { seek(by: -10) } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 20)).foregroundStyle(.white)
                    }
                    Button { togglePlayPause() } label: {
                        Image(systemName: player.status == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    Button { seek(by: 10) } label: {
                        Image(systemName: "goforward.10").font(.system(size: 20)).foregroundStyle(.white)
                    }
                }

                Spacer()

                Text(remainingLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, 24)
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            let duration = max(player.durationTicks, 1)
            let fraction = Double(isScrubbing ? Int64(scrubTicks) : player.positionTicks) / Double(duration)
            let thumbX = proxy.size.width * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                Capsule().fill(DT.Color.accent)
                    .frame(width: thumbX, height: 4)

                // Some sources report duplicate chapter start times — id'd by array offset
                // rather than startPositionTicks so SwiftUI never sees a colliding identity.
                ForEach(Array(chapters.dropFirst().enumerated()), id: \.offset) { _, chapter in
                    let x = proxy.size.width * min(max(Double(chapter.startPositionTicks) / Double(duration), 0), 1)
                    Rectangle()
                        .fill(.black.opacity(0.5))
                        .frame(width: 2, height: 4)
                        .offset(x: x - 1)
                }

                Circle().fill(.white)
                    .frame(width: isScrubbing ? 16 : 10, height: isScrubbing ? 16 : 10)
                    .offset(x: thumbX - (isScrubbing ? 8 : 5))

                #if canImport(UIKit)
                if isScrubbing, trickplayLoader != nil {
                    trickplayPreview
                        .offset(x: min(max(thumbX - 70, 0), proxy.size.width - 140), y: -100)
                }
                #endif
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            #if canImport(UIKit) && !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing { HapticManager.impact(.light) }
                        isScrubbing = true
                        hideControlsTask?.cancel()
                        let fraction = min(max(value.location.x / proxy.size.width, 0), 1)
                        scrubTicks = Double(player.durationTicks) * fraction
                        #if canImport(UIKit)
                        updateScrubThumbnail()
                        #endif
                    }
                    .onEnded { _ in
                        performSeek(to: Int64(scrubTicks))
                        isScrubbing = false
                        #if canImport(UIKit)
                        scrubThumbnail = nil
                        #endif
                        scheduleAutoHide()
                    }
            )
            #endif
        }
        .frame(height: 20)
    }

    #if canImport(UIKit)
    private var trickplayPreview: some View {
        Group {
            if let scrubThumbnail {
                Image(uiImage: scrubThumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
        .frame(width: 140, height: 79)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 1))
        .shadow(radius: 8)
        .allowsHitTesting(false)
    }

    private func updateScrubThumbnail() {
        // 2s buckets — fetching a fresh crop on every pixel of drag would hammer the loader.
        let bucket = Int(scrubTicks / (2 * 10_000_000))
        guard bucket != lastThumbnailBucket, let loader = trickplayLoader else { return }
        lastThumbnailBucket = bucket
        let ticks = Int64(scrubTicks)
        Task {
            let image = await loader.thumbnail(forPositionTicks: ticks)
            guard isScrubbing else { return }
            scrubThumbnail = image
        }
    }
    #endif

    private var remainingLabel: String {
        let remaining = max(player.durationTicks - player.positionTicks, 0)
        return "-" + timeLabel(ticks: remaining)
    }

    private func timeLabel(ticks: Int64) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Chapters

    var chapterListSheet: some View {
        List {
            ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                let isCurrent = currentChapterIndex == index
                Button {
                    showChapterMenu = false
                    jumpToChapter(chapter)
                } label: {
                    HStack {
                        Text(chapter.name ?? "Chapter \(index + 1)")
                            .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? DT.Color.accent : DT.Color.textPrimary)
                        Spacer()
                        Text(timeLabel(ticks: chapter.startPositionTicks))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private var currentChapterIndex: Int? {
        var result: Int?
        for (index, chapter) in chapters.enumerated() where chapter.startPositionTicks <= player.positionTicks {
            result = index
        }
        return result
    }

    private func jumpToChapter(_ chapter: MediaChapter) {
        Task { await player.seek(to: chapter.startPositionTicks) }
        HapticManager.impact(.light)
    }

    // MARK: - SyncPlay

    #if !os(tvOS)
    var syncPlaySheet: some View {
        NavigationStack {
            Group {
                if syncPlayManager.isInGroup {
                    List {
                        Section("Group") {
                            LabeledContent("Name", value: syncPlayManager.groupName ?? "—")
                        }
                        Section {
                            Button(role: .destructive) {
                                leaveSyncPlayGroup()
                            } label: {
                                Text("Leave Group")
                            }
                        }
                    }
                } else {
                    List {
                        Section("Create a Group") {
                            TextField("Group name", text: $syncPlayGroupNameInput)
                            Button {
                                createSyncPlayGroup()
                            } label: {
                                if isSyncPlayBusy { ProgressView() } else { Text("Create") }
                            }
                            .disabled(syncPlayGroupNameInput.trimmingCharacters(in: .whitespaces).isEmpty || isSyncPlayBusy)
                        }
                        Section {
                            if syncPlayManager.availableGroups.isEmpty {
                                Text(syncPlayManager.isRefreshingGroups ? "Looking for groups…" : "No joinable groups right now.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(DT.Color.textSecondary)
                            } else {
                                ForEach(syncPlayManager.availableGroups) { group in
                                    Button {
                                        joinSyncPlayGroup(group)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.groupName).foregroundStyle(DT.Color.textPrimary)
                                            Text("\(group.participants.count) watching" + (group.playingItemName.map { " · \($0)" } ?? ""))
                                                .font(.system(size: 11))
                                                .foregroundStyle(DT.Color.textSecondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Join a Group")
                        } footer: {
                            Text("Everyone in a group needs \(item.name) already open in their own player — SyncPlay keeps play, pause, and seek in sync from there.")
                        }
                    }
                    .task { await refreshSyncPlayGroups() }
                    .refreshable { await refreshSyncPlayGroups() }
                }
            }
            .navigationTitle("SyncPlay")
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSyncPlayMenu = false }
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

    private func refreshSyncPlayGroups() async {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        await syncPlayManager.refreshGroups(credential: credential, authHeader: authHeader)
    }

    private func createSyncPlayGroup() {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        let name = syncPlayGroupNameInput.trimmingCharacters(in: .whitespaces)
        isSyncPlayBusy = true
        Task {
            await syncPlayManager.createGroup(
                credential: credential, authHeader: authHeader, groupName: name,
                itemId: item.id, startPositionTicks: player.positionTicks
            )
            isSyncPlayBusy = false
        }
    }

    private func joinSyncPlayGroup(_ group: SyncPlayGroupInfo) {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        isSyncPlayBusy = true
        Task {
            await syncPlayManager.joinGroup(
                group, credential: credential, authHeader: authHeader,
                itemId: item.id, startPositionTicks: player.positionTicks
            )
            isSyncPlayBusy = false
        }
    }

    private func leaveSyncPlayGroup() {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        syncPlayManager.leaveGroup(credential: credential, authHeader: authHeader)
    }
    #endif

    // MARK: - Skip intro/credits

    var skipButton: some View {
        Group {
            if let label = skipButtonLabel {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { skipToSegmentEnd() } label: {
                            HStack(spacing: 6) {
                                Text(label).font(.system(size: 14, weight: .semibold))
                                Image(systemName: "forward.fill").font(.system(size: 12))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                            .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.15), lineWidth: 1))
                        }
                        .padding(.trailing, DT.Spacing.pagePad)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
    }

    private var skipButtonLabel: String? {
        guard UserDefaults.standard.bool(forKey: "skipIntro") || UserDefaults.standard.bool(forKey: "skipCredits") else { return nil }
        let currentSeconds = Double(player.positionTicks) / 10_000_000
          if UserDefaults.standard.bool(forKey: "skipIntro"),
              let introEnd = introEnd, currentSeconds < introEnd, currentSeconds > 0.5 {
            return "Skip Intro"
        }
          if UserDefaults.standard.bool(forKey: "skipCredits"),
              let creditsStart = creditsStart, currentSeconds >= creditsStart {
            return "Skip Credits"
        }
        return nil
    }

    // MARK: - Up Next

    func upNextCard(_ next: MediaItem) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    if let url = mediaRepo.imageURL(for: next, type: .thumb, fillWidth: 240) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: DT.Color.backgroundSecondary
                            }
                        }
                        .frame(width: 100, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Up Next")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(DT.Color.accent)
                        Text(next.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let s = next.parentIndexNumber, let e = next.indexNumber {
                            Text("S\(s) · E\(e)")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    VStack(spacing: 10) {
                        Button { playNextEpisode() } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 30, height: 30)
                                .background(.white, in: Circle())
                        }
                        Button { dismissUpNext() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.15), lineWidth: 1))
                .frame(maxWidth: 340)
            }
            .padding(.trailing, DT.Spacing.pagePad)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(DT.Animation.fast, value: showUpNext)
    }

    // MARK: - Are you still watching

    var stillWatchingOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(DT.Color.accent)
                VStack(spacing: 6) {
                    Text("Are you still watching?")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    if let pendingAutoAdvanceEpisode = pendingAutoAdvanceEpisode {
                        Text("Playback paused before \(pendingAutoAdvanceEpisode.name)")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                VStack(spacing: 12) {
                    Button { continueAfterStillWatchingPrompt() } label: {
                        Text("Continue Watching")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                    }
                    .buttonStyle(.plain)

                    Button { stopAfterStillWatchingPrompt() } label: {
                        Text("Stop")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 280)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Casting

    #if canImport(GoogleCast)
    var castingOverlay: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "tv")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                Text("Casting to \(CastManager.shared.deviceName ?? "TV")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    CastManager.shared.endSession()
                } label: {
                    Text("Stop")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 60)
            Spacer()
        }
        .transition(.opacity)
    }
    #endif

    private func skipToSegmentEnd() {
        let currentSeconds = Double(player.positionTicks) / 10_000_000
        if let introEnd = introEnd, currentSeconds < introEnd {
            Task { await player.seek(to: Int64(introEnd * 10_000_000)) }
        } else if let creditsStart = creditsStart, currentSeconds >= creditsStart {
            Task { await finishPlayback() }
        }
    }

    // MARK: - Playback actions

    func togglePlayPause() {
        // A manual play/pause is proof someone's actually there — same signal a manual
        // Up Next tap gives, so it resets the "are you still watching" streak too.
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        #if canImport(GoogleCast)
        if CastManager.shared.isConnected {
            // The receiver, not the local player, is the one actually playing — control
            // it instead.
            CastManager.shared.togglePlayPause()
            toggleControlsVisibilityOnAction()
            return
        }
        #endif
        #if !os(tvOS)
        if syncPlayManager.isInGroup, let credential = authManager.state.credential {
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            if player.status == .playing {
                syncPlayManager.requestPause(credential: credential, authHeader: authHeader)
            } else {
                syncPlayManager.requestPlay(credential: credential, authHeader: authHeader)
            }
            toggleControlsVisibilityOnAction()
            return
        }
        #endif
        Task {
            if player.status == .playing { await player.pause() } else { await player.play() }
        }
        toggleControlsVisibilityOnAction()
    }

    func seek(by seconds: Int) {
        let newTicks = min(max(0, player.positionTicks + Int64(seconds) * 10_000_000), player.durationTicks)
        performSeek(to: newTicks)
        toggleControlsVisibilityOnAction()
    }

    /// Routes through SyncPlay's Seek command when in a group (applied once it echoes back
    /// over the WebSocket, same as every other group member sees it) instead of seeking the
    /// local player directly — see PlayerView.applySyncPlayCommand.
    func performSeek(to ticks: Int64) {
        #if canImport(GoogleCast)
        if CastManager.shared.isConnected {
            CastManager.shared.seek(toSeconds: Double(ticks) / 10_000_000)
            return
        }
        #endif
        #if !os(tvOS)
        if syncPlayManager.isInGroup, let credential = authManager.state.credential {
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            syncPlayManager.requestSeek(credential: credential, authHeader: authHeader, positionTicks: ticks)
            return
        }
        #endif
        Task { await player.seek(to: ticks) }
    }

    private func toggleControlsVisibilityOnAction() {
        if !isControlsVisible { withAnimation(DT.Animation.fast) { isControlsVisible = true } }
        scheduleAutoHide()
    }

    // MARK: - Error / feedback views

    func networkToastView(_ text: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.system(size: 12, weight: .medium))
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

    func subtitleOverlay(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 24)
                .padding(.bottom, isControlsVisible ? 110 : 32)
        }
        .allowsHitTesting(false)
        .animation(DT.Animation.fast, value: isControlsVisible)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "EF4444"))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DT.Color.accent)
        }
        .padding(24)
        .frame(maxWidth: 320)
    }

    #if canImport(UIKit) && !os(tvOS)
    @ViewBuilder
    var dragAxisIndicator: some View {
        if let dragAxis {
            let isBrightness = dragAxis == .brightness
            HStack {
                if !isBrightness { Spacer() }
                VStack(spacing: 10) {
                    Image(systemName: isBrightness
                        ? (dragValue < 0.5 ? "sun.min.fill" : "sun.max.fill")
                        : (dragValue < 0.01 ? "speaker.slash.fill" : dragValue < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"))
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                    ZStack(alignment: .bottom) {
                        Capsule().fill(.white.opacity(0.2)).frame(width: 6, height: 90)
                        Capsule().fill(.white).frame(width: 6, height: 90 * dragValue)
                    }
                    Text("\(Int(dragValue * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(14)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                if isBrightness { Spacer() }
            }
            .padding(.horizontal, 32)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }
    #endif

    func seekFeedbackView(_ feedback: SeekFeedback) -> some View {
        HStack {
            if !feedback.forward { Spacer() }
            VStack(spacing: 4) {
                Image(systemName: feedback.forward ? "goforward.10" : "gobackward.10")
                    .font(.system(size: 28))
                Text("10s")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(.black.opacity(0.4), in: Circle())
            if feedback.forward { Spacer() }
        }
        .padding(.horizontal, 40)
        .transition(.opacity)
        .allowsHitTesting(false)
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

    var body: some View {
        List {
            if !audioStreams.isEmpty {
                Section("Audio") {
                    ForEach(audioStreams, id: \.index) { stream in
                        trackRow(label(for: stream), isSelected: stream.index == selectedAudioIndex) {
                            onSelectAudio(stream.index)
                        }
                    }
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
            }
        }
        #if canImport(UIKit) && !os(tvOS)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .background(DT.Color.backgroundPrimary)
    }

    private func trackRow(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(DT.Color.accent)
                }
            }
        }
        .listRowBackground(DT.Color.backgroundSecondary)
    }

    private func label(for stream: JellyfinMediaStream) -> String {
        if let title = stream.displayTitle, !title.isEmpty { return title }
        let parts = [stream.language, stream.codec?.uppercased()].compactMap { $0 }
        return parts.isEmpty ? "Track \(stream.index)" : parts.joined(separator: " · ")
    }
}
