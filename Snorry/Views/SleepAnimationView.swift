import SwiftUI

// MARK: - App-native sleep animation (replaces external GIF).
// Entirely SwiftUI — zero external assets, perfectly adapted to the dark night theme.
struct SleepAnimationView: View {

    @State private var glowPulse  = false
    @State private var moonFloat  = false
    @State private var barPhase   = false

    var body: some View {
        ZStack {
            outerGlow
            surfaceCircle
            moonIcon
            floatingZs
            audioWaveBars
                .offset(y: 62)
        }
        .frame(width: 200, height: 200)
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

    // MARK: Outer pulsing glow ring

    private var outerGlow: some View {
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

    // MARK: Main surface circle

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

    // MARK: Sleeping moon icon

    private var moonIcon: some View {
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

    // MARK: Continuously floating Z particles (TimelineView keeps them phase-shifted)

    private var floatingZs: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            ZStack {
                // Three Z's at different horizontal offsets and staggered phase
                zParticle(elapsed: elapsed, phaseOffset: 0.00,
                          xOffset: 36, fontSize: 13, letter: "z")
                zParticle(elapsed: elapsed, phaseOffset: 0.38,
                          xOffset: 54, fontSize: 18, letter: "Z")
                zParticle(elapsed: elapsed, phaseOffset: 0.70,
                          xOffset: 24, fontSize: 10, letter: "z")
            }
        }
    }

    private func zParticle(
        elapsed: Double,
        phaseOffset: Double,
        xOffset: CGFloat,
        fontSize: CGFloat,
        letter: String
    ) -> some View {
        let cycle = 2.6
        // phase goes 0→1 continuously
        let raw   = (elapsed / cycle + phaseOffset).truncatingRemainder(dividingBy: 1.0)
        let yDrop: CGFloat = 50

        return Text(letter)
            .font(Theme.handwritten(size: fontSize))
            .foregroundStyle(
                Theme.accent
                    .opacity(Double(1 - Float(raw)) * 0.90)      // fade out as it rises
            )
            .offset(x: xOffset, y: -CGFloat(raw) * yDrop + 18)  // rises from y=18 to y=-32
    }

    // MARK: Mini audio-wave bars (suggest snore detection, bottom of circle)

    private var audioWaveBars: some View {
        HStack(spacing: 4) {
            ForEach([0.55, 1.0, 0.70, 1.0, 0.55], id: \.self) { relHeight in
                audioBar(relativeHeight: relHeight)
            }
        }
    }

    private func audioBar(relativeHeight: Double) -> some View {
        let maxH: CGFloat = 16
        // Each bar uses a slightly different delay via a hash of relativeHeight
        let delay = relativeHeight * 0.3

        return Capsule()
            .fill(
                LinearGradient(
                    colors: [Theme.accent.opacity(0.6), Theme.accent.opacity(0.25)],
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
