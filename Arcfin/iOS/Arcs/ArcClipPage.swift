// SPDX-License-Identifier: AGPL-3.0-or-later

import JellyfinAPI
import SwiftUI
import UIKit
import AuthCore

/// What a clip page asks its feed to do.
struct ArcClipActions {
    var watchFromHere: (ArcClip) -> Void
    var openTitle: (ArcClip) -> Void
    var share: (ArcClip) -> Void
    var addToPlaylist: (ArcClip) -> Void
    var shuffleShow: (ArcClip) -> Void
    var pictureInPicture: (ArcClip) -> Void
    /// Nil without Seerr: the title on Discover, for what's like it and what comes next.
    var discover: ((ArcClip) -> Void)?
    /// A cold open: the episode from its start.
    var startEpisode: (ArcClip) -> Void = { _ in }
    /// Nil when the server doesn't allow sending scenes.
    var send: ((ArcClip) -> Void)?
    /// A title to request: Seerr's request sheet, and its page.
    var request: (ArcClip) -> Void = { _ in }
    var requestDetails: (ArcClip) -> Void = { _ in }
}

/// One clip, filling the screen: the scene, its title and description at the foot, and the
/// actions down the side. Tap to pause, double-tap to like, hold for double speed.
struct ArcClipPage: View {
    let clip: ArcClip
    let model: ArcsModel
    let isCurrent: Bool
    let bottomInset: Double
    let pictureInPictureRequest: Int
    let actions: ArcClipActions

    @AppStorage(ArcsSettings.subtitlesKey) private var subtitlesOn = false
    @State private var hearts: [ArcHeart] = []
    @State private var isFast = false
    @State private var cues: [ArcSubtitleCue] = []
    @State private var loadedCues = false
    @State private var descriptionOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var playback: ArcPlayback? { model.playback(for: clip) }
    private var showsSubtitles: Bool { subtitlesOn }

    var body: some View {
        ZStack {
            Color.black
            if let playback {
                ArcVideoView(playback: playback, framing: model.framing, isCurrent: isCurrent, pictureInPictureRequest: pictureInPictureRequest)
                    .opacity(playback.isReady ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: playback.isReady)
                if !playback.isReady && !playback.failed { ProgressView().tint(.white).controlSize(.large) }
                if playback.failed { failure }
            }
            gestureLayer
            ForEach(hearts) { heart in ArcHeartBurst(heart: heart, reduceMotion: reduceMotion) }
            if isCurrent, model.isPaused { pausedBadge }
            if isFast { fastBadge }
            overlay
        }
        .clipped()
        .task(id: isCurrent && showsSubtitles) { await loadCues() }
        .onChange(of: isCurrent) { _, current in if !current { descriptionOpen = false; isFast = false } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ArcText.accessibilitySummary(clip))
        .accessibilityAction(named: clip.liked ? Text("Unlike") : Text("Like")) { model.toggleLike(clip) }
        .accessibilityAction(named: Text("Watch from Here")) { actions.watchFromHere(clip) }
        .accessibilityAction(named: Text("View Title")) { actions.openTitle(clip) }
        .accessibilityAction(.magicTap) { model.isPaused.toggle() }
    }

    // MARK: Gestures

    private var gestureLayer: some View {
        ArcTapSurface(
            onTap: { model.isPaused.toggle() },
            onDoubleTap: { doubleTap(at: $0) },
            onHold: { holding in
                guard isCurrent, !model.isPaused || !holding else { return }
                isFast = holding
                playback?.setFast(holding)
                if holding { HapticManager.impact(.light) }
            })
            .accessibilityHidden(true)
    }

