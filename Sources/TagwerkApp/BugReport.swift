import AppKit
import Foundation

/// „Fehler melden“: Beschreibung, Umgebung, Protokoll und ein Absturzbericht von macOS, falls vorhanden.
/// Geht als GitHub-Issue (Seite im Browser) oder als Datei in „Downloads“ bzw. Text für den Chat.
enum BugReport {
    static let issuesURL = "https://github.com/boberbeck/todo/issues/new"

    /// Absturzberichte von macOS zu Tagwerk aus den letzten sieben Tagen, neueste zuerst.
    static func crashReports() -> [URL] {
        let folders = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports/Retired"),
        ]
        let limit = Date().addingTimeInterval(-7 * 86400)
        var found: [(URL, Date)] = []
        for folder in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for url in files where url.lastPathComponent.hasPrefix("Tagwerk") && ["ips", "crash", "diag"].contains(url.pathExtension) {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if date > limit { found.append((url, date)) }
            }
        }
        return found.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Ein Absturz seit dem letzten Start, der noch nicht gemeldet wurde?
    static func unreportedCrash() -> URL? {
        guard let newest = crashReports().first else { return nil }
        let seen = UserDefaults.standard.string(forKey: Preferences.lastSeenCrashKey)
        return seen == newest.lastPathComponent ? nil : newest
    }

    static func markCrashSeen(_ url: URL?) {
        guard let url else { return }
        UserDefaults.standard.set(url.lastPathComponent, forKey: Preferences.lastSeenCrashKey)
    }

    /// Kurzer Überblick über Fassung und Anbindungen (ohne Schlüssel oder Kundendaten).
    @MainActor
    static func environment(model: AppModel) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let calendar: String
        switch model.calendarAccess {
        case .granted: calendar = "freigegeben"
        case .denied: calendar = "verweigert"
        case .notDetermined: calendar = "noch nicht gefragt"
        case .unavailable: calendar = "nicht verfügbar"
        }
        let lines = [
            "Tagwerk \(AppVersion.description)",
            "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(SigningSetup.currentSignature)",
            "Ort: \(Bundle.main.bundleURL.path)",
            "Kalender: \(calendar)",
            "ManageEngine: \(model.canUseManageEngine ? "eingerichtet" : "nicht eingerichtet")\(model.ticketSyncMessage.map { " · zuletzt: \($0)" } ?? "")",
            "Claude unterwegs: \(model.remote.isEnabled ? "an" : "aus") · Pomodoro: \(model.isPomodoroEnabled ? "an" : "aus")",
            "Daten: \(model.tasks.count) Aufgaben, \(model.entries.count) Zeiteinträge, \(model.customers.count) Kunden",
        ]
        return lines.joined(separator: "\n")
    }

    /// Text des Berichts. `logLines` begrenzt das Protokoll (für die Adresse der GitHub-Seite kürzer).
    @MainActor
    static func text(description: String, expected: String, model: AppModel, logLines: Int, crash: URL?) -> String {
        var parts: [String] = []
        parts.append("## Was ist passiert?\n\n\(description.trimmingCharacters(in: .whitespacesAndNewlines))")
        if !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("## Was hätte passieren sollen?\n\n\(expected.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        parts.append("## Umgebung\n\n```\n\(environment(model: model))\n```")
        if logLines > 0 {
            parts.append("## Protokoll (letzte \(logLines) Einträge)\n\n```\n\(AppLog.recentLines(logLines).joined(separator: "\n"))\n```")
        }
        if let crash {
            parts.append("## Absturzbericht\n\n\(crash.lastPathComponent) (in der gesicherten Datei enthalten)")
        }
        return parts.joined(separator: "\n\n")
    }

    /// Ganze Datei für „Downloads“: Bericht, ausführliches Protokoll und Absturzbericht.
    @MainActor
    static func save(description: String, expected: String, model: AppModel, includeLog: Bool, crash: URL?) throws -> URL {
        var content = text(description: description, expected: expected, model: model, logLines: 0, crash: nil)
        if includeLog {
            content += "\n\n## Protokoll\n\n```\n\(AppLog.recentText(maxBytes: 300_000))\n```"
        }
        if let crash, let report = try? String(contentsOf: crash, encoding: .utf8) {
            content += "\n\n## Absturzbericht \(crash.lastPathComponent)\n\n```\n\(report.prefix(400_000))\n```"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let url = folder.appendingPathComponent("Tagwerk-Fehlerbericht-\(formatter.string(from: Date())).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// GitHub-Seite für ein neues Issue, vorausgefüllt. Die Adresse darf nicht zu lang werden.
    @MainActor
    static func issueURL(title: String, description: String, expected: String, model: AppModel, includeLog: Bool, crash: URL?) -> URL? {
        var lines = includeLog ? 60 : 0
        while true {
            var body = text(description: description, expected: expected, model: model, logLines: lines, crash: crash)
            body += "\n\n_Ausführlicher Bericht: die Datei aus „Downloads“ hier hineinziehen._"
            var components = URLComponents(string: issuesURL)!
            components.queryItems = [
                URLQueryItem(name: "title", value: title.isEmpty ? "Fehler: \(description.prefix(60))" : title),
                URLQueryItem(name: "body", value: body),
                URLQueryItem(name: "labels", value: "bug"),
            ]
            if let url = components.url, url.absoluteString.count < 7500 || lines == 0 { return url }
            lines = lines > 10 ? lines - 15 : 0
        }
    }
}
