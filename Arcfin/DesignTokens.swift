import SwiftUI

// MARK: - Design token system for Arcfin
// Dark-first, cinematic black with cyan/ice accent and full iOS 26 Liquid Glass.

public enum DT {

    // MARK: - Colour

    public enum Color {
        /// #0A0A0F — deep cinematic black, primary background
        public static let backgroundPrimary   = SwiftUI.Color(hex: "0A0A0F")
        /// #12121A — midnight navy, secondary surface
        public static let backgroundSecondary = SwiftUI.Color(hex: "12121A")
        /// #1C1C26 — deep charcoal cool tint, tertiary surface
        public static let backgroundTertiary  = SwiftUI.Color(hex: "1C1C26")
        /// #06B6D4 — cyan/ice, accent — active states, progress bars, focus rings, CTAs
        public static let accent              = SwiftUI.Color(hex: "06B6D4")
        /// #0891b2 — deeper cyan, gradient start for buttons and logo
        public static let accentDeep          = SwiftUI.Color(hex: "0891b2")
        /// Accent at reduced opacity for glass tinting
        public static let accentSubtle        = SwiftUI.Color(hex: "06B6D4").opacity(0.15)
        /// White — primary text
        public static let textPrimary         = SwiftUI.Color.white
        /// #06B6D4 — active/selected labels
        public static let textActive          = SwiftUI.Color(hex: "06B6D4")
        /// #8E8E93 — secondary metadata (system grey)
        public static let textSecondary       = SwiftUI.Color(hex: "8E8E93")
        /// #3A3A4A — separator / divider lines
        public static let separator           = SwiftUI.Color(hex: "3A3A4A")
        /// Progress bar fill
        public static let progressFill        = SwiftUI.Color(hex: "06B6D4")
        /// Progress bar track
        public static let progressTrack       = SwiftUI.Color.white.opacity(0.15)
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
        /// Poster card: portrait 2:3
        public static let posterCard        = CGSize(width: 110, height: 165)
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
        public static let standard = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.80)
        public static let fast     = SwiftUI.Animation.spring(response: 0.20, dampingFraction: 0.90)
        public static let slow     = SwiftUI.Animation.spring(response: 0.50, dampingFraction: 0.75)
        public static let playerFade = SwiftUI.Animation.easeInOut(duration: 0.25)
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
