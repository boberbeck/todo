import AppKit
import Foundation
import Observation

/// Fernzugriff für Claude im Browser und auf dem Handy: Solange Tagwerk läuft, startet es `tagwerk-mcp --http`
/// auf 127.0.0.1 und auf Wunsch einen Tunnel (z. B. Tailscale Funnel), über den claude.ai den Mac erreicht.
/// Geschützt durch einen langen geheimen Schlüssel im Pfad; er liegt im Schlüsselbund.
@MainActor
@Observable
final class RemoteAccess {
    enum State: Equatable {
        case off
        case running
        case failed(String)
    }

    private(set) var serverState: State = .off
    private(set) var tunnelState: State = .off
    /// Adresse, die der Tunnel gemeldet hat (z. B. https://mein-mac.tail1234.ts.net)
    private(set) var detectedPublicURL: String?
    private(set) var tunnelOutput = ""
    private(set) var checkMessage: String?

    @ObservationIgnored private var server: Process?
    @ObservationIgnored private var tunnel: Process?
    @ObservationIgnored private var cachedToken: String?

    static let tokenAccount = "remote-mcp-token"

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    // MARK: Einstellungen

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Preferences.remoteEnabledKey)
    }

    /// Pfad mit dem Schlüssel, wie ihn tagwerk-mcp erwartet.
    static func path(token: String) -> String { "/mcp/\(token)" }

    var port: Int {
        let stored = UserDefaults.standard.integer(forKey: Preferences.remotePortKey)
        return (1024...65535).contains(stored) ? stored : 8765
    }

    var publicBaseURL: String {
        let stored = (UserDefaults.standard.string(forKey: Preferences.remotePublicURLKey) ?? "").trimmingCharacters(in: .whitespaces)
        let base = stored.isEmpty ? (detectedPublicURL ?? "") : stored
        var trimmed = base
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    var tunnelCommand: String {
        UserDefaults.standard.string(forKey: Preferences.remoteTunnelCommandKey) ?? ""
    }

    /// Geheimer Schlüssel; wird beim ersten Mal erzeugt.
    var token: String {
        if let cachedToken { return cachedToken }
        if let stored = Keychain.get(account: Self.tokenAccount), stored.count >= 16 {
            cachedToken = stored
            return stored
        }
        let fresh = Self.makeToken()
        Keychain.set(fresh, account: Self.tokenAccount)
        cachedToken = fresh
        return fresh
    }

    var localURL: String { "http://127.0.0.1:\(port)\(Self.path(token: token))" }

    /// Die Adresse für claude.ai › Einstellungen › Connectors.
    var connectorURL: String? {
        let base = publicBaseURL
        guard base.hasPrefix("https://") else { return nil }
        return base + Self.path(token: token)
    }

    /// Neuer Schlüssel: Die alte Adresse funktioniert danach nicht mehr.
    func renewToken() {
        let fresh = Self.makeToken()
        Keychain.set(fresh, account: Self.tokenAccount)
        cachedToken = fresh
        if isEnabled { restart() }
    }

    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: Starten und Stoppen

    func startIfEnabled() {
        if isEnabled { start() }
    }

    func restart() {
        stop()
        start()
    }

    func start() {
        startServer()
        startTunnel()
    }

    func stop() {
        server?.terminationHandler = nil
        server?.terminate()
        server = nil
        tunnel?.terminationHandler = nil
        tunnel?.terminate()
        tunnel = nil
        serverState = .off
        tunnelState = .off
    }

    private func startServer() {
        guard server == nil else { return }
        guard let url = ClaudeIntegration.serverURL else {
            serverState = .failed("tagwerk-mcp fehlt neben der App.")
            return
        }
        ClaudeIntegration.removeQuarantine(from: url)
        let process = Process()
        process.executableURL = url
        process.arguments = ["--http", String(port)]
        var environment = ProcessInfo.processInfo.environment
        environment["TAGWERK_HTTP_TOKEN"] = token
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            let message = String(decoding: errors.fileHandleForReading.availableData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                guard let self, self.server === finished else { return }
                self.server = nil
                self.serverState = .failed(message.isEmpty ? "Server beendet (Code \(finished.terminationStatus))." : message)
                AppLog.warning("Fernzugriff", "Server beendet: \(message)")
            }
        }
        do {
            try process.run()
            server = process
            serverState = .running
            AppLog.info("Fernzugriff", "Server gestartet auf Port \(port)")
        } catch {
            serverState = .failed("Startet nicht: \(error.localizedDescription)")
            AppLog.error("Fernzugriff", "Server startet nicht: \(error.localizedDescription)")
        }
    }

    private func startTunnel() {
        let command = tunnelCommand.trimmingCharacters(in: .whitespaces)
        guard tunnel == nil, !command.isEmpty else { return }
        let process = Process()
        // Login-Shell, damit Programme aus Homebrew gefunden werden
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command.replacingOccurrences(of: "{port}", with: String(port))]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.tunnelPrinted(chunk) }
        }
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self, self.tunnel === finished else { return }
                self.tunnel = nil
                let last = self.tunnelOutput.split(separator: "\n").suffix(3).joined(separator: " ")
                self.tunnelState = .failed(last.isEmpty ? "Tunnel beendet (Code \(finished.terminationStatus))." : last)
                AppLog.warning("Fernzugriff", "Tunnel beendet: \(last)")
            }
        }
        do {
            tunnelOutput = ""
            try process.run()
            tunnel = process
            tunnelState = .running
        } catch {
            tunnelState = .failed("Tunnel startet nicht: \(error.localizedDescription)")
        }
    }

    private func tunnelPrinted(_ chunk: String) {
        tunnelOutput = String((tunnelOutput + chunk).suffix(4000))
        if let found = Self.firstHTTPSURL(in: chunk) {
            detectedPublicURL = found
        }
    }

    /// Erste öffentliche https-Adresse in der Ausgabe eines Tunnels (Tailscale, cloudflared, ngrok).
    static func firstHTTPSURL(in text: String) -> String? {
        let pattern = #"https://[A-Za-z0-9.-]+\.(ts\.net|trycloudflare\.com|ngrok-free\.app|ngrok\.app|ngrok\.io|ngrok-free\.dev)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    // MARK: Prüfen

    /// Fragt den Server lokal und, wenn eingetragen, über die öffentliche Adresse wie claude.ai.
    func check() async {
        checkMessage = "Prüft …"
        var parts: [String] = []
        parts.append("Auf dem Mac: " + (await Self.probe(localURL) ?? "keine Antwort"))
        if let connectorURL {
            parts.append("Über den Tunnel: " + (await Self.probe(connectorURL) ?? "keine Antwort (Tunnel aus oder Adresse falsch)"))
        } else {
            parts.append("Öffentliche Adresse fehlt noch.")
        }
        checkMessage = parts.joined(separator: "\n")
    }

    private static func probe(_ address: String) async -> String? {
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"tagwerk-pruefung","version":"1"}}}"#.utf8)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(decoding: data, as: UTF8.self)
            if status == 200, text.contains("protocolVersion") { return "antwortet ✓" }
            return "HTTP \(status)"
        } catch {
            return error.localizedDescription
        }
    }
}
