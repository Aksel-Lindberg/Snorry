import SwiftUI

// MARK: - App colour palette and design tokens
enum Theme {

    // MARK: Colours
    static let background       = Color(red: 0.05, green: 0.06, blue: 0.14)   // deep midnight blue
    static let surface          = Color(red: 0.09, green: 0.11, blue: 0.22)
    static let surfaceSecondary = Color(red: 0.13, green: 0.16, blue: 0.30)

    static let accent           = Color(red: 0.40, green: 0.60, blue: 1.00)   // sky blue
    static let accentGlow       = Color(red: 0.40, green: 0.60, blue: 1.00).opacity(0.35)

    static let snoring          = Color(red: 1.00, green: 0.45, blue: 0.35)   // warm coral
    static let snoringGlow      = Color(red: 1.00, green: 0.45, blue: 0.35).opacity(0.30)

    static let good             = Color(red: 0.30, green: 0.85, blue: 0.60)   // mint green (quiet)

    static let labelPrimary     = Color.white
    static let labelSecondary   = Color.white.opacity(0.60)
    static let labelTertiary    = Color.white.opacity(0.35)

    static let waveformBar      = Color(red: 0.50, green: 0.70, blue: 1.00)
    static let waveformSnore    = Color(red: 1.00, green: 0.55, blue: 0.40)

    // MARK: Gradients
    static var nightGradient: LinearGradient {
        LinearGradient(
            colors: [background, Color(red: 0.04, green: 0.04, blue: 0.10)],
            startPoint: .top, endPoint: .bottom
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.35, green: 0.55, blue: 1.0),
                     Color(red: 0.55, green: 0.35, blue: 1.0)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    static var snoringGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.45, blue: 0.35),
                     Color(red: 1.0, green: 0.65, blue: 0.20)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: Typography helpers
    static func monoDigit(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Corner radii
    static let radiusCard: CGFloat    = 20
    static let radiusButton: CGFloat  = 50

    // MARK: Shadows
    static func cardShadow(color: Color = .black) -> some View {
        Rectangle()
            .fill(color.opacity(0.35))
            .blur(radius: 20)
    }
}
