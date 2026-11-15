// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Foundation

// MARK: - Design token system for Arcfin
// Dark-first, graphite black with a coral accent and full iOS 26 Liquid Glass. Every colour
// follows the system appearance; the light values hold the same contrast as the dark ones.

public enum DT {

    // MARK: - Colour

    public enum Color {
        /// Dark #0B0B0C, graphite black / light #F4F4F5 — primary background
        public static let backgroundPrimary   = SwiftUI.Color(light: "F4F4F5", dark: "0B0B0C")
        /// Dark #141416 / light white — secondary surface
        public static let backgroundSecondary = SwiftUI.Color(light: "FFFFFF", dark: "141416")
        /// Dark #1E1E21 / light #E4E4E7 — tertiary surface
        public static let backgroundTertiary  = SwiftUI.Color(light: "E4E4E7", dark: "1E1E21")
        /// Dark #FF6A4D, coral (5.9–7.0:1) / light #B83A25 (coral on white is 2.8:1; this is
        /// 4.5–5.7:1) — active states, progress bars, focus rings, CTAs
        public static let accent              = SwiftUI.Color(light: "B83A25", dark: "FF6A4D")
        /// Deeper coral, gradient start for buttons and logo
        public static let accentDeep          = SwiftUI.Color(light: "962E1D", dark: "E5533A")
        /// Accent at reduced opacity for glass tinting
        public static let accentSubtle        = accent.opacity(0.15)
        /// Text and symbols on an accent fill: dark on the bright coral (7.0:1, where white is
        /// 2.8:1), white on the deeper light-appearance coral (5.7:1).
        public static let onAccent            = SwiftUI.Color(light: "FFFFFF", dark: "0B0B0C")
        /// White / light #0B0B0C — primary text
        public static let textPrimary         = SwiftUI.Color(light: "0B0B0C", dark: "FFFFFF")
        /// Active/selected labels
        public static let textActive          = accent

        /// Reads the system's real Increase Contrast accessibility setting directly —
        /// same bare-global-read shape as DT.Animation.reduceMotion below, so textSecondary/
        /// separator stay plain property accesses at every call site, no environment
        /// plumbing needed. textPrimary/textActive/accent are already 8:1+ against every
        /// background (computed from their actual hex values) and don't need a second tier.
        private static var increaseContrast: Bool {
            PlatformAccessibility.increaseContrast
        }

        /// #8E8E93 (5.1–6.0:1 on the three backgrounds) / Increase Contrast: #AEAEB4
        /// (7.5–8.9:1) — secondary metadata (system grey)
        /// Light #636366 (4.7–6.0:1) / Increase Contrast #48484C (7.2–9.1:1).
        public static var textSecondary: SwiftUI.Color {
            increaseContrast ? SwiftUI.Color(light: "48484C", dark: "AEAEB4") : SwiftUI.Color(light: "636366", dark: "8E8E93")
        }
        /// #3A3A3E (1.5–1.7:1, under the 3:1 UI-boundary floor) / Increase Contrast:
        /// #707076 (3.4–4.0:1) — separator / divider lines
        public static var separator: SwiftUI.Color {
            increaseContrast ? SwiftUI.Color(light: "8A8A8E", dark: "707076") : SwiftUI.Color(light: "C6C6C8", dark: "3A3A3E")
        }
        /// A status or category colour from the shared palette, with a darker partner for the
        /// light appearance (the bright dark-mode hues are 2.1–3.8:1 on white; these are 4.4:1
        /// or better). Errors are rose rather than red so they don't read as the coral accent.
        /// Any other hex is used as is.
        public static func palette(_ hex: String) -> SwiftUI.Color {
            switch hex.lowercased() {
            case "10b981": SwiftUI.Color(light: "047857", dark: "10B981")
            case "f59e0b": SwiftUI.Color(light: "B45309", dark: "F59E0B")
            case "f43f5e": SwiftUI.Color(light: "BE123C", dark: "F43F5E")
            case "60a5fa": SwiftUI.Color(light: "1D4ED8", dark: "60A5FA")
            case "f5c518": SwiftUI.Color(light: "A16207", dark: "F5C518")
            case "ff6a4d": accent
            default: SwiftUI.Color(hex: hex)
            }
        }
        /// Progress bar fill
        public static let progressFill        = accent
        /// Progress bar track
        public static let progressTrack       = textPrimary.opacity(0.15)
    }

    // MARK: - Typography

    public enum Font {
        /// SF Pro Display Bold — hero banner title
        public static let hero          = PlatformMetrics.contentFont(.largeTitle, design: .default, weight: .bold)
        /// SF Pro Display Semibold — section headers
        public static let sectionTitle  = PlatformMetrics.contentFont(.title2, design: .default, weight: .semibold)
        /// SF Pro Display Medium — card titles
        public static let cardTitle     = PlatformMetrics.contentFont(.headline, design: .default, weight: .medium)
        /// SF Pro Text Regular — body copy
        public static let body          = PlatformMetrics.contentFont(.body, design: .default, weight: .regular)
        /// SF Pro Text Regular — supporting body
        public static let callout       = PlatformMetrics.contentFont(.callout, design: .default, weight: .regular)
        /// SF Pro Text Regular — captions, metadata
        public static let caption       = PlatformMetrics.contentFont(.caption, design: .default, weight: .regular)
        /// SF Pro Text Regular — micro metadata
        public static let caption2      = PlatformMetrics.contentFont(.caption2, design: .default, weight: .regular)
        /// SF Pro Text Semibold — button labels
        public static let button        = PlatformMetrics.contentFont(.subheadline, design: .default, weight: .semibold)
        /// SF Pro Text Medium — tab bar labels
        public static let tabLabel      = PlatformMetrics.contentFont(.caption2, design: .default, weight: .medium)
    }

