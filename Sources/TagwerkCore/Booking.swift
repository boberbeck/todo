import Foundation

/// Wohin eine Zeit gebucht wird: als Worklog ins Ticket in ManageEngine.
public enum BookingTarget: String, Codable, CaseIterable, Sendable, Identifiable {
    case manageEngine

    public var id: String { rawValue }

    public var label: String { "ManageEngine" }
}

public enum BookingStatus: String, Codable, Sendable {
    /// vorbereitet, noch nicht übertragen
    case pending
    /// Senden fehlgeschlagen, wird erneut versucht
    case failed
    /// vom Zielsystem bestätigt (z. B. Worklog angelegt)
    case confirmed
    /// bewusst ausgelassen, z. B. kein Worklog im Ticket (dort ist er freiwillig)
    case skipped

    public var label: String {
        switch self {
        case .pending: return "offen"
        case .failed: return "Fehler"
        case .confirmed: return "gebucht"
        case .skipped: return "ohne Worklog"
        }
    }

    public var isDone: Bool { self == .confirmed || self == .skipped }
}

/// Eine Buchung: Zeit einer Aufgabe an einem Tag für ein Zielsystem.
public struct Booking: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var day: LocalDate
    public var target: BookingTarget
    public var minutes: Int
    public var description: String
    /// interne Ticket-ID in ManageEngine
    public var ticketKey: String?
    public var status: BookingStatus
    /// z. B. die Worklog-ID
    public var reference: String?
    public var lastError: String?
    public var attempts: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        day: LocalDate,
        target: BookingTarget,
        minutes: Int,
        description: String,
        ticketKey: String? = nil,
        status: BookingStatus = .pending,
        reference: String? = nil,
        lastError: String? = nil,
        attempts: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.taskID = taskID
        self.day = day
        self.target = target
        self.minutes = minutes
        self.description = description
        self.ticketKey = ticketKey
        self.status = status
        self.reference = reference
        self.lastError = lastError
        self.attempts = attempts
        self.updatedAt = updatedAt
    }
}

/// Was vor dem Worklog noch fehlt.
public enum BookingIssue: String, Hashable, Sendable, CaseIterable {
    case missingDescription
    case missingTicketKey

    public var message: String {
        switch self {
        case .missingDescription: return "Beschreibung der Bearbeitung fehlt"
        case .missingTicketKey: return "Ticket in ManageEngine nicht gefunden (Nummer prüfen oder neu zuordnen)"
        }
    }

    public var target: BookingTarget { .manageEngine }
}

public struct BookingRules: Equatable, Sendable {
    public var roundingStep: Int
    public var roundingMode: RoundingMode

    public init(roundingStep: Int = 15, roundingMode: RoundingMode = .nearest) {
        self.roundingStep = roundingStep
        self.roundingMode = roundingMode
    }
}

/// Eine Zeile im Tagesabschluss: eine Aufgabe, ihre Zeit an diesem Tag und ob ein Worklog ins Ticket geht.
public struct BookingLine: Identifiable, Equatable, Sendable {
    public var id: UUID { task.id }
    public var task: TaskItem
    public var day: LocalDate
    public var trackedSeconds: TimeInterval
    public var minutes: Int
    public var targets: [BookingTarget]
    public var issues: [BookingIssue]
    public var bookings: [BookingTarget: Booking]
    /// Titel der übergeordneten Aufgabe, wenn dies eine Unteraufgabe ist.
    public var parentTitle: String? = nil

    public func issues(for target: BookingTarget) -> [BookingIssue] {
        issues.filter { $0.target == target }
    }

    public func status(for target: BookingTarget) -> BookingStatus? {
        bookings[target]?.status
    }

    /// Alle Ziele erledigt? (Ohne Ticket gibt es nichts zu senden.)
    public var isDone: Bool {
        targets.allSatisfy { bookings[$0]?.status.isDone ?? false }
    }

    /// Nach dem Buchen wurde die Zeit noch geändert.
    public var changedAfterBooking: Bool {
        bookings.values.contains { $0.status == .confirmed && $0.minutes != minutes }
    }

    /// Hinweise, die noch offen sind: Ziele, die erledigt oder ausgelassen sind, zählen nicht mehr.
    public var openIssues: [BookingIssue] {
        issues.filter { !(bookings[$0.target]?.status.isDone ?? false) }
    }

    /// Titel für Worklog und Liste; bei Unteraufgaben mit der übergeordneten Aufgabe davor.
    public var displayTitle: String {
        guard let parentTitle, !parentTitle.isEmpty else { return task.title }
        return "\(parentTitle): \(task.title)"
    }

    /// Text für den Worklog in ManageEngine.
    public var worklogDescription: String {
        task.workDescription.isEmpty ? displayTitle : task.workDescription
    }
}

