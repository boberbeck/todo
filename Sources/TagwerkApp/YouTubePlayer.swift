import AppKit
import SwiftUI
import TagwerkCore
import WebKit

/// Spielt einen YouTube-Link mit dem offiziellen eingebetteten Player von YouTube.
/// YouTube verlangt einen sichtbaren Player; deshalb zeigt der Fokus ihn an und hält ihn an, wenn der Fokus zugeht.
@MainActor
final class YouTubePlayer {
    /// spielt, Titel des Videos, Problem
    var onChange: ((Bool, String?, String?) -> Void)?

    let webView: WKWebView
    private(set) var loadedLink: YouTubeLink?
    private var isReady = false
    private var handler: YouTubeMessageHandler?

    /// Herkunft, mit der Tagwerk sich beim Player meldet (YouTube verlangt eine).
    static let origin = URL(string: "https://local.tagwerk.app")!

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 356, height: 200), configuration: configuration)
        let handler = YouTubeMessageHandler()
        controller.add(handler, name: "tagwerk")
        self.handler = handler
        handler.player = self
    }

    func play(_ link: YouTubeLink) {
        if link == loadedLink, isReady {
            run("player.playVideo()")
        } else {
            load(link)
        }
    }

    func pause() {
        guard isReady else { return }
        run("player.pauseVideo()")
    }

    func next() {
        guard isReady else { return }
        run("player.nextVideo()")
    }

    private func load(_ link: YouTubeLink) {
        loadedLink = link
        isReady = false
        webView.loadHTMLString(Self.html(for: link), baseURL: Self.origin)
    }

    private func run(_ script: String) {
        webView.evaluateJavaScript("if (window.player) { \(script) }", completionHandler: nil)
    }

    fileprivate func received(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        if let code = message["error"] as? Int {
            AppLog.warning("YouTube", "Player meldet Fehler \(code)")
            onChange?(false, nil, Self.problem(for: code))
            return
        }
        if message["ready"] != nil {
            isReady = true
        }
        let title = (message["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let state = message["state"] as? Int
        // 1 = spielt, 3 = lädt noch (zählt als spielend), 2 = Pause, 0 = Ende
        onChange?(state == 1 || state == 3, title, nil)
    }

    static func problem(for code: Int) -> String {
        switch code {
        case 2: return "YouTube kann diesen Link nicht abspielen."
        case 100: return "Das Video gibt es nicht mehr oder es ist privat."
        case 101, 150: return "Der Kanal erlaubt das Abspielen außerhalb von YouTube nicht. Bitte ein anderes Video wählen."
        case 153: return "YouTube lehnt den eingebetteten Player gerade ab."
        default: return "YouTube meldet Fehler \(code)."
        }
    }

    /// Seite mit dem offiziellen Player (IFrame-API). Video, Playlist oder beides.
    static func html(for link: YouTubeLink) -> String {
        // Ruhig wie ein Albumcover: ohne YouTube-Bedienleiste (Tagwerk hat eigene Knöpfe), ohne Einblendungen und Vollbild.
        // Das Bild bleibt sichtbar; nur Ton ist bei eingebetteten YouTube-Videos nicht erlaubt.
        var vars = ["autoplay: 1", "playsinline: 1", "rel: 0", "controls: 0", "disablekb: 1", "fs: 0", "iv_load_policy: 3", "origin: '\(origin.absoluteString)'"]
        if let list = link.listID {
            vars.append("listType: 'playlist'")
            vars.append("list: '\(list)'")
        }
        let video = link.videoID.map { "videoId: '\($0)'," } ?? ""
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>html, body { margin: 0; height: 100%; background: #000; overflow: hidden; } #player { width: 100%; height: 100%; }</style>
        </head><body>
        <div id="player"></div>
        <script>
        function send(message) { window.webkit.messageHandlers.tagwerk.postMessage(message); }
        function title() { try { return player.getVideoData().title || ''; } catch (e) { return ''; } }
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            width: '100%', height: '100%',
            \(video)
            playerVars: { \(vars.joined(separator: ", ")) },
            events: {
              onReady: function () { send({ ready: true, title: title() }); player.playVideo(); },
              onStateChange: function (event) { send({ state: event.data, title: title() }); },
              onError: function (event) { send({ error: event.data }); }
            }
          });
        }
        </script>
        <script src="https://www.youtube.com/iframe_api"></script>
        </body></html>
        """
    }
}

/// Nimmt die Nachrichten der Player-Seite entgegen (Bereit, Zustand, Fehler).
@MainActor
private final class YouTubeMessageHandler: NSObject, WKScriptMessageHandler {
    weak var player: YouTubePlayer?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        player?.received(message.body)
    }
}

/// Der Player im Fokus, sichtbar wie von YouTube verlangt (mindestens 200 Punkte hoch).
struct YouTubePlayerView: NSViewRepresentable {
    let player: YouTubePlayer

    func makeNSView(context: Context) -> WKWebView {
        player.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
