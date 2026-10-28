import SwiftUI
import WebKit

/// Redă un segment dintr-un clip YouTube prin playerul oficial (IFrame API), în buclă.
/// Folosim embed-ul în loc să descărcăm clipul, ca să respectăm termenii YouTube.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String
    let startSeconds: Int?
    let endSeconds: Int?
    let isActive: Bool
    var rate: Float = 1

    /// YouTube refuză embed-urile fără un origin/referrer valid (eroarea 153).
    private static let origin = "https://mybucharest.app"

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: Coordinator.messageName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        // Atingerile merg la gesturile aplicației (pauză, 2×), nu la player: altfel un tap pe
        // titlu deschide YouTube sau playerul trece pe tot ecranul și nu mai ajungi la butonul X.
        webView.isUserInteractionEnabled = false
        webView.loadHTMLString(html, baseURL: URL(string: Self.origin))
        context.coordinator.isActive = isActive
        context.coordinator.rate = rate
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.rate != rate {
            coordinator.rate = rate
            webView.evaluateJavaScript("setRate(\(rate))")
        }
        if coordinator.isActive != isActive {
            coordinator.isActive = isActive
            webView.evaluateJavaScript("setActive(\(isActive))")
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.evaluateJavaScript("setActive(false)")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let messageName = "player"

        weak var webView: WKWebView?
        var isActive = false
        var rate: Float = 1

        /// Pornirea cu sunet e permisă doar când o cere aplicația (evaluateJavaScript contează ca
        /// gest al utilizatorului), nu playerul singur; de aceea pagina anunță când e gata.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.body as? String == "ready" else { return }
            webView?.evaluateJavaScript("setRate(\(rate)); setActive(\(isActive));")
        }
    }

    private var html: String {
        let safeID = videoID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        let start = max(startSeconds ?? 0, 0)
        let endVar = endSeconds.map { ", end: \($0)" } ?? ""
        // Playerul e mai mare decât ecranul și centrat, ca un video vertical „aspect fill”:
        // bara de sus (titlu, canal) și sigla de jos rămân în afara cadrului.
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
          #frame {
            position: absolute; top: 50%; left: 50%;
            height: calc(100vh + 160px); width: calc((100vh + 160px) * 16 / 9);
            transform: translate(-50%, -50%);
          }
          #player { width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="frame"><div id="player"></div></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player = null;
          var wantsPlay = \(isActive);
          var wantsRate = \(rate);
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              width: '100%', height: '100%',
              videoId: '\(safeID)',
              playerVars: {
                playsinline: 1, controls: 0, rel: 0, modestbranding: 1, disablekb: 1,
                fs: 0, iv_load_policy: 3,
                origin: '\(Self.origin)', start: \(start)\(endVar)
              },
              events: {
                onReady: function () {
                  window.webkit.messageHandlers.player.postMessage('ready');
                },
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
          function setRate(rate) {
            wantsRate = rate;
            if (player && player.setPlaybackRate) { player.setPlaybackRate(rate); }
          }
        </script>
        </body>
        </html>
        """
    }
}
