// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import CastKit

/// The compact "now casting" bar shown above the tab bar (via tabViewBottomAccessory) while a
/// Cast session has something loaded and the player screen isn't open — so playback on the
/// TV can be paused or stopped without reopening a title, and a tap opens its player again.
struct CastMiniController: View {
    private var cast: CastManager { CastManager.shared }

    var body: some View {
        HStack(spacing: 12) {
            Button { openPlayer() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(cast.nowPlayingTitle ?? "Casting")
                            .font(.system(.footnote, design: .default, weight: .semibold))
                            .lineLimit(1)
                        Text("Casting to \(cast.deviceName ?? "TV")")
                            .font(.system(.caption2))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .disabled(cast.nowPlayingItemID == nil)
            .accessibilityHint("Opens the player")

            Button { cast.togglePlayPause() } label: {
                Image(systemName: cast.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(.title3))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(cast.isPaused ? "Play" : "Pause")

            Button { cast.endSession() } label: {
                Image(systemName: "xmark")
                    .font(.system(.body, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop casting")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    /// Something another device cast has no item ID, so there's no player to open for it.
    private func openPlayer() {
        guard let id = cast.nowPlayingItemID else { return }
        WatchRoute.open(id: id)
    }
}
