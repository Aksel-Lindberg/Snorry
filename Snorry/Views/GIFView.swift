import SwiftUI
import WebKit

// MARK: - SwiftUI wrapper that renders an animated GIF via WKWebView.
// Accepts a raw base64-encoded GIF string; builds a transparent HTML page so the
// GIF loops seamlessly on the dark background without any white flash.
struct GIFView: UIViewRepresentable {

    let base64: String
    var accessibilityLabel: String = ""

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isAccessibilityElement = true
        webView.accessibilityLabel = accessibilityLabel
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { width: 100%; height: 100%; background: transparent; }
          img { width: 100%; height: 100%; object-fit: contain; display: block; }
        </style>
        </head>
        <body>
          <img src="data:image/gif;base64,\(base64)" />
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
