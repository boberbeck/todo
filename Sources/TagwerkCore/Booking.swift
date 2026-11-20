import Foundation

/// Wohin eine Zeit gebucht wird.
public enum BookingTarget: String, Codable, CaseIterable, Sendable, Identifiable {
    case sap
    case manageEngine

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sap: return "SAP"
        case .manageEngine: return "ManageEngine"
        }
    }
}

public enum BookingStatus: String, Codable, Sendable {
    /// vorbereitet, noch nicht übertragen
    case pending
    /// Senden fehlgeschlagen, wird erneut versucht
    case failed
    /// vom Zielsystem bestätigt (z. B. Worklog angelegt)
    case confirmed
    /// von Hand übertragen und abgehakt (SAP ohne Schnittstelle)
    case entered
    /// bewusst ausgelassen, z. B. kein Worklog im Ticket (dort ist er freiwillig)
    case skipped

    public var label: String {
        switch self {
        case .pending: return "offen"
        case .failed: return "Fehler"
        case .confirmed: return "gebucht"
        case .entered: return "eingetragen"
        case .skipped: return "ohne Worklog"
        }
    }

    public var isDone: Bool { self == .confirmed || self == .entered || self == .skipped }
}

/// Eine Buchung: Zeit einer Aufgabe an einem Tag für ein Zielsystem.
public struct Booking: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var taskID: UUID
    public var day: LocalDate
    public var target: BookingTarget
    public var minutes: Int
    public var description: String
    public var pspElement: String?
    public var workType: WorkType?
    /// interne Ticket-ID in ManageEngine
    public var ticketKey: String?
    public var status: BookingStatus
    /// z. B. die Worklog-ID
    public var reference: String?
    public var lastError: String?
    public var attempts: Int
    public var updatedAt: Date
    /// Tätigkeit aus SAP (Activity); ohne sie bestimmt die Arbeitsart die Leistung.
    public var activity: String?

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        day: LocalDate,
        target: BookingTarget,
        minutes: Int,
        description: String,
        pspElement: String? = nil,
        workType: WorkType? = nil,
        ticketKey: String? = nil,
        status: BookingStatus = .pending,
        reference: String? = nil,
        lastError: String? = nil,
        attempts: Int = 0,
        updatedAt: Date = Date(),
        activity: String? = nil
    ) {
        self.id = id
        self.taskID = taskID
        self.day = day
        self.target = target
        self.minutes = minutes
        self.description = description
        self.pspElement = pspElement
        self.workType = workType
        self.ticketKey = ticketKey
        self.status = status
        self.reference = reference
        self.lastError = lastError
        self.attempts = attempts
        self.updatedAt = updatedAt
        self.activity = activity
    }
}

/// Was vor dem Buchen noch fehlt.
public enum BookingIssue: String, Hashable, Sendable, CaseIterable {
    case missingPSP
    case missingWorkType
    case missingDescription
    case missingTicketKey

    public var message: String {
        switch self {
        case .missingPSP: return "PSP-Element fehlt"
        case .missingWorkType: return "Arbeitsart oder SAP-Tätigkeit fehlt (legt die Leistung fest)"
        case .missingDescription: return "Beschreibung der Bearbeitung fehlt"
        case .missingTicketKey: return "Ticket ist nicht mit ManageEngine verbunden"
        }
    }

    public var target: BookingTarget {
        switch self {
        case .missingPSP, .missingWorkType: return .sap
        case .missingDescription, .missingTicketKey: return .manageEngine
        }
    }
}

public struct BookingRules: Equatable, Sendable {
    public var roundingStep: Int
    public var roundingMode: RoundingMode

    public init(roundingStep: Int = 15, roundingMode: RoundingMode = .nearest) {
        self.roundingStep = roundingStep
        self.roundingMode = roundingMode
    }
}

