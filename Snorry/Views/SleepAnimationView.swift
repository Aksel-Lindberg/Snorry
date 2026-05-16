import SwiftUI

// MARK: - App-native sleep animation (replaces external GIF).
// Entirely SwiftUI — zero external assets, perfectly adapted to the dark night theme.
struct SleepAnimationView: View {

    /// Hero decorative card vs. single morph with the home START control.
    enum Presentation: Equatable {
        case standalone
        case startButton
    }

    var presentation: Presentation = .standalone
    /// Circle size — use a smaller value on iPad portrait so cards fit above the tab bar.
    var diameter: CGFloat = 172

    /// Scales inner artwork relative to the default 172pt START control.
    private var startLayoutScale: CGFloat {
        guard presentation == .startButton else { return 1 }
        return diameter / 172
    }

    @State private var glowPulse  = false
    @State private var moonFloat  = false
    @State private var barPhase   = false

    var body: some View {
        Group {
            switch presentation {
            case .standalone: standaloneBody
            case .startButton: startButtonBody
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                moonFloat = true
            }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                barPhase = true
            }
        }
    }

    // MARK: Standalone (decorative card on home background)

    private var standaloneBody: some View {
        ZStack {
            outerGlowAccent
            surfaceCircle
            moonIconStandalone
            floatingZsAccent
            audioWaveBarsAccent
                .offset(y: 62)
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: Start button (accent disk + animation + START label)

    private var startButtonBody: some View {
        let scale = startLayoutScale
        let edgeInset = 22 * scale
        let labelSpacing = 8 * scale

        return ZStack {
            outerGlowStartButton
            Circle()
                .fill(Theme.accentGradient)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: max(1, 2 * scale))
                )
                .shadow(color: .black.opacity(0.35), radius: 12 * scale, y: 6 * scale)

            VStack(spacing: 0) {
                Spacer(minLength: edgeInset)
                moonIconStartButton
                Spacer(minLength: 4 * scale)
                audioWaveBarsLight
                    .padding(.bottom, 8 * scale)
                HStack(spacing: labelSpacing) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 19 * scale, weight: .semibold))
                    Text("START")
                        .font(.system(size: 15 * scale, weight: .bold, design: .rounded))
                        .tracking(3)
                }
                .foregroundStyle(.white)
                Spacer(minLength: edgeInset)
            }
            .frame(width: diameter, height: diameter)

            floatingZsLight
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: Outer pulsing glow ring

    private var outerGlowAccent: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Theme.accent.opacity(0.14), Color.clear],
                    center: .center,
                    startRadius: 60, endRadius: 100
                )
            )
            .scaleEffect(glowPulse ? 1.20 : 0.90)
    }

    private var outerGlowStartButton: some View {
        let scale = startLayoutScale
        return Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.22), Color.clear],
                    center: .center,
                    startRadius: 70 * scale, endRadius: 118 * scale
                )
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(glowPulse ? 1.14 : 0.94)
    }

    // MARK: Main surface circle (standalone only)

    private var surfaceCircle: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Theme.surface, Theme.background],
                    center: .center,
                    startRadius: 0, endRadius: 90
                )
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.55),
                                     Color(red: 0.65, green: 0.45, blue: 1.0).opacity(0.35)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .padding(14)
    }

    // MARK: Moon — standalone vs on accent fill

    private var moonIconStandalone: some View {
        Image(systemName: "moon.zzz.fill")
            .font(.system(size: 62, weight: .ultraLight))
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.accent,
                             Color(red: 0.70, green: 0.50, blue: 1.00)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .offset(y: moonFloat ? -6 : 4)
            .shadow(color: Theme.accent.opacity(0.45), radius: 12)
    }

    private var moonIconStartButton: some View {
        Image(systemName: "moon.zzz.fill")
            .font(.system(size: 54 * startLayoutScale, weight: .ultraLight))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.white.opacity(0.98),
                             Color.white.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .offset(y: moonFloat ? -5 : 3)
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    // MARK: Floating Z particles

    private var floatingZsAccent: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            ZStack {
                zParticle(elapsed: elapsed, phaseOffset: 0.00,
                          xOffset: 36, fontSize: 13, letter: "z", style: .accent)
                zParticle(elapsed: elapsed, phaseOffset: 0.38,
                          xOffset: 54, fontSize: 18, letter: "Z", style: .accent)
                zParticle(elapsed: elapsed, phaseOffset: 0.70,
                          xOffset: 24, fontSize: 10, letter: "z", style: .accent)
            }
        }
    }

    private var floatingZsLight: some View {
        let scale = startLayoutScale
        return TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            ZStack {
                zParticle(elapsed: elapsed, phaseOffset: 0.00,
                          xOffset: 36 * scale, fontSize: 13 * scale, letter: "z", style: .light)
                zParticle(elapsed: elapsed, phaseOffset: 0.38,
                          xOffset: 54 * scale, fontSize: 18 * scale, letter: "Z", style: .light)
                zParticle(elapsed: elapsed, phaseOffset: 0.70,
                          xOffset: 24 * scale, fontSize: 10 * scale, letter: "z", style: .light)
            }
        }
    }

    private enum ZStyle { case accent, light }

    private func zParticle(
        elapsed: Double,
        phaseOffset: Double,
        xOffset: CGFloat,
        fontSize: CGFloat,
        letter: String,
        style: ZStyle
    ) -> some View {
        let cycle = 2.6
        let raw   = (elapsed / cycle + phaseOffset).truncatingRemainder(dividingBy: 1.0)
        let yDrop: CGFloat = presentation == .startButton ? 50 * startLayoutScale : 50

        let opacity: Double = {
            switch style {
            case .accent:
                return Double(1 - Float(raw)) * 0.90
            case .light:
                return Double(1 - Float(raw)) * 0.85
            }
        }()

        let colour: Color = {
            switch style {
            case .accent: return Theme.accent.opacity(opacity)
            case .light:  return Color.white.opacity(opacity * 0.95)
            }
        }()

        return Text(letter)
            .font(Theme.handwritten(size: fontSize))
            .foregroundStyle(colour)
            .offset(x: xOffset, y: -CGFloat(raw) * yDrop + 18)
    }

    // MARK: Audio-wave bars

    private var audioWaveBarsAccent: some View {
        audioWaveBars(
            gradientTop: Theme.accent.opacity(0.6),
            gradientBottom: Theme.accent.opacity(0.25)
        )
    }

    private var audioWaveBarsLight: some View {
        audioWaveBars(
            gradientTop: Color.white.opacity(0.95),
            gradientBottom: Color.white.opacity(0.35)
        )
    }

    private func audioWaveBars(gradientTop: Color, gradientBottom: Color) -> some View {
        let heights: [Double] = [0.55, 1.0, 0.70, 1.0, 0.55]
        return HStack(spacing: 4) {
            ForEach(heights.indices, id: \.self) { index in
                audioBar(
                    relativeHeight: heights[index],
                    gradientTop: gradientTop,
                    gradientBottom: gradientBottom
                )
            }
        }
    }

    private func audioBar(
        relativeHeight: Double,
        gradientTop: Color,
        gradientBottom: Color
    ) -> some View {
        let maxH: CGFloat = presentation == .startButton ? 14 * startLayoutScale : 16
        let delay = relativeHeight * 0.3

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [gradientTop, gradientBottom],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 4,
                   height: barPhase
                       ? maxH * CGFloat(relativeHeight)
                       : maxH * CGFloat(relativeHeight) * 0.35)
            .animation(
                .easeInOut(duration: 0.5 + delay)
                    .repeatForever(autoreverses: true),
                value: barPhase
            )
    }
}