/// Tagesabschluss: aus erfasster Zeit werden Buchungen.
public enum DailyClose {
    public static func lines(
        for day: LocalDate,
        tasks: [TaskItem],
        entries: [TimeEntry],
        bookings: [Booking],
        rules: BookingRules,
        now: Date,
        calendar: Calendar = .current
    ) -> [BookingLine] {
        let interval = day.interval(calendar: calendar)
        let dayEntries = entries.filter { TimeMath.overlap(of: $0, with: interval, now: now) > 0 }
        let firstStart = Dictionary(grouping: dayEntries.compactMap { entry in entry.taskID.map { ($0, entry.start) } }, by: \.0)
            .mapValues { $0.map(\.1).min() ?? .distantFuture }
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return tasks
            .compactMap { stored -> BookingLine? in
                let seconds = TimeMath.tracked(taskID: stored.id, on: day, entries: dayEntries, now: now, calendar: calendar)
                guard seconds > 0 else { return nil }
                let parent = stored.parentID.flatMap { byID[$0] }
                let task = stored.resolved(parent: parent)
                let targets: [BookingTarget] = task.hasTicket ? [.manageEngine] : []
                var issues: [BookingIssue] = []
                if targets.contains(.manageEngine) {
                    if task.workDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        issues.append(.missingDescription)
                    }
                    if task.linkedTicketKey == nil { issues.append(.missingTicketKey) }
                }
                var byTarget: [BookingTarget: Booking] = [:]
                for booking in bookings where booking.taskID == task.id && booking.day == day {
                    byTarget[booking.target] = booking
                }
                return BookingLine(
                    task: task,
                    day: day,
                    trackedSeconds: seconds,
                    minutes: TimeMath.rounded(seconds, toMinutes: rules.roundingStep, mode: rules.roundingMode),
                    targets: targets,
                    issues: issues,
                    bookings: byTarget,
                    parentTitle: parent?.title
                )
            }
            .sorted { (firstStart[$0.task.id] ?? .distantFuture) < (firstStart[$1.task.id] ?? .distantFuture) }
    }

    /// Bereitet für jedes noch offene Ziel einer Zeile eine Buchung vor (oder aktualisiert sie).
    /// Erledigte Buchungen bleiben unangetastet, Ziele mit fehlenden Angaben werden übersprungen.
    public static func prepare(_ line: BookingLine, minutes: Int? = nil, now: Date) -> [Booking] {
        let effectiveMinutes = minutes ?? line.minutes
        return line.targets.compactMap { target in
            guard line.issues(for: target).isEmpty else { return nil }
            if let existing = line.bookings[target], existing.status.isDone { return nil }
            var booking = line.bookings[target] ?? Booking(
                taskID: line.task.id,
                day: line.day,
                target: target,
                minutes: effectiveMinutes,
                description: ""
            )
            booking.minutes = effectiveMinutes
            booking.description = line.worklogDescription
            booking.ticketKey = line.task.linkedTicketKey
            if booking.status != .failed {
                booking.status = .pending
            }
            booking.updatedAt = now
            return booking
        }
    }
}

/// Warteschlange: was als Nächstes gesendet wird und wann ein Fehlversuch wiederholt wird.
public enum BookingQueue {
    /// Ziel bewusst auslassen (z. B. kein Worklog im Ticket).
    public static func skipped(_ line: BookingLine, target: BookingTarget, minutes: Int, now: Date) -> Booking {
        var booking = line.bookings[target] ?? Booking(
            taskID: line.task.id,
            day: line.day,
            target: target,
            minutes: minutes,
            description: line.worklogDescription,
            ticketKey: line.task.linkedTicketKey
        )
        booking.status = .skipped
        booking.minutes = minutes
        booking.lastError = nil
        booking.updatedAt = now
        return booking
    }

    /// 30 s, 1 min, 2 min, … höchstens 1 Stunde
    public static func retryDelay(attempts: Int) -> TimeInterval {
        guard attempts > 0 else { return 0 }
        return min(3600, 30 * pow(2, Double(attempts - 1)))
    }

    public static func due(_ bookings: [Booking], target: BookingTarget, now: Date) -> [Booking] {
        bookings.filter { booking in
            guard booking.target == target else { return false }
            switch booking.status {
            case .pending:
                return true
            case .failed:
                return now >= booking.updatedAt.addingTimeInterval(retryDelay(attempts: booking.attempts))
            case .confirmed, .skipped:
                return false
            }
        }
    }

    public static func confirmed(_ booking: Booking, reference: String?, now: Date) -> Booking {
        var copy = booking
        copy.status = .confirmed
        copy.reference = reference
        copy.lastError = nil
        copy.updatedAt = now
        return copy
    }

    public static func failed(_ booking: Booking, error: String, now: Date) -> Booking {
        var copy = booking
        copy.status = .failed
        copy.lastError = error
        copy.attempts += 1
        copy.updatedAt = now
        return copy
    }
}

/// Liste des Tages zum Kopieren, z. B. um Zeiten in ein anderes System abzutippen.
/// Tabulator-getrennt, damit sie in Excel oder Numbers gleich in Spalten landet.
public enum DayList {
    /// Stunden mit Komma, z. B. "1,25".
    public static func hours(_ minutes: Int) -> String {
        let value = Double(minutes) / 60
        let text = String(format: "%.2f", value)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    /// Datum, Aufgabe, Kunde, Ticket, Stunden, Beschreibung; `minutes` ersetzt die gerundete Zeit einer Zeile.
    public static func text(
        _ lines: [BookingLine],
        minutes: [UUID: Int] = [:],
        customerName: (UUID?) -> String?
    ) -> String {
        var rows = [["Datum", "Aufgabe", "Kunde", "Ticket", "Stunden", "Beschreibung"]]
        for line in lines {
            let date = String(format: "%02d.%02d.%04d", line.day.day, line.day.month, line.day.year)
            rows.append([
                date,
                line.displayTitle,
                customerName(line.task.customerID) ?? "",
                line.task.linkedTicketNumber.map { "#\($0)" } ?? "",
                hours(minutes[line.id] ?? line.minutes),
                line.task.workDescription,
            ])
        }
        return rows
            .map { $0.map(clean).joined(separator: "\t") }
            .joined(separator: "\n") + "\n"
    }

    /// Tabulatoren und Zeilenumbrüche würden die Spalten verschieben.
    private static func clean(_ field: String) -> String {
        field
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
