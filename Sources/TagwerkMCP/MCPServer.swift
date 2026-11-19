import Foundation

/// Minimaler MCP-Server (Model Context Protocol) über stdio: JSON-RPC 2.0, eine Nachricht pro Zeile.
/// Unterstützt `initialize`, `ping`, `tools/list` und `tools/call`.
public final class MCPServer {
    public static let supportedVersions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
    public static let defaultVersion = "2025-06-18"

    private let tools: TagwerkTools
    private let serverVersion: String

    public init(tools: TagwerkTools, serverVersion: String = "0.1") {
        self.tools = tools
        self.serverVersion = serverVersion
    }

    /// Liest Zeilen von stdin und antwortet auf stdout, bis die Eingabe endet.
    public func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let response = handle(line: line) {
                FileHandle.standardOutput.write(Data((response + "\n").utf8))
            }
        }
    }

    /// Verarbeitet eine eingehende Nachricht. Gibt die Antwortzeile zurück, bei Benachrichtigungen `nil`.
    public func handle(line: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
            return encode(error: -32700, message: "Parse error", id: NSNull())
        }
        guard let message = object as? [String: Any] else {
            return encode(error: -32600, message: "Invalid Request", id: NSNull())
        }
        let id = message["id"]
        guard let method = message["method"] as? String else {
            // Antworten des Clients auf eigene Anfragen gibt es hier nicht.
            return nil
        }
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id else {
            // Benachrichtigung (z. B. notifications/initialized): keine Antwort
            return nil
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? Self.defaultVersion
            let version = Self.supportedVersions.contains(requested) ? requested : Self.defaultVersion
            return encode(result: [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "tagwerk", "title": "Tagwerk", "version": serverVersion],
                "instructions": TagwerkTools.instructions,
            ], id: id)
        case "ping":
            return encode(result: [:], id: id)
        case "tools/list":
            return encode(result: ["tools": tools.definitions], id: id)
        case "tools/call":
            guard let name = params["name"] as? String else {
                return encode(error: -32602, message: "Werkzeugname fehlt", id: id)
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard tools.names.contains(name) else {
                return encode(error: -32602, message: "Unbekanntes Werkzeug: \(name)", id: id)
            }
            do {
                let text = try tools.call(name: name, arguments: arguments)
                return encode(result: ["content": [["type": "text", "text": text]], "isError": false], id: id)
            } catch {
                return encode(result: ["content": [["type": "text", "text": String(describing: error)]], "isError": true], id: id)
            }
        default:
            return encode(error: -32601, message: "Method not found: \(method)", id: id)
        }
    }

    private func encode(result: [String: Any], id: Any) -> String {
        serialize(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func encode(error code: Int, message: String, id: Any) -> String {
        serialize(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func serialize(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#
        }
        return String(decoding: data, as: UTF8.self)
    }
}
