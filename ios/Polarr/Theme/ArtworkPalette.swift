import SwiftUI

/// Represents a tonally balanced 60-30-10 color scheme extracted from episode artwork.
public struct ArtworkPalette: Equatable, Sendable {
    // MARK: - 60-30-10 Foundation
    /// 60%: Dominant background canvas color.
    public let dominant: Color
    /// Deepened anchor color for the dominant background gradient.
    public let dominantDark: Color
    /// 30%: Secondary / complementary color for structural surfaces, cards, and borders.
    public let secondary: Color
    /// 10%: Accent color for high-visibility focal elements (play button, active track).
    public let accent: Color

    // MARK: - WCAG-Calibrated Typography & Contrast
    /// Primary high-contrast text color (guaranteed >= 4.5:1 against dominant background).
    public let textPrimary: Color
    /// Secondary text color (with >= 4.5:1 against dominant background).
    public let textSecondary: Color
    /// Muted text/border color.
    public let textMuted: Color
    /// High-contrast icon/text color positioned directly on top of the accent color.
    public let controlOnAccent: Color
    /// Whether the dominant background is considered light by relative luminance.
    public let isBackgroundLight: Bool

    public init(
        dominant: Color,
        dominantDark: Color,
        secondary: Color,
        accent: Color,
        textPrimary: Color,
        textSecondary: Color,
        textMuted: Color,
        controlOnAccent: Color,
        isBackgroundLight: Bool
    ) {
        self.dominant = dominant
        self.dominantDark = dominantDark
        self.secondary = secondary
        self.accent = accent
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textMuted = textMuted
        self.controlOnAccent = controlOnAccent
        self.isBackgroundLight = isBackgroundLight
    }

    /// Default palette aligned with Polarr's standard BrandTheme.
    public static let `default` = ArtworkPalette(
        dominant: BrandTheme.bgPrimary,
        dominantDark: Color(red: 5/255, green: 6/255, blue: 9/255),
        secondary: BrandTheme.bgSecondary,
        accent: BrandTheme.cyan,
        textPrimary: BrandTheme.textPrimary,
        textSecondary: BrandTheme.textSecondary,
        textMuted: BrandTheme.textMuted,
        controlOnAccent: Color.black,
        isBackgroundLight: false
    )

    // MARK: - Hex Accessors for ActivityKit / Serialization
    public var dominantHex: String { dominant.toHex() }
    public var dominantDarkHex: String { dominantDark.toHex() }
    public var secondaryHex: String { secondary.toHex() }
    public var accentHex: String { accent.toHex() }
    public var textPrimaryHex: String { textPrimary.toHex() }
    public var textSecondaryHex: String { textSecondary.toHex() }
    public var controlOnAccentHex: String { controlOnAccent.toHex() }
}

// MARK: - Hex Color Conversion Extensions
public extension Color {
    func toHex() -> String {
        let uic = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uic.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02lX%02lX%02lX",
            lroundf(Float(r * 255)),
            lroundf(Float(g * 255)),
            lroundf(Float(b * 255))
        )
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
