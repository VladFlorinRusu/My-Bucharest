import SwiftUI
import WebKit

/// Redă un segment dintr-un clip YouTube prin playerul oficial (IFrame API), în buclă.
/// Folosim embed-ul în loc să descărcăm clipul, ca să respectăm termenii YouTube.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let startSeconds: Int?
    let endSeconds: Int?
    let isActive: Bool

    /// YouTube refuză embed-urile fără un origin/referrer valid (eroarea 153).
    private static let origin = "https://mybucharest.app"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(html, baseURL: URL(string: Self.origin))
        context.coordinator.isActive = isActive
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.isActive != isActive else { return }
        context.coordinator.isActive = isActive
        webView.evaluateJavaScript("setActive(\(isActive))")
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.evaluateJavaScript("setActive(false)")
    }

    final class Coordinator {
        var isActive = false
    }

    private var html: String {
        let safeID = videoID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let start = max(startSeconds ?? 0, 0)
        let endVar = endSeconds.map { ", end: \($0)" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
          #player { position: absolute; inset: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player = null;
          var wantsPlay = \(isActive);
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              videoId: '\(safeID)',
              playerVars: {
                playsinline: 1, controls: 0, rel: 0, modestbranding: 1,
                origin: '\(Self.origin)', start: \(start)\(endVar)
              },
              events: {
                onReady: function () { if (wantsPlay) { player.playVideo(); } },
                onStateChange: function (e) {
                  if (e.data === YT.PlayerState.ENDED) { player.seekTo(\(start)); player.playVideo(); }
                }
              }
            });
          }
          function setActive(active) {
            wantsPlay = active;
            if (!player || !player.playVideo) { return; }
            if (active) { player.playVideo(); } else { player.pauseVideo(); }
          }
        </script>
        </body>
        </html>
        """
    }
}
