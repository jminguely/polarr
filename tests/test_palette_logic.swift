import Foundation

// Test WCAG relative luminance
func linearize(_ c: Double) -> Double {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
    (0.2126 * linearize(r)) + (0.7152 * linearize(g)) + (0.0722 * linearize(b))
}

func contrastRatio(l1: Double, l2: Double) -> Double {
    let lighter = max(l1, l2)
    let darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)
}

func rgbToHsb(r: Double, g: Double, b: Double) -> (h: Double, s: Double, b: Double) {
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

func hsbToRgb(h: Double, s: Double, b: Double) -> (r: Double, g: Double, b: Double) {
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

// 1. Verify black vs white contrast is 21:1
let blackLum = relativeLuminance(r: 0, g: 0, b: 0)
let whiteLum = relativeLuminance(r: 1, g: 1, b: 1)
let maxContrast = contrastRatio(l1: blackLum, l2: whiteLum)
assert(abs(maxContrast - 21.0) < 0.01, "Black/White contrast ratio must be 21:1, got \(maxContrast)")
print("✓ Black vs White contrast: \(String(format: "%.2f", maxContrast)):1 (Expected: 21.00:1)")

// 2. Verify identical color contrast is 1:1
let sameContrast = contrastRatio(l1: 0.5, l2: 0.5)
assert(abs(sameContrast - 1.0) < 0.01, "Identical colors contrast ratio must be 1:1")
print("✓ Identical color contrast: \(String(format: "%.2f", sameContrast)):1 (Expected: 1.00:1)")

// 3. Verify WCAG threshold for dark background (e.g. dark navy / slate)
let darkNavyLum = relativeLuminance(r: 0.05, g: 0.08, b: 0.15)
let darkNavyWhiteRatio = contrastRatio(l1: darkNavyLum, l2: whiteLum)
assert(darkNavyWhiteRatio >= 4.5, "Dark navy must have >= 4.5 contrast with white")
print("✓ Dark navy with white text contrast: \(String(format: "%.2f", darkNavyWhiteRatio)):1 (>= 4.5)")

// 4. Verify WCAG threshold for bright background (e.g. pastel yellow / white)
let brightYellowLum = relativeLuminance(r: 0.98, g: 0.95, b: 0.5)
let brightYellowWhiteRatio = contrastRatio(l1: brightYellowLum, l2: whiteLum)
assert(brightYellowWhiteRatio < 4.5, "Bright yellow should trigger isBackgroundLight")
let charcoalLum = relativeLuminance(r: 15/255, g: 23/255, b: 42/255)
let brightYellowCharcoalRatio = contrastRatio(l1: brightYellowLum, l2: charcoalLum)
assert(brightYellowCharcoalRatio >= 4.5, "Bright yellow must have >= 4.5 contrast with dark charcoal")
print("✓ Bright yellow with charcoal text contrast: \(String(format: "%.2f", brightYellowCharcoalRatio)):1 (>= 4.5)")

// 5. Verify HSB roundtrip conversion
let testH = 0.6 // ~216 deg (blue)
let testS = 0.75
let testB = 0.85
let (testR, testG, testBOut) = hsbToRgb(h: testH, s: testS, b: testB)
let (roundH, roundS, roundB) = rgbToHsb(r: testR, g: testG, b: testBOut)
assert(abs(testH - roundH) < 0.01, "Hue roundtrip mismatch")
assert(abs(testS - roundS) < 0.01, "Saturation roundtrip mismatch")
assert(abs(testB - roundB) < 0.01, "Brightness roundtrip mismatch")
print("✓ HSB/RGB roundtrip conversion verified")

// 6. Verify complementary color hue shift
let dominantHue = 0.1 // 36 degrees (orange)
let complementaryHue = (dominantHue + 0.5).truncatingRemainder(dividingBy: 1.0) // 0.6 -> 216 degrees (blue)
let hueAngleDiff = abs(complementaryHue - dominantHue) * 360.0
assert(abs(hueAngleDiff - 180.0) < 0.01, "Complementary hue angle diff must be 180 degrees")
print("✓ Complementary hue angle shift: \(hueAngleDiff) degrees (180.0 expected)")

print("\nAll color math and WCAG compliance tests passed successfully!")
