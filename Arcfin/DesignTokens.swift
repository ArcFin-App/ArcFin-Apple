// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Design token system for Arcfin
// Dark-first, cinematic black with cyan/ice accent and full iOS 26 Liquid Glass. Every colour
// follows the system appearance; the light values hold the same contrast as the dark ones.

public enum DT {

    // MARK: - Colour

    public enum Color {
        /// Dark #0A0A0F, deep cinematic black / light #F2F2F7 — primary background
        public static let backgroundPrimary   = SwiftUI.Color(light: "F2F2F7", dark: "0A0A0F")
        /// Dark #12121A, midnight navy / light white — secondary surface
        public static let backgroundSecondary = SwiftUI.Color(light: "FFFFFF", dark: "12121A")
        /// Dark #1C1C26, deep charcoal / light #E5E5EA — tertiary surface
        public static let backgroundTertiary  = SwiftUI.Color(light: "E5E5EA", dark: "1C1C26")
        /// Dark #06B6D4, cyan/ice / light #0E7490 (cyan on white is 2.4:1; this is 4.3–5.4:1)
        /// — active states, progress bars, focus rings, CTAs
        public static let accent              = SwiftUI.Color(light: "0E7490", dark: "06B6D4")
        /// Deeper cyan, gradient start for buttons and logo
        public static let accentDeep          = SwiftUI.Color(light: "155E75", dark: "0891B2")
        /// Accent at reduced opacity for glass tinting
        public static let accentSubtle        = accent.opacity(0.15)
        /// Text and symbols on an accent fill: dark on the bright cyan (8.1:1, where white was
        /// 2.4:1), white on the deeper light-appearance cyan (5.4:1).
        public static let onAccent            = SwiftUI.Color(light: "FFFFFF", dark: "0A0A0F")
        /// White / light #0A0A0F — primary text
        public static let textPrimary         = SwiftUI.Color(light: "0A0A0F", dark: "FFFFFF")
        /// Active/selected labels
        public static let textActive          = accent

        /// Reads the system's real Increase Contrast accessibility setting directly —
        /// same bare-global-read shape as DT.Animation.reduceMotion below, so textSecondary/
        /// separator stay plain property accesses at every call site, no environment
        /// plumbing needed. textPrimary/textActive/accent are already 8:1+ against every
        /// background (computed from their actual hex values) and don't need a second tier.
        private static var increaseContrast: Bool {
#if os(macOS)
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
#else
            UIAccessibility.isDarkerSystemColorsEnabled
#endif
        }

        /// #8E8E93 (5.2–6.1:1 on the three backgrounds) / Increase Contrast: #AEAEB4
        /// (7.65–8.95:1) — secondary metadata (system grey)
        /// Light #636366 (4.8–5.9:1) / Increase Contrast #48484C (7.3–9.1:1).
        public static var textSecondary: SwiftUI.Color {
            increaseContrast ? SwiftUI.Color(light: "48484C", dark: "AEAEB4") : SwiftUI.Color(light: "636366", dark: "8E8E93")
        }
        /// #3A3A4A (1.5–1.8:1, under the 3:1 UI-boundary floor) / Increase Contrast:
        /// #6E6E82 (3.4–4.0:1) — separator / divider lines
        public static var separator: SwiftUI.Color {
            increaseContrast ? SwiftUI.Color(light: "8A8A8E", dark: "6E6E82") : SwiftUI.Color(light: "C6C6C8", dark: "3A3A4A")
        }
        /// A status or category colour from the shared palette, with a darker partner for the
        /// light appearance (the bright dark-mode hues are 2.1–3.8:1 on white; these are 4.4:1
        /// or better). Any other hex is used as is.
        public static func palette(_ hex: String) -> SwiftUI.Color {
            switch hex.lowercased() {
            case "10b981": SwiftUI.Color(light: "047857", dark: "10B981")
            case "f59e0b": SwiftUI.Color(light: "B45309", dark: "F59E0B")
            case "ef4444": SwiftUI.Color(light: "B91C1C", dark: "EF4444")
            case "8b5cf6": SwiftUI.Color(light: "6D28D9", dark: "8B5CF6")
            case "f5c518": SwiftUI.Color(light: "A16207", dark: "F5C518")
            case "06b6d4": accent
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
        public static let hero          = SwiftUI.Font.system(.largeTitle,  design: .default, weight: .bold)
        /// SF Pro Display Semibold — section headers
        public static let sectionTitle  = SwiftUI.Font.system(.title2,      design: .default, weight: .semibold)
        /// SF Pro Display Medium — card titles
        public static let cardTitle     = SwiftUI.Font.system(.headline,    design: .default, weight: .medium)
        /// SF Pro Text Regular — body copy
        public static let body          = SwiftUI.Font.system(.body,        design: .default, weight: .regular)
        /// SF Pro Text Regular — supporting body
        public static let callout       = SwiftUI.Font.system(.callout,     design: .default, weight: .regular)
        /// SF Pro Text Regular — captions, metadata
        public static let caption       = SwiftUI.Font.system(.caption,     design: .default, weight: .regular)
        /// SF Pro Text Regular — micro metadata
        public static let caption2      = SwiftUI.Font.system(.caption2,    design: .default, weight: .regular)
        /// SF Pro Text Semibold — button labels
        public static let button        = SwiftUI.Font.system(.subheadline, design: .default, weight: .semibold)
        /// SF Pro Text Medium — tab bar labels
        public static let tabLabel      = SwiftUI.Font.system(.caption2,    design: .default, weight: .medium)
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
        public static let pagePad: CGFloat = 20
        /// Shelf row internal item gap
        public static let shelfGap: CGFloat = 12
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
#if os(tvOS)
        public static let posterCard        = CGSize(width: 320, height: 180)
#else
        public static let posterCard        = CGSize(width: 110, height: 165)
#endif
        /// Backdrop card: landscape 16:9
        public static let backdropCard      = CGSize(width: 240, height: 135)
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
            #if canImport(UIKit)
            return UIAccessibility.isReduceMotionEnabled
            #elseif canImport(AppKit)
            return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            #else
            return false
            #endif
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
        #if os(tvOS)
        public static let font: CGFloat = 2.0
        #else
        public static let font: CGFloat = 1.0
        #endif
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
    /// One colour for the light appearance and one for the dark, switching with the system.
    init(light: String, dark: String) {
        let light = SwiftUI.Color(hex: light), dark = SwiftUI.Color(hex: dark)
        #if canImport(UIKit)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

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
        #if os(tvOS)
        // 23 pt is tvOS's smallest text style; anything under it is unreadable from the couch.
        _size = ScaledMetric(wrappedValue: max(size * DT.Scale.font, 23), relativeTo: style)
        #else
        _size = ScaledMetric(wrappedValue: size * DT.Scale.font, relativeTo: style)
        #endif
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// The player, splash and lock screen are dark in either system appearance: video and
    /// artwork read best on black. Set on the view's own subtree, not the window, so the rest
    /// of the app keeps following the system.
    func alwaysDark() -> some View {
        environment(\.colorScheme, .dark)
    }

    /// The players, which on iPhone, iPad and Apple TV are their own full-screen presentation:
    /// that presentation is dark too, so its menus and alerts match.
    func alwaysDarkPlayer() -> some View {
        #if os(macOS)
        alwaysDark()
        #else
        alwaysDark().preferredColorScheme(.dark)
        #endif
    }

    /// `DT.Scale.font` sizing that also tracks Dynamic Type — plain `.font(.system(size:))`
    /// stays fixed regardless of the user's text-size setting.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}
