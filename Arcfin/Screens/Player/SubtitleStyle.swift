import SwiftUI

enum SubtitleTextSize: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
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
        case .white: return "White"
        case .yellow: return "Yellow"
        case .cyan: return "Cyan"
        case .green: return "Green"
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
        case .box: return "Box"
        case .outline: return "Outline"
        case .none: return "None"
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
        Text(text)
            .font(.system(size: size.pointSize, weight: .semibold))
            .foregroundStyle(color.color)
            .multilineTextAlignment(.center)
    }
}
