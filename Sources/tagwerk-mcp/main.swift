import Foundation
import TagwerkCore
import TagwerkMCP

// MCP-Server für Tagwerk. Claude Desktop oder Claude Code starten dieses Programm
// und sprechen über stdin/stdout mit ihm. Meldungen gehen nur nach stderr,
// damit stdout ausschließlich MCP-Nachrichten enthält.

func log(_ message: String) {
    FileHandle.standardError.write(Data("tagwerk-mcp: \(message)\n".utf8))
}

let environment = ProcessInfo.processInfo.environment
let databaseURL: URL
if let path = environment["TAGWERK_DB"], !path.isEmpty {
    databaseURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
} else {
    databaseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Tagwerk", isDirectory: true)
        .appendingPathComponent("tagwerk.sqlite")
}

do {
    let store = try SQLiteStore(url: databaseURL)
    // Liegt der Server in Tagwerk.app, gehört er zum Bundle der App und liest ihre Einstellungen direkt.
    let appID = "local.tagwerk.app"
    let defaults = Bundle.main.bundleIdentifier == appID ? UserDefaults.standard : UserDefaults(suiteName: appID)
    let tools = TagwerkTools(store: store, defaults: defaults)
    // Stand der App, zu der dieser Server gehört (steht beim Bau in Info.plist)
    let info = Bundle.main.infoDictionary ?? [:]
    let short = info["CFBundleShortVersionString"] as? String ?? "0.1"
    let build = info["CFBundleVersion"] as? String
    let version = build.map { "\(short) (\($0))" } ?? short
    let server = MCPServer(tools: tools, serverVersion: version)
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--http") {
        // Über HTTP für Claude im Browser und auf dem Handy (über einen Tunnel). Nur 127.0.0.1.
        let port = arguments.indices.contains(flag + 1) ? UInt16(arguments[flag + 1]) ?? 8765 : 8765
        guard let token = environment["TAGWERK_HTTP_TOKEN"], token.count >= 16 else {
            log("TAGWERK_HTTP_TOKEN fehlt oder ist zu kurz (mindestens 16 Zeichen).")
            exit(2)
        }
        let listener = MCPHTTPListener(handler: MCPHTTPHandler(server: server, token: token), port: port)
        do {
            try listener.bind()
        } catch {
            log("\(error)")
            exit(3)
        }
        log("bereit über HTTP auf http://127.0.0.1:\(port)\(MCPHTTPHandler.path(token: "…")), Stand \(version), Daten: \(databaseURL.path)")
        listener.run()
    }
    log("bereit, Stand \(version), Daten: \(databaseURL.path)")
    server.run()
} catch {
    log("Datenbank lässt sich nicht öffnen: \(error)")
    exit(1)
}