    private func doubleTap(at location: CGPoint) {
        model.like(clip)
        HapticManager.impact(.medium)
        let heart = ArcHeart(location: location, angle: .degrees(Double.random(in: -18...18)))
        hearts.append(heart)
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            hearts.removeAll { $0.id == heart.id }
        }
    }

    // MARK: Overlay

    private var overlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 10) {
                ArcClipInfo(clip: clip, showsReason: model.showsReasons, descriptionOpen: $descriptionOpen,
                            watchFromHere: { actions.watchFromHere(clip) }, openTitle: { actions.openTitle(clip) },
                            startEpisode: clip.isColdOpen ? { actions.startEpisode(clip) } : nil)
                    .anchorPreference(key: ArcTitleTop.self, value: .top) { $0 }
                ArcActionRail(clip: clip, model: model, actions: actions)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            if let playback {
                ArcProgressBar(playback: playback)
                    .padding(.bottom, bottomInset)
            }
        }
        // Subtitles centred across the screen, their foot just above the title (the rail beside it is
        // taller, so above the whole row would put them mid-screen).
        .overlayPreferenceValue(ArcTitleTop.self) { anchor in
            GeometryReader { proxy in
                if showsSubtitles, let playback, isCurrent, let anchor {
                    ArcSubtitleOverlay(cues: cues, time: playback.elapsed)
                        .padding(.horizontal, 24)
                        .frame(width: proxy.size.width, height: max(0, proxy[anchor].y - 8), alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(descriptionOpen ? 0.85 : 0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: descriptionOpen ? 440 : 280)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.25), value: descriptionOpen)
        }
    }

    private var pausedBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 44))
            .foregroundStyle(.white.opacity(0.85))
            .shadow(radius: 12)
            .allowsHitTesting(false)
            .transition(.scale.combined(with: .opacity))
            .accessibilityHidden(true)
    }

    private var fastBadge: some View {
        VStack {
            Label("2×", systemImage: "forward.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
                .padding(.top, 120)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var failure: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text("This scene couldn't be loaded.").font(.headline)
        }
        .foregroundStyle(.white.opacity(0.8))
    }

    private func loadCues() async {
        guard isCurrent, showsSubtitles, !loadedCues, !clip.subtitles.isEmpty, let (credential, header) = model.auth() else { return }
        loadedCues = true
        cues = await ArcSubtitles.load(for: clip, credential: credential, authHeader: header)
    }
}

// MARK: - Info

