import SwiftUI

/// Custom design palette and typography for Polarr iOS
public enum BrandTheme {
    // MARK: - Colors
    public static let bgPrimary = Color(red: 9/255, green: 10/255, blue: 15/255)       // #090A0F
    public static let bgSecondary = Color(red: 18/255, green: 21/255, blue: 30/255)   // #12151E
    public static let bgCard = Color(red: 27/255, green: 32/255, blue: 46/255)        // #1B202E
    public static let bgCardHover = Color(red: 35/255, green: 42/255, blue: 60/255)

    // Accents
    public static let cyan = Color(red: 6/255, green: 182/255, blue: 212/255)         // #06B6D4
    public static let blue = Color(red: 59/255, green: 130/255, blue: 246/255)        // #3B82F6
    public static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)     // #10B981
    public static let amber = Color(red: 245/255, green: 158/255, blue: 11/255)       // #F59E0B
    public static let rose = Color(red: 244/255, green: 63/255, blue: 94/255)         // #F43F5E
    public static let purple = Color(red: 168/255, green: 85/255, blue: 247/255)      // #A855F7

    // Gradient
    public static let brandGradient = LinearGradient(
        colors: [cyan, blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let cardGradient = LinearGradient(
        colors: [bgCard.opacity(0.85), bgSecondary.opacity(0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Text
    public static let textPrimary = Color(red: 248/255, green: 250/255, blue: 252/255) // #F8FAFC
    public static let textSecondary = Color(red: 148/255, green: 163/255, blue: 184/255) // #94A3B8
    public static let textMuted = Color(red: 100/255, green: 116/255, blue: 139/255)     // #64748B
    public static let border = Color.white.opacity(0.08)
    public static let borderActive = cyan.opacity(0.35)
}

// MARK: - View Modifiers
public struct PolarrCardModifier: ViewModifier {
    var isInteractive: Bool = false
    var cornerRadius: CGFloat = 16

    public func body(content: Content) -> some View {
        content
            .background(BrandTheme.cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BrandTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
    }
}

public extension View {
    func polarrCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(PolarrCardModifier(cornerRadius: cornerRadius))
    }
    
    func formatTime(seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
