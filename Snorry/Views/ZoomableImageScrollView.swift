import SwiftUI
import UIKit

// MARK: - Pinch-to-zoom and pan for asset-catalog images
struct ZoomableImageScrollView: UIViewRepresentable {

    let imageName: String
    var minimumZoomScale: CGFloat = 1.0
    var maximumZoomScale: CGFloat = 5.0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> LayoutAwareScrollView {
        let scrollView = LayoutAwareScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.image = UIImage(named: imageName)
        scrollView.addSubview(imageView)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.imageName = imageName
        context.coordinator.lastLoadedName = imageName

        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.layoutImageIfNeeded()
        }

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: LayoutAwareScrollView, context: Context) {
        context.coordinator.imageName = imageName
        if context.coordinator.lastLoadedName != imageName {
            context.coordinator.imageView?.image = UIImage(named: imageName)
            context.coordinator.lastLoadedName = imageName
        }
        context.coordinator.layoutImageIfNeeded()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {

        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        var imageName: String = ""
        var lastLoadedName: String?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImage(in: scrollView)
        }

        func layoutImageIfNeeded() {
            guard let scrollView, let imageView else { return }
            let bounds = scrollView.bounds
            guard bounds.width > 1, bounds.height > 1 else { return }

            if scrollView.zoomScale != scrollView.minimumZoomScale {
                centerImage(in: scrollView)
                return
            }

            guard let image = imageView.image else {
                imageView.frame = bounds
                scrollView.contentSize = bounds.size
                return
            }

            let fitted = aspectFitFrame(for: image.size, in: bounds)
            imageView.frame = fitted
            scrollView.contentSize = fitted.size
            centerImage(in: scrollView)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }

            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let location = recognizer.location(in: imageView)
            let zoomScale = min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 2.5)
            let zoomRect = zoomRect(for: zoomScale, center: location, in: scrollView)
            scrollView.zoom(to: zoomRect, animated: true)
        }

        private func aspectFitFrame(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
            guard imageSize.width > 0, imageSize.height > 0 else { return bounds }

            let widthRatio = bounds.width / imageSize.width
            let heightRatio = bounds.height / imageSize.height
            let scale = min(widthRatio, heightRatio)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let origin = CGPoint(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2
            )
            return CGRect(origin: origin, size: size)
        }

        private func centerImage(in scrollView: UIScrollView) {
            guard let imageView else { return }

            let bounds = scrollView.bounds
            var frame = imageView.frame

            frame.origin.x = frame.width < bounds.width
                ? (bounds.width - frame.width) / 2
                : frame.origin.x
            frame.origin.y = frame.height < bounds.height
                ? (bounds.height - frame.height) / 2
                : frame.origin.y

            imageView.frame = frame
        }

        private func zoomRect(for scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            let origin = CGPoint(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2
            )
            return CGRect(origin: origin, size: size)
        }
    }
}

final class LayoutAwareScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
