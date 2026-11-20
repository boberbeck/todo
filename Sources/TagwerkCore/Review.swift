import Foundation

/// Ein Ziel für eine Woche, optional für einen Kunden. Aufgaben können darauf einzahlen.
public struct WeeklyGoal: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// Montag der Woche
    public var weekStart: LocalDate
    public var customerID: UUID?
    public var title: String
    public var isDone: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        weekStart: LocalDate,
        customerID: UUID? = nil,
        title: String,
        isDone: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.weekStart = weekStart
        self.customerID = customerID
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

/// Auswertungen für den Wochenrückblick.
public enum WeeklyReview {
    /// Montag bis Sonntag der Woche, in der `day` liegt.
    public static func days(ofWeekContaining day: LocalDate, calendar: Calendar = .current) -> [LocalDate] {
        let monday = day.startOfWeek(calendar: calendar)
        return (0..<7).map { monday.adding(days: $0, calendar: calendar) }
    }

    public static func interval(ofWeekStarting monday: LocalDate, calendar: Calendar = .current) -> DateInterval {
        DateInterval(
            start: monday.startDate(calendar: calendar),
            end: monday.adding(days: 7, calendar: calendar).startDate(calendar: calendar)
        )
    }

    /// Zeit, die in der Woche auf Aufgaben dieses Ziels erfasst wurde.
    public static func trackedSeconds(
        for goal: WeeklyGoal,
        tasks: [TaskItem],
        entries: [TimeEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let taskIDs = Set(tasks.filter { $0.goalID == goal.id }.map(\.id))
        let week = interval(ofWeekStarting: goal.weekStart, calendar: calendar)
        return entries
            .filter { entry in entry.taskID.map { taskIDs.contains($0) } ?? false }
            .reduce(0) { $0 + TimeMath.overlap(of: $1, with: week, now: now) }
    }
}

/// Was mit einer Pause passiert, die der Leerlauf-Hinweis erkannt hat.
public enum IdleDecision: Equatable, Sendable {
    /// Die Zeit war Arbeit, alles bleibt.
    case keep
    /// Die Pause zählt nicht; der Timer läuft ab jetzt weiter.
    case discard
    /// Die Pause gehört zu einer anderen Aufgabe (z. B. ein spontanes Telefonat); danach weiter wie vorher.
    case assign(to: UUID)
}

public extension TimerLogic {
    /// Wendet die Entscheidung auf den laufenden Eintrag an. `idleStart` ist der Beginn der Pause.
    static func resolveIdle(
        entries: [TimeEntry],
        idleStart: Date,
        now: Date,
        decision: IdleDecision
    ) -> Change {
        guard let running = running(in: entries), let taskID = running.taskID else { return Change() }
        var change = Change()
        switch decision {
        case .keep:
            return change
        case .discard, .assign:
            var stopped = running
            stopped.end = max(running.start, idleStart)
            if stopped.duration(now: now) < minimumDuration {
                change.discarded.append(stopped)
            } else {
                change.stopped.append(stopped)
            }
            if case .assign(let otherTask) = decision {
                change.stopped.append(TimeEntry(taskID: otherTask, start: idleStart, end: now))
            }
            change.started = TimeEntry(taskID: taskID, start: now)
            return change
        }
    }
}

/// Liest Betreff und Absender aus einer Mail-Datei (.eml), z. B. per Drag-and-drop aus Outlook.
public enum EmailHeaderParser {
    public struct Header: Equatable, Sendable {
        public var subject: String?
        public var from: String?
        public var date: String?
        public var messageID: String?
    }

    public static func parse(_ data: Data) -> Header {
        let text = String(decoding: data.prefix(64 * 1024), as: UTF8.self)
        // Kopf endet an der ersten Leerzeile
        let headerPart: Substring
        if let range = text.range(of: "\r\n\r\n") ?? text.range(of: "\n\n") {
            headerPart = text[..<range.lowerBound]
        } else {
            headerPart = Substring(text)
        }
        var fields: [String: String] = [:]
        var currentName: String?
        for rawLine in headerPart.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let first = line.first, first == " " || first == "\t", let name = currentName {
                fields[name, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if fields[name] == nil {
                    fields[name] = value
                }
                currentName = name
            }
        }
        return Header(
            subject: fields["subject"].map(decodeEncodedWords),
            from: fields["from"].map(decodeEncodedWords).map(displayName),
            date: fields["date"],
            messageID: fields["message-id"]
        )
    }

