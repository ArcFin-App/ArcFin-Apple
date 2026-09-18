import SwiftUI
import JellyfinAPI
import MediaEngine

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
                    if let method = playbackInfo?.playMethod, method != .directPlay {
                        Text(method.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(method == .transcode ? DT.Color.accent : Color.white.opacity(0.6), in: Capsule())
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

            #if canImport(UIKit) && !os(tvOS)
            AirPlayButton()
                .frame(width: 30, height: 30)

            if pip.isSupported {
                Button { pip.toggle() } label: {
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
            #endif

            Button { showTrackMenu = true } label: {
                Image(systemName: "captions.bubble")
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
                        Task {
                            await player.seek(to: Int64(scrubTicks))
                            isScrubbing = false
                            #if canImport(UIKit)
                            scrubThumbnail = nil
                            #endif
                            scheduleAutoHide()
                        }
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
           let introEnd, currentSeconds < introEnd, currentSeconds > 0.5 {
            return "Skip Intro"
        }
        if UserDefaults.standard.bool(forKey: "skipCredits"),
           let creditsStart, currentSeconds >= creditsStart {
            return "Skip Credits"
        }
        return nil
    }

    private func skipToSegmentEnd() {
        let currentSeconds = Double(player.positionTicks) / 10_000_000
        if let introEnd, currentSeconds < introEnd {
            Task { await player.seek(to: Int64(introEnd * 10_000_000)) }
        } else if let creditsStart, currentSeconds >= creditsStart {
            Task { await finishPlayback() }
        }
    }

    // MARK: - Playback actions

    func togglePlayPause() {
        Task {
            if player.status == .playing { await player.pause() } else { await player.play() }
        }
        toggleControlsVisibilityOnAction()
    }

    func seek(by seconds: Int) {
        let newTicks = max(0, player.positionTicks + Int64(seconds) * 10_000_000)
        Task { await player.seek(to: min(newTicks, player.durationTicks)) }
        toggleControlsVisibilityOnAction()
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