/// Eine Zeile im Tagesabschluss: eine Aufgabe, ihre Zeit an diesem Tag und wohin sie geht.
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

    /// Alle Ziele erledigt?
    public var isDone: Bool {
        targets.allSatisfy { bookings[$0]?.status.isDone ?? false }
    }

    /// Nach dem Buchen wurde die Zeit noch geändert.
    public var changedAfterBooking: Bool {
        bookings.values.contains { ($0.status == .confirmed || $0.status == .entered) && $0.minutes != minutes }
    }

    /// Hinweise, die noch offen sind: Ziele, die erledigt oder ausgelassen sind, zählen nicht mehr.
    public var openIssues: [BookingIssue] {
        issues.filter { !(bookings[$0.target]?.status.isDone ?? false) }
    }

    /// Titel für Kommentar und Worklog; bei Unteraufgaben mit der übergeordneten Aufgabe davor.
    public var displayTitle: String {
        guard let parentTitle, !parentTitle.isEmpty else { return task.title }
        return "\(parentTitle): \(task.title)"
    }

    /// Text für SAP: Ticketnummer vorweg, dann die Beschreibung.
    public var sapComment: String {
        let text = task.workDescription.isEmpty ? displayTitle : task.workDescription
        if let number = task.linkedTicketNumber {
            return "#\(number) \(text)"
        }
        return text
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
                let targets: [BookingTarget] = task.hasTicket ? [.sap, .manageEngine] : [.sap]
                var issues: [BookingIssue] = []
                if task.pspElement == nil { issues.append(.missingPSP) }
                if task.workType == nil, (task.sapActivity ?? "").isEmpty { issues.append(.missingWorkType) }
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
            booking.description = target == .sap ? line.sapComment : line.worklogDescription
            booking.pspElement = line.task.pspElement
            booking.workType = line.task.workType
            booking.activity = line.task.sapActivity
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
            description: target == .manageEngine ? line.worklogDescription : line.sapComment,
            pspElement: line.task.pspElement,
            workType: line.task.workType,
            ticketKey: line.task.linkedTicketKey,
            activity: line.task.sapActivity
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
            case .confirmed, .entered, .skipped:
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

    public static func entered(_ booking: Booking, now: Date) -> Booking {
        var copy = booking
        copy.status = .entered
        copy.lastError = nil
        copy.updatedAt = now
        return copy
    }
}

/// Übertragungsliste für SAP ByDesign, solange es keine Schnittstelle gibt.
public enum SAPTransfer {
    /// Stunden mit Komma, z. B. "1,25".
    public static func hours(_ minutes: Int) -> String {
        let value = Double(minutes) / 60
        let text = String(format: "%.2f", value)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    /// Leistung für SAP: die Tätigkeit aus SAP, sonst was zur Arbeitsart eingestellt ist.
    public static func service(for booking: Booking, serviceFor: (WorkType?) -> String) -> String {
        if let activity = booking.activity?.trimmingCharacters(in: .whitespaces), !activity.isEmpty {
            return activity
        }
        return serviceFor(booking.workType)
    }

    /// Semikolon-getrennt für Excel (deutsch): Datum;PSP-Element;Leistung;Stunden;Kommentar
    public static func csv(_ bookings: [Booking], serviceFor: (WorkType?) -> String) -> String {
        var lines = ["Datum;PSP-Element;Leistung;Stunden;Kommentar"]
        for booking in bookings.sorted(by: { ($0.day, $0.pspElement ?? "") < ($1.day, $1.pspElement ?? "") }) {
            let date = String(format: "%02d.%02d.%04d", booking.day.day, booking.day.month, booking.day.year)
            let fields = [
                date,
                booking.pspElement ?? "",
                service(for: booking, serviceFor: serviceFor),
                hours(booking.minutes),
                booking.description,
            ]
            lines.append(fields.map(escape).joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        let needsQuotes = field.contains(";") || field.contains("\"") || field.contains("\n")
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
