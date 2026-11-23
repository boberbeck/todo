import Foundation

/// Protokoll für die Fehlersuche: ~/Library/Logs/Tagwerk/tagwerk.log.
/// Steht drin, was beim SAP-Abruf, mit ManageEngine, Kalender, Claude und Updates passiert ist.
/// Nie Passwörter, Schlüssel oder Tokens hineinschreiben.
enum AppLog {
    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "FEHLER"
    }

    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Tagwerk", isDirectory: true)
    static let file = folder.appendingPathComponent("tagwerk.log")
    static let previousFile = folder.appendingPathComponent("tagwerk.1.log")
    private static let maximumSize = 2 * 1024 * 1024
    private static let queue = DispatchQueue(label: "tagwerk.log", qos: .utility)
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func info(_ category: String, _ message: String) { write(.info, category, message) }
    static func warning(_ category: String, _ message: String) { write(.warning, category, message) }
    static func error(_ category: String, _ message: String) { write(.error, category, message) }

    static func write(_ level: Level, _ category: String, _ message: String) {
        let date = Date()
        let line = "\(formatter.string(from: date)) \(level.rawValue) [\(category)] \(redact(message).replacingOccurrences(of: "\n", with: " ⏎ "))\n"
        queue.async {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                rotateIfNeeded()
                if let handle = try? FileHandle(forWritingTo: file) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data(line.utf8))
                } else {
                    try Data(line.utf8).write(to: file)
                }
            } catch {
                // Protokoll ist Beiwerk; Fehler beim Schreiben bleiben still.
            }
        }
    }

    /// Die letzten Einträge (höchstens `maxBytes`), älteste zuerst; auch aus der vorigen Datei, wenn nötig.
    static func recentText(maxBytes: Int = 200_000) -> String {
        queue.sync {
            var data = (try? Data(contentsOf: file)) ?? Data()
            if data.count < maxBytes, let previous = try? Data(contentsOf: previousFile) {
                data = previous.suffix(maxBytes - data.count) + data
            }
            var text = String(decoding: data.suffix(maxBytes), as: UTF8.self)
            if data.count > maxBytes, let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            }
            return text
        }
    }

    /// Letzte Zeilen, z. B. für den Text eines Fehlerberichts.
    static func recentLines(_ count: Int) -> [String] {
        recentText(maxBytes: 400_000).split(separator: "\n").suffix(count).map(String.init)
    }

    private static func rotateIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int, size > maximumSize else { return }
        try? FileManager.default.removeItem(at: previousFile)
        try? FileManager.default.moveItem(at: file, to: previousFile)
    }

    /// Sicherheitsnetz: Zeichenfolgen, die wie Schlüssel aussehen, unkenntlich machen.
    static func redact(_ text: String) -> String {
        var result = text
        let patterns = [
            #"(?i)(authtoken|authorization|bearer|token|password|passwort)([=: ]+)[^\s,;&]+"#,
            #"github_pat_[A-Za-z0-9_]+"#,
            #"/mcp/[A-Za-z0-9_-]{16,}"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = pattern.hasPrefix("(?i)") ? "$1$2•••" : (pattern.hasPrefix("/mcp") ? "/mcp/•••" : "•••")
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }
}
