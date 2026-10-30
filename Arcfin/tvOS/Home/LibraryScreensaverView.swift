// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UIKit
import JellyfinAPI
import ImageCache

/// Open players, paused or not, which the screensaver waits for.
@MainActor
enum ScreensaverHold {
    static var count = 0
}

/// Apple TV doesn't let apps provide a system screensaver, so this is Arcfin's own: after a
/// few idle minutes outside the player, the library's artwork drifts by. Any press ends it.
struct LibraryScreensaverView: View {
    let onDismiss: () -> Void

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("reduceMotion") private var appReduceMotion = false
    @State private var index = 0
    @FocusState private var isFocused: Bool

    private static let slideSeconds = 12.0
    /// After this long the system's own screensaver and sleep can take over again.
    private static let keepAwakeMinutes = 30

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    private var items: [MediaItem] {
        var seen = Set<String>()
        let pool = mediaRepo.recentlyAddedMovies + mediaRepo.recentlyAddedShows + mediaRepo.favorites
            + mediaRepo.watchAgain + mediaRepo.continueWatching + mediaRepo.recentlyAdded
        return pool.filter { item in
            let key = item.seriesId ?? item.id
            return mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920) != nil && seen.insert(key).inserted
        }
    }

    var body: some View {
        Button(action: onDismiss) {
            ZStack(alignment: .bottomLeading) {
                Color.black
                if let item = items.dropFirst(index).first {
                    ScreensaverSlide(item: item, zooms: !reduceMotion, duration: Self.slideSeconds + 2)
                        .id(item.id)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .buttonStyle(ScreensaverButtonStyle())
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onExitCommand(perform: onDismiss)
        .onMoveCommand { _ in onDismiss() }
        .onPlayPauseCommand(perform: onDismiss)
        .accessibilityLabel("Screensaver")
        .accessibilityHint("Press to go back")
        .task { await run() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func run() async {
        UIApplication.shared.isIdleTimerDisabled = true
        let start = Date()
        ImageCache.preheat(urls: items.prefix(6).compactMap { mediaRepo.imageURL(for: $0, type: .backdrop, fillWidth: 1920) })
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.slideSeconds))
            guard !Task.isCancelled else { return }
            if Date().timeIntervalSince(start) > Double(Self.keepAwakeMinutes * 60) {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            guard items.count > 1 else { continue }
            withAnimation(.easeInOut(duration: 1.6)) { index = (index + 1) % items.count }
        }
    }
}

/// One title's backdrop, slowly drifting closer while it's up.
private struct ScreensaverSlide: View {
    let item: MediaItem
    let zooms: Bool
    let duration: Double

    @Environment(MediaRepository.self) private var mediaRepo
    @State private var zoomed = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.black
                }
            }
            .scaleEffect(zoomed ? 1.08 : 1)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)

            caption
                .padding(.leading, 90)
                .padding(.bottom, 80)
        }
        .onAppear {
            guard zooms else { return }
            withAnimation(.linear(duration: duration)) { zoomed = true }
        }
    }

    @ViewBuilder
    private var caption: some View {
        let title = item.type == .episode ? (item.seriesName ?? item.name) : item.name
        VStack(alignment: .leading, spacing: 10) {
            if item.type == .movie || item.type == .series {
                CachedAsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                            .frame(maxWidth: 420, maxHeight: 140, alignment: .leading)
                    } else {
                        titleText(title)
                    }
                }
                .accessibilityLabel(title)
            } else {
                titleText(title)
            }
            if let year = item.productionYear {
                Text(String(year))
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 12)
    }

    private func titleText(_ title: String) -> some View {
        Text(title)
            .font(.system(.title2, design: .default, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
    }
}

/// No focus lift or highlight: the whole screen is the button.
private struct ScreensaverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
