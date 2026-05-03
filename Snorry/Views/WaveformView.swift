import SwiftUI

// MARK: - Scrolling real-time waveform rendered as vertical bars
struct WaveformView: View {

    let samples: [Float]          // normalised 0…1
    let isSnoring: Bool
    var barWidth: CGFloat = 3
    var spacing: CGFloat  = 1

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let barCount = samples.count
                guard barCount > 0 else { return }

                let totalBarWidth = barWidth + spacing
                let barColor = isSnoring ? Theme.waveformSnore : Theme.waveformBar

                for (i, sample) in samples.enumerated() {
                    let x = CGFloat(i) * totalBarWidth
                    let barHeight = max(2, CGFloat(sample) * size.height)
                    let y = (size.height - barHeight) / 2
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)

                    let alpha = 0.4 + 0.6 * Double(sample)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(barColor.opacity(alpha)))
                }
            }
        }
    }
}

// MARK: - dB bar meter (vertical)
struct DBMeterView: View {

    let dBFS: Float     // -160 … 0
    let isSnoring: Bool

    private var level: CGFloat { AudioMath.normalisedLevel(dBFS) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.surface)
                    .frame(width: 8)

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSnoring ? Theme.snoringGradient : Theme.accentGradient)
                    .frame(width: 8, height: geo.size.height * level)
                    .animation(.linear(duration: 0.05), value: level)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
