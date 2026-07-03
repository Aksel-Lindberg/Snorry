import SwiftUI

// MARK: - App-wide banner when a session runs but Recording screen is dismissed
struct RecordingInProgressBanner: View {

    let elapsedSeconds: Int
    let onReturn: () -> Void

    var body: some View {
        Button(action: onReturn) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.good)
                    .frame(width: 8, height: 8)

                Text("Recording in progress")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.labelPrimary)

                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(Theme.labelTertiary)

                Text("Return")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)

                Spacer(minLength: 8)

                Text(elapsedString)
                    .font(Theme.monoDigit(size: 13))
                    .foregroundStyle(Theme.labelSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Theme.surface,
                in: RoundedRectangle(cornerRadius: Theme.radiusCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .strokeBorder(Theme.surfaceSecondary.opacity(0.9), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Return to recording")
        .accessibilityHint("Opens the active recording session")
    }

    private var elapsedString: String {
        let h = elapsedSeconds / 3600
        let m = elapsedSeconds % 3600 / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
