import Foundation

/// Ein Meeting (meist ein Termin aus dem Kalender) mit Transkript. Das Transkript liegt als Datei im Ordner des Kunden,
/// damit Claude Code es dort findet; Aufgaben daraus verweisen über `TaskItem.meetingID` auf das Meeting.
public struct Meeting: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// Termin im Kalender (genau diese Wiederholung), sonst `nil`
    public var eventID: String?
    public var title: String
    public var start: Date
    public var end: Date
    public var customerID: UUID?
    /// Vollständiger Pfad der Transkript-Datei
    public var transcriptPath: String?
    /// Wann Aufgaben daraus angelegt wurden (oder es ohne Aufgaben als erledigt markiert wurde)
    public var processedAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        eventID: String? = nil,
        title: String,
        start: Date,
        end: Date,
        customerID: UUID? = nil,
        transcriptPath: String? = nil,
        processedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.eventID = eventID
        self.title = title
        self.start = start
        self.end = end
        self.customerID = customerID
        self.transcriptPath = transcriptPath
        self.processedAt = processedAt
        self.createdAt = createdAt
    }

    public var isProcessed: Bool { processedAt != nil }
    public var hasTranscript: Bool { !(transcriptPath ?? "").isEmpty }
}

/// Ordner und Dateien für Kunden und Meetings, und was Claude Code darin vorfindet.
public enum MeetingFiles {
    /// Unterordner im Kundenordner für Transkripte
    public static let meetingsFolder = "Meetings"
    /// Anweisungen für Claude Code im Kundenordner
    public static let instructionsFile = "CLAUDE.md"

    /// Ordnername für einen Kunden: der Name ohne Zeichen, die in Pfaden stören.
    public static func folderName(for customerName: String) -> String {
        let cleaned = clean(customerName)
        return cleaned.isEmpty ? "Kunde" : cleaned
    }

    /// „2026-11-26 1400 Weekly Status Meeting - ceSA.md“: sortiert nach Datum, lesbar im Finder.
    public static func fileName(title: String, start: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        let stamp = String(
            format: "%04d-%02d-%02d %02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
        var name = clean(title)
        if name.count > 80 { name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? "\(stamp) Meeting.md" : "\(stamp) \(name).md"
    }

    /// Schrägstriche, Doppelpunkte und Steuerzeichen raus, Leerraum zusammengefasst.
    static func clean(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let replaced = text.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }.joined()
        return replaced
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    /// Transkript als Markdown mit Kopf (Titel, Zeit, Kunde), so wie es im Kundenordner liegt.
    public static func document(
        title: String,
        start: Date,
        end: Date,
        customerName: String?,
        transcript: String,
        calendar: Calendar = .current
    ) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: start)
        let date = String(format: "%02d.%02d.%04d", day.day ?? 0, day.month ?? 0, day.year ?? 0)
        var lines = ["# \(title)", "", "\(date), \(clock(start, calendar))–\(clock(end, calendar))"]
        if let customerName, !customerName.isEmpty { lines.append("Kunde: \(customerName)") }
        lines += ["", "## Transkript", "", transcript.trimmingCharacters(in: .whitespacesAndNewlines), ""]
        return lines.joined(separator: "\n")
    }

    private static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Ist das ein WebVTT-Transkript (z. B. aus Teams)?
    public static func isVTT(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT")
    }

