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

// MARK: - Share button

struct SnoreClipShareButton: View {
    let event: SnoreEvent
    var onShare: (() -> Void)? = nil

    var body: some View {
        Button {
            guard let url = SnoreClipSharing.preparedShareURL(for: event) else { return }
            onShare?()
            // UIActivityViewController must be presented from UIKit — wrapping it in a
            // SwiftUI `.sheet` often shows a blank sheet on iPhone.
            ActivitySharePresenter.present(items: [url])
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title3)
                .foregroundStyle(Theme.labelSecondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share recording")
    }
}

// MARK: - UIKit presenter

enum ActivitySharePresenter {

    @MainActor
    static func present(items: [Any]) {
        guard !items.isEmpty else { return }
        guard let presenter = topViewController() else { return }

        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(activity, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        for scene in scenes {
            guard let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene.windows.first?.rootViewController else { continue }
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            return top
        }
        return nil
    }
}
