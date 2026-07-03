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
    static let warning          = Color(red: 1.00, green: 0.80, blue: 0.20)   // amber (detecting pattern)

    static let labelPrimary     = Color.white
    /// Body subtext — ~4.5:1 on background (WCAG AA).
    static let labelSecondary   = Color.white.opacity(0.75)
    /// Hints and footnotes — de-emphasized but readable on dark cards.
    static let labelTertiary    = Color.white.opacity(0.52)
    /// Sublabels on `surface` cards — higher opacity for WCAG AA on lighter card backgrounds.
    static let labelOnSurfaceSecondary = Color.white.opacity(0.68)

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

    /// Darker, deeper red-maroon gradient for destructive/stop buttons.
    static var stopGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.42, green: 0.05, blue: 0.08),
                     Color(red: 0.28, green: 0.04, blue: 0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: Typography helpers
    static func monoDigit(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Noteworthy — iOS built-in handwritten font, readable on dark backgrounds.
    static func handwritten(size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size)
    }

    /// Gradient used for handwritten accent text (left: sky blue → right: soft white).
    static var handwrittenGradient: LinearGradient {
        LinearGradient(
            colors: [accent, Color.white.opacity(0.88)],
            startPoint: .leading, endPoint: .trailing
        )
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

// MARK: - iPad floating tab bar clearance

enum TabBarLayout {

    /// Bottom scroll inset so content stays above the tab bar on iPad (regular width).
    static func scrollContentBottomMargin(
        horizontalSizeClass: UserInterfaceSizeClass?,
        safeAreaBottom: CGFloat
    ) -> CGFloat {
        guard horizontalSizeClass == .regular else { return 28 }
        return max(safeAreaBottom, 20) + 64
    }
}

private struct SafeAreaBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {

    /// Keeps scroll content above the floating tab bar on iPad.
    func clearsFloatingTabBar() -> some View {
        modifier(FloatingTabBarClearanceModifier())
    }
}

private struct FloatingTabBarClearanceModifier: ViewModifier {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var safeAreaBottom: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SafeAreaBottomPreferenceKey.self,
                        value: geometry.safeAreaInsets.bottom
                    )
                }
            }
            .onPreferenceChange(SafeAreaBottomPreferenceKey.self) { safeAreaBottom = $0 }
            .contentMargins(
                .bottom,
                TabBarLayout.scrollContentBottomMargin(
                    horizontalSizeClass: horizontalSizeClass,
                    safeAreaBottom: safeAreaBottom
                ),
                for: .scrollContent
            )
    }
}
