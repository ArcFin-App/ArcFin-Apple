// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

enum SubtitleTextSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        case .extraLarge: return String(localized: "Extra Large")
        }
    }

    var pointSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 17
        case .large: return 21
        case .extraLarge: return 26
        }
    }
}

enum SubtitleTextColorOption: String, CaseIterable, Identifiable {
    case white, yellow, cyan, green

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: return String(localized: "White")
        case .yellow: return String(localized: "Yellow")
        case .cyan: return String(localized: "Cyan")
        case .green: return String(localized: "Green")
        }
    }

    var color: Color {
        switch self {
        case .white: return .white
        case .yellow: return Color(red: 1, green: 0.92, blue: 0.23)
        case .cyan: return Color(red: 0.3, green: 0.85, blue: 0.98)
        case .green: return Color(red: 0.44, green: 0.93, blue: 0.44)
        }
    }
}

enum SubtitleBackgroundStyle: String, CaseIterable, Identifiable {
    case box, outline, none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .box: return String(localized: "Box")
        case .outline: return String(localized: "Outline")
        case .none: return String(localized: "None")
        }
    }
}

/// Shared subtitle rendering for both the online and offline players, driven by the three
/// @AppStorage-backed prefs set in SubtitleStyleSettingsView — kept as one view so the two
/// players can't drift out of sync on how a style option actually renders.
struct SubtitleText: View {
    let text: String
    var size: SubtitleTextSize
    var color: SubtitleTextColorOption
    var background: SubtitleBackgroundStyle

    var body: some View {
        switch background {
        case .box:
            styledText
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        case .outline:
            styledText
                .shadow(color: .black, radius: 0, x: 1, y: 0)
                .shadow(color: .black, radius: 0, x: -1, y: 0)
                .shadow(color: .black, radius: 0, x: 0, y: 1)
                .shadow(color: .black, radius: 0, x: 0, y: -1)
        case .none:
            styledText
                .shadow(color: .black.opacity(0.85), radius: 3)
        }
    }

    private var styledText: some View {
        // Without a width to wrap against, Text renders a long cue on one line at its
        // natural width and runs off-screen instead of wrapping — frame(maxWidth:) gives
        // it one to wrap against; fixedSize(vertical) lets it still grow tall enough for
        // however many lines that wrap produces instead of clipping them.
        Text(text)
            .font(.system(size: size.pointSize, weight: .semibold))
            .foregroundStyle(color.color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}
