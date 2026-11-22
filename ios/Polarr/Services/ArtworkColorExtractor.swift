import UIKit
import SwiftUI

/// Cache box wrapper for storing ArtworkPalette in NSCache.
private final class PaletteCacheBox: NSObject {
    let palette: ArtworkPalette
    init(palette: ArtworkPalette) {
        self.palette = palette
    }
}

/// Service that extracts tonally balanced 60-30-10 color palettes from episode artwork
/// with WCAG-compliant dynamic text contrast calculations.
public actor ArtworkColorExtractor {
    public static let shared = ArtworkColorExtractor()

    private let cache = NSCache<NSString, PaletteCacheBox>()

    private init() {
        cache.countLimit = 100
    }

    /// Retrieves a cached palette or asynchronously extracts a new one from the artwork URL.
    public func extractPalette(from urlString: String?) async -> ArtworkPalette {
        guard let urlString = urlString, !urlString.isEmpty else {
            return .default
        }

        let cacheKey = NSString(string: urlString)
        if let cached = cache.object(forKey: cacheKey) {
            return cached.palette
        }

        guard let url = URL(string: urlString) else {
            return .default
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                return .default
            }

            let palette = await Task.detached(priority: .userInitiated) {
                Self.processImage(image)
            }.value

            cache.setObject(PaletteCacheBox(palette: palette), forKey: cacheKey)
            return palette
        } catch {
            return .default
        }
    }

    /// Directly extracts a palette from an in-memory UIImage (useful for unit testing and offline images).
    public static func processImage(_ image: UIImage) -> ArtworkPalette {
        let targetSize = CGSize(width: 64, height: 64)
        guard let cgImage = downscale(image: image, to: targetSize) else {
            return .default
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return .default
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        struct PixelSample {
            let r: Double
            let g: Double
            let b: Double
            let h: Double
            let s: Double
            let v: Double
        }

        var samples: [PixelSample] = []
        samples.reserveCapacity(width * height)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let a = Double(rawData[offset + 3]) / 255.0
                guard a > 0.5 else { continue }

                let r = Double(rawData[offset]) / 255.0
                let g = Double(rawData[offset + 1]) / 255.0
                let b = Double(rawData[offset + 2]) / 255.0

                let (h, s, v) = rgbToHsb(r: r, g: g, b: b)
                samples.append(PixelSample(r: r, g: g, b: b, h: h, s: s, v: v))
            }
        }

        guard !samples.isEmpty else {
            return .default
        }

        // Group into hue bins (18 bins of 20 degrees each)
        let binCount = 18
        var bins = [[PixelSample]](repeating: [], count: binCount)

        for sample in samples {
            let binIndex = min(binCount - 1, max(0, Int(sample.h * Double(binCount))))
            bins[binIndex].append(sample)
        }

        // Find the most frequent bin for dominant color
        var dominantBinIndex = 0
        var maxBinCount = 0
        for (i, bin) in bins.enumerated() {
            if bin.count > maxBinCount {
                maxBinCount = bin.count
                dominantBinIndex = i
            }
        }

        let dominantSamples = bins[dominantBinIndex]
        let avgDomR = dominantSamples.map(\.r).reduce(0, +) / Double(dominantSamples.count)
        let avgDomG = dominantSamples.map(\.g).reduce(0, +) / Double(dominantSamples.count)
        let avgDomB = dominantSamples.map(\.b).reduce(0, +) / Double(dominantSamples.count)
        let (domH, domS, domV) = rgbToHsb(r: avgDomR, g: avgDomG, b: avgDomB)

        // Find best accent (high saturation & moderate-to-high brightness)
        var bestAccentSample: PixelSample?
        var maxAccentScore: Double = -1

        for sample in samples {
            if sample.v >= 0.35 && sample.v <= 0.98 {
                let score = (sample.s * 1.5) + (sample.v * 0.8)
                if score > maxAccentScore {
                    maxAccentScore = score
                    bestAccentSample = sample
                }
            }
        }

        let accentRGB: (r: Double, g: Double, b: Double)
        if let bestAccent = bestAccentSample, bestAccent.s >= 0.25 {
            accentRGB = (bestAccent.r, bestAccent.g, bestAccent.b)
        } else {
            // Algorithmic fallback: split-complementary or saturated boost
            let tunedAccentH = (domH + 0.33).truncatingRemainder(dividingBy: 1.0)
            accentRGB = hsbToRgb(h: tunedAccentH, s: max(0.65, domS), b: max(0.75, domV))
        }

        // Find 30% secondary / complementary color
        var bestSecondarySample: PixelSample?
        var maxSecondaryCount = 0

        for (i, bin) in bins.enumerated() {
            guard !bin.isEmpty else { continue }
            let binHue = Double(i) / Double(binCount)
            let hueDiff = min(abs(binHue - domH), 1.0 - abs(binHue - domH))
            if hueDiff >= 0.15 { // at least ~54 degrees difference
                if bin.count > maxSecondaryCount {
                    maxSecondaryCount = bin.count
                    let avgR = bin.map(\.r).reduce(0, +) / Double(bin.count)
                    let avgG = bin.map(\.g).reduce(0, +) / Double(bin.count)
                    let avgB = bin.map(\.b).reduce(0, +) / Double(bin.count)
                    let (h, s, v) = rgbToHsb(r: avgR, g: avgG, b: avgB)
                    bestSecondarySample = PixelSample(r: avgR, g: avgG, b: avgB, h: h, s: s, v: v)
                }
            }
        }

        let secondaryRGB: (r: Double, g: Double, b: Double)
        if let sec = bestSecondarySample {
            secondaryRGB = (sec.r, sec.g, sec.b)
        } else {
            // Algorithmic complementary (180 degree shift)
            let compH = (domH + 0.5).truncatingRemainder(dividingBy: 1.0)
            secondaryRGB = hsbToRgb(h: compH, s: max(0.35, min(0.65, domS)), b: max(0.20, min(0.40, domV)))
        }

        // Anchor background gradient tone (grounded dark shade of dominant)
        let darkAnchorRGB = hsbToRgb(
            h: domH,
            s: min(1.0, domS * 1.15),
            b: max(0.06, domV * 0.32)
        )

        // MARK: - WCAG 2.1 Contrast Calculations
        let domLuminance = relativeLuminance(r: avgDomR, g: avgDomG, b: avgDomB)
        let whiteLuminance = 1.0
        let whiteContrastRatio = contrastRatio(l1: domLuminance, l2: whiteLuminance)

        let isBackgroundLight = whiteContrastRatio < 4.5

        let textPrimary: Color
        let textSecondary: Color
        let textMuted: Color

        if isBackgroundLight {
            // Bright background: Use deep rich charcoal/black
            textPrimary = Color(red: 15/255, green: 23/255, blue: 42/255) // #0F172A
            textSecondary = Color(red: 51/255, green: 65/255, blue: 85/255) // #334155
            textMuted = Color(red: 100/255, green: 116/255, blue: 139/255) // #64748B
        } else {
            // Dark/Medium background: Use crisp white and high-contrast silver
            textPrimary = Color.white
            textSecondary = Color(red: 226/255, green: 232/255, blue: 240/255) // #E2E8F0
            textMuted = Color(red: 148/255, green: 163/255, blue: 184/255) // #94A3B8
        }

        // Compute high-contrast control color on top of Accent
        let accentLuminance = relativeLuminance(r: accentRGB.r, g: accentRGB.g, b: accentRGB.b)
        let accentBlackContrast = contrastRatio(l1: accentLuminance, l2: 0.0)
        let accentWhiteContrast = contrastRatio(l1: accentLuminance, l2: 1.0)
        let controlOnAccent: Color = accentBlackContrast >= accentWhiteContrast ? Color.black : Color.white

        return ArtworkPalette(
            dominant: Color(red: avgDomR, green: avgDomG, blue: avgDomB),
            dominantDark: Color(red: darkAnchorRGB.r, green: darkAnchorRGB.g, blue: darkAnchorRGB.b),
            secondary: Color(red: secondaryRGB.r, green: secondaryRGB.g, blue: secondaryRGB.b),
            accent: Color(red: accentRGB.r, green: accentRGB.g, blue: accentRGB.b),
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            textMuted: textMuted,
            controlOnAccent: controlOnAccent,
            isBackgroundLight: isBackgroundLight
        )
    }

    // MARK: - Color Math Helpers

    public static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * linearize(r)) + (0.7152 * linearize(g)) + (0.0722 * linearize(b))
    }

    public static func contrastRatio(l1: Double, l2: Double) -> Double {
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func rgbToHsb(r: Double, g: Double, b: Double) -> (h: Double, s: Double, b: Double) {
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal

        var h: Double = 0
        let s: Double = maxVal == 0 ? 0 : delta / maxVal
        let v: Double = maxVal

        if delta != 0 {
            if maxVal == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
            } else if maxVal == g {
                h = ((b - r) / delta) + 2.0
            } else {
                h = ((r - g) / delta) + 4.0
            }
            h /= 6.0
            if h < 0 { h += 1.0 }
        }

        return (h, s, v)
    }

    public static func hsbToRgb(h: Double, s: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        if s == 0 {
            return (b, b, b)
        }

        let hPrime = (h * 360.0) / 60.0
        let i = floor(hPrime)
        let f = hPrime - i
        let p = b * (1.0 - s)
        let q = b * (1.0 - s * f)
        let t = b * (1.0 - s * (1.0 - f))

        switch Int(i) % 6 {
        case 0: return (b, t, p)
        case 1: return (q, b, p)
        case 2: return (p, b, t)
        case 3: return (p, q, b)
        case 4: return (t, p, b)
        default: return (b, p, q)
        }
    }

    private static func downscale(image: UIImage, to size: CGSize) -> CGImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let renderedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return renderedImage.cgImage
    }
}