    // MARK: - Spacing

    public enum Spacing {
        public static let xxs: CGFloat =  4
        public static let xs:  CGFloat =  8
        public static let sm:  CGFloat = 12
        public static let md:  CGFloat = 16
        public static let lg:  CGFloat = 24
        public static let xl:  CGFloat = 32
        public static let xxl: CGFloat = 48
        public static let xxxl: CGFloat = 64

        /// Standard horizontal page margin
        public static let pagePad: CGFloat = PlatformMetrics.pagePad
        /// Shelf row internal item gap
        public static let shelfGap: CGFloat = PlatformMetrics.shelfGap
        /// Section header → shelf gap
        public static let sectionGap: CGFloat = 8
    }

    // MARK: - Corner radius

    public enum Radius {
        public static let xs:    CGFloat =  6
        public static let sm:    CGFloat =  8
        public static let md:    CGFloat = 12
        public static let lg:    CGFloat = 16
        public static let xl:    CGFloat = 20
        public static let card:  CGFloat = 12
        public static let sheet: CGFloat = 20
        public static let pill:  CGFloat = 100
    }

    // MARK: - Sizing

    public enum Size {
        /// Poster card — portrait 2:3 on iOS, landscape 16:9 thumb on tvOS
        public static let posterCard        = PlatformMetrics.posterCard
        /// Backdrop card: landscape 16:9
        public static let backdropCard      = PlatformMetrics.backdropCard
        /// Continue Watching and other landscape shelf cards.
        public static let wideCard          = PlatformMetrics.wideCard
        /// Hero banner height
        public static let heroBannerHeight: CGFloat = 520
        /// Tab bar height (approx, under Liquid Glass)
        public static let tabBarHeight: CGFloat = 84
        /// Player overlay control height
        public static let playerControlBar: CGFloat = 96
    }

    // MARK: - Animation

    public enum Animation {
        /// When the Appearance → Reduce Motion setting or the system Reduce Motion is on, every DT.Animation
        /// collapses to a near-instant linear fade instead of its spring/duration.
        private static var reduceMotion: Bool {
            if UserDefaults.standard.bool(forKey: "reduceMotion") { return true }
            return PlatformAccessibility.reduceMotion
        }
        private static let reducedFallback = SwiftUI.Animation.linear(duration: 0.01)

        public static var standard: SwiftUI.Animation {
            reduceMotion ? reducedFallback : .spring(response: 0.35, dampingFraction: 0.80)
        }
        public static var fast: SwiftUI.Animation {
            reduceMotion ? reducedFallback : .spring(response: 0.20, dampingFraction: 0.90)
        }
        public static var slow: SwiftUI.Animation {
            reduceMotion ? reducedFallback : .spring(response: 0.50, dampingFraction: 0.75)
        }
        /// Any other animation, collapsed the same way under Reduce Motion.
        public static func motion(_ animation: SwiftUI.Animation) -> SwiftUI.Animation {
            reduceMotion ? reducedFallback : animation
        }
        public static var playerFade: SwiftUI.Animation {
            reduceMotion ? reducedFallback : .easeInOut(duration: 0.25)
        }
    }

    // MARK: - Platform scale

    public enum Scale {
        /// Multiply hardcoded pt sizes by this for 10-foot TV readability.
        public static let font: CGFloat = PlatformMetrics.fontScale
    }

    // MARK: - Glass

    public enum Glass {
        /// Standard material for nav bars, tab bar, modal sheets
        public static let primary   = Material.ultraThinMaterial
        /// Denser material for cards that sit on artwork
        public static let secondary = Material.thinMaterial
    }
}

// MARK: - Hex colour initialiser

extension SwiftUI.Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        let style: Font.TextStyle = switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<13.5: .footnote
        case ..<14.5: .subheadline
        case ..<15.5: .callout
        case ..<17.5: .body
        case ..<20.5: .title3
        case ..<22.5: .title2
        case ..<28.5: .title
        default: .largeTitle
        }
        _size = ScaledMetric(wrappedValue: PlatformMetrics.scaledFontSize(size), relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// Text on browsing screens: shelves, cards and title pages. The system text style on
    /// iPhone, iPad and Apple TV; a step larger on the Mac (see `PlatformMetrics.contentFont`).
    func contentFont(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> some View {
        font(PlatformMetrics.contentFont(style, design: design, weight: weight))
    }

    /// The player, splash and lock screen are dark in either system appearance: video and
    /// artwork read best on black. Set on the view's own subtree, not the window, so the rest
    /// of the app keeps following the system.
    func alwaysDark() -> some View {
        environment(\.colorScheme, .dark)
    }

    /// `DT.Scale.font` sizing that also tracks Dynamic Type — plain `.font(.system(size:))`
    /// stays fixed regardless of the user's text-size setting.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}