    /// "Max Muster <max@example.com>" → "Max Muster", sonst die Adresse.
    static func displayName(_ value: String) -> String {
        if let angle = value.firstIndex(of: "<") {
            let name = value[..<angle].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
            return value[value.index(after: angle)...].trimmingCharacters(in: CharacterSet(charactersIn: "> "))
        }
        return value
    }

    /// Dekodiert RFC-2047-Wörter wie "=?UTF-8?B?...?=" und "=?ISO-8859-1?Q?...?=".
    static func decodeEncodedWords(_ value: String) -> String {
        var result = ""
        var rest = Substring(value)
        var lastWasEncoded = false
        while let start = rest.range(of: "=?") {
            let before = rest[..<start.lowerBound]
            if !(lastWasEncoded && before.allSatisfy(\.isWhitespace)) {
                result += before
            }
            let afterStart = rest[start.upperBound...]
            let parts = afterStart.split(separator: "?", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, parts[3].hasPrefix("=") else {
                result += rest[start.lowerBound...]
                return result
            }
            let charset = String(parts[0])
            let encoding = parts[1].uppercased()
            let payload = String(parts[2])
            let decoded: String?
            if encoding == "B" {
                decoded = Data(base64Encoded: payload).flatMap { string(from: $0, charset: charset) }
            } else if encoding == "Q" {
                decoded = decodeQ(payload, charset: charset)
            } else {
                decoded = nil
            }
            result += decoded ?? "=?\(charset)?\(encoding)?\(payload)?="
            lastWasEncoded = decoded != nil
            rest = parts[3].dropFirst()
        }
        result += rest
        return result
    }

    private static func decodeQ(_ payload: String, charset: String) -> String? {
        var bytes: [UInt8] = []
        var index = payload.startIndex
        while index < payload.endIndex {
            let character = payload[index]
            if character == "_" {
                bytes.append(0x20)
            } else if character == "=",
                      let end = payload.index(index, offsetBy: 3, limitedBy: payload.endIndex),
                      let byte = UInt8(payload[payload.index(after: index)..<end], radix: 16) {
                bytes.append(byte)
                index = end
                continue
            } else {
                bytes.append(contentsOf: Array(String(character).utf8))
            }
            index = payload.index(after: index)
        }
        return string(from: Data(bytes), charset: charset)
    }

    private static func string(from data: Data, charset: String) -> String? {
        switch charset.lowercased() {
        case "iso-8859-1", "latin1", "iso-8859-15", "windows-1252", "cp1252":
            return String(data: data, encoding: .isoLatin1)
        default:
            return String(data: data, encoding: .utf8)
        }
    }
}

/// Welche alten Sicherungen weg können.
public enum BackupPolicy {
    public static let filePrefix = "tagwerk-"
    public static let fileExtension = "sqlite"

    public static func fileName(for day: LocalDate) -> String {
        "\(filePrefix)\(day.string).\(fileExtension)"
    }

    /// Behält die neuesten `keep` Sicherungen (nach Datum im Dateinamen), gibt die übrigen zurück.
    public static func filesToDelete(_ names: [String], keep: Int) -> [String] {
        let backups = names
            .filter { $0.hasPrefix(filePrefix) && $0.hasSuffix(".\(fileExtension)") }
            .sorted(by: >)
        return Array(backups.dropFirst(max(0, keep)))
    }
}

/// Alle Zeiten als Tabelle, z. B. für Excel oder die eigene Ablage.
public enum TimeExport {
    public static func csv(
        entries: [TimeEntry],
        tasks: [TaskItem],
        customers: [Customer],
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let customerByID = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0) })
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = Locale(identifier: "de_DE")
        timeFormatter.dateFormat = "HH:mm"

        var lines = ["Datum;Beginn;Ende;Minuten;Kunde;Aufgabe;Quelle;Ticket;Arbeitsart;PSP-Element;Beschreibung"]
        for entry in entries.sorted(by: { $0.start < $1.start }) {
            let task = entry.taskID.flatMap { taskByID[$0] }
            let customer = task?.customerID.flatMap { customerByID[$0] }
            let end = entry.end ?? now
            let fields = [
                formatter.string(from: entry.start),
                timeFormatter.string(from: entry.start),
                entry.end == nil ? "läuft" : timeFormatter.string(from: end),
                String(Int(entry.duration(now: now) / 60)),
                customer?.name ?? "",
                task?.title ?? "",
                task?.source.label ?? "",
                task?.linkedTicketNumber ?? "",
                task?.workType?.label ?? "",
                task?.pspElement ?? "",
                task?.workDescription ?? "",
            ]
            lines.append(fields.map(escape).joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(";") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
