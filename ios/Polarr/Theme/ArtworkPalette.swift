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
}
