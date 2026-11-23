import SwiftUI

/// Custom design palette and typography for Polarr iOS
public enum BrandTheme {
    // MARK: - Colors (Monochromatic Black & White Theme)
    public static let bgPrimary = Color.black                                          // #000000 Pure Obsidian Black
    public static let bgSecondary = Color(red: 13/255, green: 14/255, blue: 18/255)   // #0D0E12
    public static let bgCard = Color(red: 20/255, green: 23/255, blue: 32/255)        // #141720
    public static let bgCardHover = Color(red: 28/255, green: 32/255, blue: 44/255)

    // Monochromatic Highlights
    public static let cyan = Color.white                                               // Primary highlight: Crisp White
    public static let blue = Color(red: 226/255, green: 232/255, blue: 240/255)        // Silver / Slate 200
    public static let purple = Color(red: 203/255, green: 213/255, blue: 225/255)      // Slate 300
    public static let indigo = Color(red: 148/255, green: 163/255, blue: 184/255)      // Slate 400

    // Subtle Semantic Accents (strictly for functional feedback)
    public static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)     // #10B981 Sync / download success
    public static let amber = Color(red: 245/255, green: 158/255, blue: 11/255)       // #F59E0B Warning / skip
    public static let rose = Color(red: 244/255, green: 63/255, blue: 94/255)         // #F43F5E Destructive delete

    // Gradient
    public static let brandGradient = LinearGradient(
        colors: [Color.white, Color(red: 210/255, green: 215/255, blue: 225/255)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let cardGradient = LinearGradient(
        colors: [bgCard.opacity(0.95), bgSecondary.opacity(0.98)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Text
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 161/255, green: 161/255, blue: 170/255) // Zinc 400
    public static let textMuted = Color(red: 113/255, green: 113/255, blue: 122/255)     // Zinc 500
    public static let border = Color.white.opacity(0.12)
    public static let borderActive = Color.white.opacity(0.50)
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

    func cleanHTML(_ raw: String) -> String {
        raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
