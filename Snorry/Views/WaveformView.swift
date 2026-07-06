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

// MARK: - Live FFT power spectrum
struct LivePowerSpectrumView: View {

    let bands: [Float]
    let isSnoring: Bool

    var barSpacing: CGFloat = 1.5
    var cornerRadius: CGFloat = 2

    private var accentColor: Color {
        isSnoring ? Theme.waveformSnore : Theme.waveformBar
    }

    var body: some View {
        GeometryReader { _ in
            Canvas { ctx, csize in
                let n = bands.count
                guard n > 0 else { return }

                let totalSpacing = barSpacing * CGFloat(max(0, n - 1))
                let barW = max(1.5, (csize.width - totalSpacing) / CGFloat(n))
                let baseY = csize.height

                let hr = CGFloat(0.12)
                for k in stride(from: CGFloat(2), through: baseY - 4, by: 18) {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: baseY - k))
                    p.addLine(to: CGPoint(x: csize.width, y: baseY - k))
                    ctx.stroke(p, with: .color(Color.white.opacity(hr)), lineWidth: 0.5)
                }

                for i in 0 ..< n {
                    let v = CGFloat(max(0, min(1, bands[i])))
                    let h = max(2, v * csize.height * 0.94)
                    let x = CGFloat(i) * (barW + barSpacing)
                    let y = csize.height - h

                    let alpha = 0.35 + 0.65 * Double(v)
                    let fillColor = accentColor.opacity(alpha)

                    let rect = CGRect(x: x, y: y, width: barW, height: h)
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: cornerRadius),
                        with: .color(fillColor)
                    )
                }
            }
        }
        .drawingGroup()
    }
}