/// The title, which scene it is, why it's here and the description, which opens with "more".
struct ArcClipInfo: View {
    let clip: ArcClip
    let showsReason: Bool
    @Binding var descriptionOpen: Bool
    let watchFromHere: () -> Void
    let openTitle: () -> Void
    /// A cold open's main button: the episode from its start, rather than from this moment.
    var startEpisode: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sender = clip.sentBy {
                VStack(alignment: .leading, spacing: 2) {
                    Label { Text("From \(sender)") } icon: { Image(systemName: "paperplane.fill") }
                        .font(.caption.weight(.bold))
                    if let note = clip.sentNote, !note.isEmpty {
                        Text(verbatim: note).font(.caption).lineLimit(2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 4)
            }
            Button(action: openTitle) {
                Text(verbatim: clip.seriesName ?? clip.name)
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the title's page."))
            if let line = ArcText.sceneLine(clip) {
                Text(verbatim: line)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            if showsReason, let reason = ArcText.reason(clip) {
                Label { Text(reason) } icon: { Image(systemName: "sparkles") }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .labelStyle(.titleAndIcon)
            }
            if let overview = clip.overview, !overview.isEmpty {
                ArcDescription(text: overview, isOpen: $descriptionOpen)
            }
            HStack(spacing: 6) {
                if let startEpisode {
                    Button(action: startEpisode) {
                        Label("Start Episode", systemImage: "play.fill")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                } else {
                    Button(action: watchFromHere) {
                        Label("Watch from Here", systemImage: "play.fill")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                }
                Button(action: openTitle) {
                    Label("View Title", systemImage: "info.circle")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Two lines with "more" after them when there's more; opened, the whole description scrolls.
struct ArcDescription: View {
    let text: String
    @Binding var isOpen: Bool
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isOpen {
                ScrollView {
                    Text(verbatim: text)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .scrollIndicators(.hidden)
            } else {
                Text(verbatim: text)
                    .font(.footnote)
                    .lineLimit(2)
                    .background {
                        // The whole text laid out unseen, to tell whether two lines cut it short.
                        ViewThatFits(in: .vertical) {
                            Text(verbatim: text).font(.footnote).hidden().onAppear { isTruncated = false }
                            Color.clear.onAppear { isTruncated = true }
                        }
                    }
            }
            if isTruncated || isOpen {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { isOpen.toggle() }
                } label: {
                    isOpen ? Text("less") : Text("more")
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
                .buttonStyle(.plain)
                .accessibilityLabel(isOpen ? Text("Show Less") : Text("Show More"))
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .contentShape(Rectangle())
        .onTapGesture { if isTruncated || isOpen { withAnimation(.easeInOut(duration: 0.25)) { isOpen.toggle() } } }
    }
}

// MARK: - Rail

/// Like, not for me, favourite, add, share and more, down the trailing edge.
struct ArcActionRail: View {
    let clip: ArcClip
    let model: ArcsModel
    let actions: ArcClipActions

    var body: some View {
        VStack(spacing: 12) {
            ArcRailButton(icon: clip.liked ? "heart.fill" : "heart", title: clip.likeCount > 0 ? "\(clip.likeCount)" : String(localized: "Like"),
                          tint: clip.liked ? DT.Color.accent : .white, label: clip.liked ? "Unlike" : "Like") {
                HapticManager.impact(.light)
                model.toggleLike(clip)
            }
            ArcRailButton(icon: clip.disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", title: String(localized: "Not for Me"),
                          tint: .white, label: clip.disliked ? "Undo Not for Me" : "Not for Me") { model.toggleDislike(clip) }
            ArcReactionButton(clip: clip, model: model)
            ArcRailButton(icon: clip.isFavorite ? "star.fill" : "star", title: String(localized: "Favourite"),
                          tint: clip.isFavorite ? .yellow : .white, label: clip.isFavorite ? "Remove from Favourites" : "Add to Favourites") {
                model.toggleFavorite(clip)
            }
            ArcRailButton(icon: "text.badge.plus", title: String(localized: "Playlist"), tint: .white, label: "Add to Playlist") {
                actions.addToPlaylist(clip)
            }
            if model.canShare || actions.send != nil {
                Menu {
                    if model.canShare {
                        Button { actions.share(clip) } label: { Label("Share Video", systemImage: "square.and.arrow.up") }
                    }
                    if let send = actions.send {
                        Button { send(clip) } label: { Label("Send to Someone", systemImage: "paperplane") }
                    }
                } label: {
                    ArcRailIcon(icon: "square.and.arrow.up", title: String(localized: "Share"), tint: .white)
                }
                .accessibilityLabel(Text("Share This Scene"))
            }
            Menu {
                ArcMoreMenu(clip: clip, model: model, actions: actions)
            } label: {
                ArcRailIcon(icon: "ellipsis", title: String(localized: "More"), tint: .white)
            }
            .accessibilityLabel(Text("More"))
        }
        .frame(width: 52)
    }
}

/// Everything else for a clip: show less of it, hide it, report it, and the player extras.
struct ArcMoreMenu: View {
    let clip: ArcClip
    let model: ArcsModel
    let actions: ArcClipActions
    @AppStorage(ArcsSettings.subtitlesKey) private var subtitlesOn = false

    var body: some View {
        Section {
            if clip.isEpisode || clip.seriesId != nil {
                Button { actions.shuffleShow(clip) } label: { Label("More Scenes from This Show", systemImage: "shuffle") }
            } else {
                Button { actions.shuffleShow(clip) } label: { Label("More Scenes from This Film", systemImage: "shuffle") }
            }
            Button { model.markWatched(clip) } label: { Label("Mark as Watched", systemImage: "checkmark.circle") }
            if let discover = actions.discover {
                Button { discover(clip) } label: { Label("More Like This on Discover", systemImage: "sparkle.magnifyingglass") }
            }
        }
        Section {
            if !clip.subtitles.isEmpty {
                Button { subtitlesOn.toggle() } label: {
                    Label(subtitlesOn ? "Turn Subtitles Off" : "Turn Subtitles On", systemImage: subtitlesOn ? "captions.bubble.fill" : "captions.bubble")
                }
            }
            Button { actions.pictureInPicture(clip) } label: { Label("Picture in Picture", systemImage: "pip.enter") }
        }
        Section {
            Button { model.keepOut(clip, .notNow) } label: { Label("Not Now", systemImage: "clock.arrow.circlepath") }
            Button { model.keepOut(clip, .fewerFromSeries) } label: {
                Label(clip.isEpisode ? "Fewer from This Show" : "Fewer Like This", systemImage: "minus.circle")
            }
            Button(role: .destructive) { model.keepOut(clip, .hide) } label: {
                Label(clip.isEpisode ? "Hide This Show" : "Hide This Film", systemImage: "eye.slash")
            }
            Button(role: .destructive) { model.keepOut(clip, .report) } label: { Label("Report a Bad Scene", systemImage: "exclamationmark.bubble") }
        }
    }
}

struct ArcRailButton: View {
    let icon: String
    let title: String
    let tint: Color
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { ArcRailIcon(icon: icon, title: title, tint: tint) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label))
    }
}

struct ArcRailIcon: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: Circle())
            Text(verbatim: title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
        .frame(width: 52)
    }
}

// MARK: - Progress

/// A thin line at the foot; drag along it to move through the clip.
struct ArcProgressBar: View {
    let playback: ArcPlayback
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { proxy in
            let fraction = dragging ?? playback.progress
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: max(0, proxy.size.width * fraction))
            }
            .frame(height: dragging == nil ? 3 : 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                dragging = min(1, max(0, value.location.x / max(1, proxy.size.width)))
            }.onEnded { _ in
                if let dragging { playback.seek(to: dragging) }
                dragging = nil
            })
            .animation(.easeOut(duration: 0.15), value: dragging == nil)
        }
        .frame(height: 22)
        .padding(.horizontal, 8)
        .accessibilityElement()
        .accessibilityLabel(Text("Scene Position"))
        .accessibilityValue(Text(Duration.seconds(playback.elapsed).formatted(.time(pattern: .minuteSecond))))
        .accessibilityAdjustableAction { direction in
            let step = 5 / max(1, playback.duration)
            playback.seek(to: playback.progress + (direction == .increment ? step : -step))
        }
    }
}

// MARK: - Heart

struct ArcHeart: Identifiable, Equatable {
    let id = UUID()
    let location: CGPoint
    let angle: Angle
}

struct ArcHeartBurst: View {
    let heart: ArcHeart
    let reduceMotion: Bool
    @State private var popped = false
    @State private var faded = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 80))
            .foregroundStyle(DT.Color.accent.gradient)
            .shadow(color: .black.opacity(0.3), radius: 10)
            .rotationEffect(heart.angle)
            .scaleEffect(popped ? 1 : 0.4)
            .opacity(faded ? 0 : 1)
            .offset(y: faded && !reduceMotion ? -70 : 0)
            .position(heart.location)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { popped = true }
                withAnimation(.easeOut(duration: 0.45).delay(0.4)) { faded = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Text

enum ArcText {
    static func emoji(_ reaction: ArcReaction) -> String {
        switch reaction {
        case .funny: "😂"
        case .wow:   "😮"
        case .sad:   "😢"
        }
    }

    static func label(_ mood: ArcsMood) -> LocalizedStringResource {
        switch mood {
        case .funny:    "Funny"
        case .action:   "Action"
        case .feelgood: "Feel-Good"
        case .scary:    "Scary"
        case .drama:    "Drama"
        case .scifi:    "Sci-Fi"
        }
    }

    static func label(_ reaction: ArcReaction) -> LocalizedStringResource {
        switch reaction {
        case .funny: "Funny"
        case .wow:   "Wow"
        case .sad:   "Sad"
        }
    }

    /// "S4 · E12 · The Heist" for an episode, "2019 · The Heist" for a film.
    static func sceneLine(_ clip: ArcClip) -> String? {
        var parts: [String] = []
        if clip.isEpisode {
            if let season = clip.seasonNumber { parts.append(String(localized: "S\(season)")) }
            if let episode = clip.episodeNumber { parts.append(String(localized: "E\(episode)")) }
            if clip.seriesName != nil, !clip.name.isEmpty, clip.chapterName == nil { parts.append(clip.name) }
        } else if let year = clip.year {
            parts.append(String(year))
        }
        if let chapter = clip.chapterName, !chapter.isEmpty { parts.append(chapter) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func reason(_ clip: ArcClip) -> String? {
        guard let reason = clip.reason else { return nil }
        switch reason.kind {
        case .because:
            guard let seed = reason.seedName else { return String(localized: "Picked for you") }
            return String(localized: "Because you liked \(seed)")
        case .continue: return String(localized: "From something you're watching")
        case .discover: return String(localized: "Something you haven't watched")
        case .popular:  return String(localized: "Popular on your server")
        case .new:      return String(localized: "New on your server")
        case .explore:  return String(localized: "Something different")
        case .top:      return String(localized: "Picked for you")
        case .request:
            guard let seed = reason.seedName else { return String(localized: "Not on your server yet") }
            return String(localized: "Not on your server yet · like \(seed)")
        case .series, .liked, .sent, .unknown: return nil
        }
    }

    static func accessibilitySummary(_ clip: ArcClip) -> Text {
        let title = clip.seriesName ?? clip.name
        if let line = sceneLine(clip) { return Text(verbatim: "\(title), \(line)") }
        return Text(verbatim: title)
    }
}

/// Tap, double tap and hold over the scene, with UIKit's recognizers: a single tap waits until a
/// double tap is ruled out, so liking never also pauses and resumes.
struct ArcTapSurface: UIViewRepresentable {
    var onTap: () -> Void
    var onDoubleTap: (CGPoint) -> Void
    var onHold: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        single.require(toFail: double)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.35
        hold.allowableMovement = 30
        [double, single, hold].forEach(view.addGestureRecognizer)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.surface = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(surface: self) }

    @MainActor
    final class Coordinator: NSObject {
        var surface: ArcTapSurface

        init(surface: ArcTapSurface) { self.surface = surface }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            surface.onTap()
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            surface.onDoubleTap(recognizer.location(in: recognizer.view))
        }

        @objc func held(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began: surface.onHold(true)
            case .ended, .cancelled, .failed: surface.onHold(false)
            default: break
            }
        }
    }
}

/// Where the title column starts, for placing the subtitles just above it.
private struct ArcTitleTop: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

/// Funny, wow or sad, beside the like; the counts show once several people chose one.
struct ArcReactionButton: View {
    let clip: ArcClip
    let model: ArcsModel

    var body: some View {
        Menu {
            ForEach(ArcReaction.allCases, id: \.self) { reaction in
                Button { model.react(clip, reaction) } label: {
                    let count = clip.reactions[reaction.rawValue] ?? 0
                    let name = String(localized: ArcText.label(reaction))
                    Text(verbatim: count > 0 ? "\(ArcText.emoji(reaction)) \(name)  \(count)" : "\(ArcText.emoji(reaction)) \(name)")
                }
            }
        } label: {
            VStack(spacing: 3) {
                Group {
                    if let mine = clip.myReaction {
                        Text(verbatim: ArcText.emoji(mine)).font(.system(size: 20))
                    } else {
                        Image(systemName: "face.smiling").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 40, height: 40)
                .glassEffect(.regular.interactive(), in: Circle())
                Text("React").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            }
            .shadow(color: .black.opacity(0.4), radius: 4)
            .frame(width: 52)
        }
        .accessibilityLabel(clip.myReaction.map { Text("Reaction: \(Text(ArcText.label($0)))") } ?? Text("React"))
    }
}