    /// WebVTT (Teams) → lesbarer Text: Nummern und Zeitstempel weg, aufeinanderfolgende Sätze derselben Person
    /// in einem Absatz („Max Muster: …“).
    public static func plainTranscript(fromVTT text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var paragraphs: [(speaker: String?, text: String)] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            for line in lines[(timing + 1)...] {
                let (speaker, spoken) = cue(line)
                guard !spoken.isEmpty else { continue }
                if let last = paragraphs.last, last.speaker == speaker {
                    // Teams wiederholt manchmal dieselbe Zeile
                    if last.text.hasSuffix(spoken) { continue }
                    paragraphs[paragraphs.count - 1].text += " " + spoken
                } else {
                    paragraphs.append((speaker, spoken))
                }
            }
        }
        return paragraphs
            .map { paragraph in paragraph.speaker.map { "\($0): \(paragraph.text)" } ?? paragraph.text }
            .joined(separator: "\n\n")
    }

    /// Eine Textzeile: Sprecher aus „<v Name>“, Text ohne Tags.
    static func cue(_ line: String) -> (speaker: String?, text: String) {
        var speaker: String?
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("<v"), let close = trimmed.firstIndex(of: ">") {
            // „<v Max Muster>“ oder „<v.loud Max Muster>“
            let inside = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close]
            let name = inside.drop { $0 != " " && $0 != "\t" }.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { speaker = name }
        }
        return (speaker, stripTags(trimmed))
    }

    private static func stripTags(_ text: String) -> String {
        var result = ""
        var inTag = false
        for character in text {
            if character == "<" { inTag = true; continue }
            if character == ">" { inTag = false; continue }
            if !inTag { result.append(character) }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Erste Fassung der CLAUDE.md für einen Kundenordner: was Claude Code dort tun soll und wie es an Tagwerk kommt.
    public static func claudeInstructions(customerName: String) -> String {
        """
        # \(customerName)

        Dieser Ordner gehört zum Kunden „\(customerName)“. Aufgaben, Zeiten und Meetings verwaltet die Mac-App Tagwerk; \
        du erreichst sie über den MCP-Server „tagwerk“.

        ## Meetings
        - Transkripte liegen in `\(meetingsFolder)/` und in Tagwerk am Termin.
        - „Neue Meetings?“: `meetings` mit kunde „\(customerName)“ und nur_offen aufrufen und kurz auflisten.
        - Aufgaben aus einem Meeting: Transkript mit `meeting_transkript` lesen, konkrete Aufgaben für mich vorschlagen \
        (kurzer Titel, Schätzung, wenn klar; Aufgaben anderer nur als Notiz). Erst nach meinem Okay mit `aufgabe_anlegen` \
        und dem Parameter `meeting` anlegen; Kunde und Verweis aufs Meeting kommen dann von selbst.
        - Kommt nichts für mich heraus: `meeting_erledigt`.

        ## Arbeit an Aufgaben
        - Vor der Arbeit an einer Tagwerk-Aufgabe `timer_starten`, danach `timer_stoppen`.
        - Was erledigt wurde, als Bearbeitung mit `aufgabe_aendern` (Parameter beschreibung) eintragen: \
        Das geht beim Tagesabschluss als Worklog ins Ticket.
        - Technische Details zur Übergabe in die Notizen der Aufgabe schreiben.

        ## Über den Kunden
        Ansprechpartner, Systeme, Zugänge (ohne Passwörter), Besonderheiten: hier ergänzen.

        """
    }
}

/// Link, der in der Claude-App (Desktop) eine neue Claude-Code-Sitzung öffnet: im Ordner, mit vorausgefüllter Bitte.
/// Format laut Anthropic: `claude://code/new?q=…&folder=…`; die App fragt vor dem Ordner einmal nach.
public enum ClaudeDesktopLink {
    /// Die App kürzt längere Bitten.
    public static let maximumPromptLength = 14_000

    public static func newCodeSession(prompt: String?, folder: String?) -> URL? {
        var parameters: [String] = []
        if let prompt, !prompt.isEmpty {
            parameters.append("q=" + encode(String(prompt.prefix(maximumPromptLength))))
        }
        if let folder, !folder.isEmpty {
            parameters.append("folder=" + encode(folder))
        }
        return URL(string: "claude://code/new" + (parameters.isEmpty ? "" : "?" + parameters.joined(separator: "&")))
    }

    /// Streng kodiert: nur Buchstaben, Ziffern und „-._~“ bleiben, alles andere (auch &, =, +, Umlaute) wird %XX.
    static func encode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
