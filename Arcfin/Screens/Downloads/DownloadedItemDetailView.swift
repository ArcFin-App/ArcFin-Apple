// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence
#if os(macOS)
import AppKit
#endif

struct DownloadedItemDetailView: View {
    let item: DownloadedItem

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var playingItem: DownloadedItem?
    @State private var startOverride: Int64?
    @State private var showDeleteConfirm = false

    private var isResumable: Bool { item.playbackPositionTicks > 0 && !item.played }

    private var dir: URL { DownloadStore.directory(for: item.itemId) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                backdrop

                VStack(alignment: .leading, spacing: DT.Spacing.md) {
                    HStack(spacing: 8) {
                        Text(item.seriesId != nil ? "Episode" : "Movie")
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                        if let year = item.productionYear {
                            Text("· \(String(year))")
                                .font(.system(.caption2))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        if item.runtimeTicks > 0 {
                            Text("· \(Int(item.runtimeTicks / 10_000_000 / 60)) min")
                                .font(.system(.caption2))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        if let rating = item.communityRating, rating > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").font(.system(.caption2))
                                Text(String(format: "%.1f", rating))
                            }
                            .font(.system(.caption2))
                            .foregroundStyle(Color(hex: "f59e0b"))
                        }
                    }

                    if !item.genres.isEmpty {
                        Text(item.genres.joined(separator: " · "))
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            startOverride = nil
                            playingItem = item
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text(isResumable ? "Resume" : "Play")
                            }
                            .font(.system(.callout, design: .default, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                        }
                        .buttonStyle(.plain)

                        if isResumable {
                            Button {
                                startOverride = 0
                                playingItem = item
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(.body, weight: .semibold))
                                    .foregroundStyle(DT.Color.textPrimary)
                                    .frame(width: 48, height: 48)
                                    .background(DT.Color.backgroundSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Start Over")
                        }
                    }

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(.footnote))
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineSpacing(3)
                    }

                    infoRow

                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Download")
                        }
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "EF4444").opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                    }
                    .buttonStyle(.plain)
                }
                .padding(DT.Spacing.pagePad)
            }
        }
        .screenBackground()
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        #if os(iOS)
        .fullScreenCover(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item, startPositionOverride: startOverride)
        }
        #elseif os(macOS)
        // fullScreenCover is unavailable on macOS — OfflinePlayerView has its own in-window
        // fullscreen (F key) now that it has a real macOS video surface, so a sheet is enough.
        .sheet(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item, startPositionOverride: startOverride)
                .frame(minWidth: 900, minHeight: 560)
        }
        #endif
        .alert("Delete this download?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                downloadManager.deleteDownload(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottomLeading) {
            #if canImport(UIKit)
            if let fileName = item.backdropFileName ?? item.posterFileName,
               let uiImage = UIImage(contentsOfFile: dir.appendingPathComponent(fileName).path) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #elseif os(macOS)
            if let fileName = item.backdropFileName ?? item.posterFileName,
               let nsImage = NSImage(contentsOfFile: dir.appendingPathComponent(fileName).path) {
                Image(nsImage: nsImage).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
            #else
            DT.Color.backgroundSecondary
            #endif
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            Text(item.seriesId != nil ? (item.seriesName ?? item.name) : item.name)
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundStyle(.white)
                .padding(DT.Spacing.pagePad)
                .shadow(color: .black.opacity(0.6), radius: 6)
        }
        .frame(height: 220)
        .clipped()
    }

    @ViewBuilder
    private var infoRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Storage")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textPrimary)
            }
            if !item.subtitleLanguages.isEmpty {
                HStack {
                    Text("Subtitles")
                        .font(.system(.caption, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    Spacer()
                    Text(item.subtitleLanguages.joined(separator: ", "))
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
            }
            HStack {
                Text("Downloaded")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                Spacer()
                Text(item.downloadedAt, style: .date)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textPrimary)
            }
        }
        .padding(12)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }
}
