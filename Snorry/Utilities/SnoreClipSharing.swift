import SwiftUI
import UIKit

// MARK: - Export a recorded snore clip via the system share sheet

enum SnoreClipSharing {

    /// Copies the clip to a temp file with a readable name for sharing.
    static func preparedShareURL(for event: SnoreEvent) -> URL? {
        guard let source = event.playbackURL else { return nil }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(exportFilename(for: event))
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            return source
        }
    }

    private static func exportFilename(for event: SnoreEvent) -> String {
        let stamp = event.startDate.formatted(
            .dateTime.year().month(.twoDigits).day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        )
        let safe = stamp
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "Snorry snore \(safe).m4a"
    }
}

// MARK: - Share button (copies clip once when tapped)

struct SnoreClipShareButton: View {
    let event: SnoreEvent
    var onShare: (() -> Void)? = nil

    @State private var shareURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        Button {
            guard let url = SnoreClipSharing.preparedShareURL(for: event) else { return }
            shareURL = url
            showShareSheet = true
            onShare?()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title3)
                .foregroundStyle(Theme.labelSecondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share recording")
        .sheet(isPresented: $showShareSheet) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }
}

// MARK: - UIKit share sheet wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
