import Foundation

/// Woher eine Aufgabe stammt.
public enum TaskSource: String, CaseIterable, Codable, Sendable {
    case local
    case ticket
    case mail
    case calendar

    public var label: String {
        switch self {
        case .local: return "Eigenes Todo"
        case .ticket: return "Ticket"
        case .mail: return "Mail"
        case .calendar: return "Termin"
        }
    }

    public var systemImage: String {
        switch self {
        case .local: return "checklist"
        case .ticket: return "ticket"
        case .mail: return "envelope"
        case .calendar: return "calendar"
        }
    }
}

public enum TaskStatus: String, Codable, Sendable {
    case open
    case done
}

public struct Customer: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    /// Index in die feste Farbpalette der Oberfläche.
    public var colorIndex: Int
    public var isArchived: Bool
    public var createdAt: Date
    /// Name des Kontos in ManageEngine, über das Tickets diesem Kunden zugeordnet werden.
    public var manageEngineAccount: String?
    /// Ordner des Kunden für Claude Code (CLAUDE.md, Meeting-Transkripte)
    public var folderPath: String?

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        manageEngineAccount: String? = nil,
        folderPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.manageEngineAccount = manageEngineAccount
        self.folderPath = folderPath
    }
}

public struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var customerID: UUID?
    public var source: TaskSource
    /// z. B. die Ticketnummer aus ManageEngine
    public var externalID: String?
    public var externalURL: String?
    /// Tag, für den die Aufgabe geplant ist. `nil` = noch nicht eingeplant (Eingang).
    public var plannedDate: LocalDate?
    /// Geschätzte Dauer in Minuten.
    public var estimateMinutes: Int?
    /// Beschreibung der Bearbeitung. Wird zum Worklog-Text im Ticket.
    public var workDescription: String
    public var status: TaskStatus
    public var completedAt: Date?
    /// Reihenfolge innerhalb eines Tages.
    public var sortIndex: Double
    public var createdAt: Date
    /// Beginn des Zeitblocks im Kalender. Dauer = Schätzung (sonst 30 Minuten).
    public var scheduledStart: Date?
    /// Termin im Kalender „Tagwerk“, falls Zeitblöcke dorthin geschrieben werden.
    public var calendarEventID: String?
    /// Interne ID im Quellsystem (bei ManageEngine die Request-ID für den Worklog).
    public var externalKey: String?
    /// Wochenziel, auf das die Aufgabe einzahlt.
    public var goalID: UUID?
    /// Work Log Type in ManageEngine, genau wie dort benannt (z. B. „Ticketbearbeitung“). `nil` = Standard.
    public var worklogType: String?
    /// Übergeordnete Aufgabe, wenn dies eine Unteraufgabe ist.
    public var parentID: UUID?
    /// Zugeordnetes Ticket (Nummer, die Menschen sehen), wenn die Aufgabe selbst kein Ticket ist.
    public var ticketNumber: String?
    /// Interne Request-ID des zugeordneten Tickets in ManageEngine (für den Worklog).
    public var ticketKey: String?
    /// Betreff des zugeordneten Tickets, zur Anzeige
    public var ticketTitle: String?
    /// Langes Ziel, auf das die Aufgabe einzahlt (z. B. „AZ-305 bestehen“).
    public var longGoalID: UUID?
    /// Standardaufgabe wie „Organisatorisches“: immer da, wird nie erledigt, steht nicht im Eingang.
    public var isStanding: Bool
    /// Unteraufgabe mit eigenem Tag: ihre Position in der Liste dieses Tages
    /// (`sortIndex` bleibt die Reihenfolge unter ihrer Aufgabe).
    public var daySortIndex: Double?
    /// Meeting, aus dem die Aufgabe entstanden ist
    public var meetingID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        customerID: UUID? = nil,
        source: TaskSource = .local,
        externalID: String? = nil,
        externalURL: String? = nil,
        plannedDate: LocalDate? = nil,
        estimateMinutes: Int? = nil,
        workDescription: String = "",
        status: TaskStatus = .open,
        completedAt: Date? = nil,
        sortIndex: Double = 0,
        createdAt: Date = Date(),
        scheduledStart: Date? = nil,
        calendarEventID: String? = nil,
        externalKey: String? = nil,
        goalID: UUID? = nil,
        worklogType: String? = nil,
        parentID: UUID? = nil,
        ticketNumber: String? = nil,
        ticketKey: String? = nil,
        longGoalID: UUID? = nil,
        ticketTitle: String? = nil,
        isStanding: Bool = false,
        daySortIndex: Double? = nil,
        meetingID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.customerID = customerID
        self.source = source
        self.externalID = externalID
        self.externalURL = externalURL
        self.plannedDate = plannedDate
        self.estimateMinutes = estimateMinutes
        self.workDescription = workDescription
        self.status = status
        self.completedAt = completedAt
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.scheduledStart = scheduledStart
        self.calendarEventID = calendarEventID
        self.externalKey = externalKey
        self.goalID = goalID
        self.worklogType = worklogType
        self.parentID = parentID
        self.ticketNumber = ticketNumber
        self.ticketKey = ticketKey
        self.longGoalID = longGoalID
        self.ticketTitle = ticketTitle
        self.isStanding = isStanding
        self.daySortIndex = daySortIndex
        self.meetingID = meetingID
    }

    public var isDone: Bool { status == .done }

    public var isSubtask: Bool { parentID != nil }

    /// Position in einer Tagesliste: bei Unteraufgaben die eigene, sonst `sortIndex`.
    public var dayOrder: Double { isSubtask ? (daySortIndex ?? sortIndex) : sortIndex }

    /// Ticketnummer: beim Ticket selbst die eigene, sonst die zugeordnete.
    public var linkedTicketNumber: String? {
        source == .ticket ? (externalID ?? ticketNumber) : ticketNumber
    }

    /// Request-ID in ManageEngine: beim Ticket selbst die eigene, sonst die des zugeordneten Tickets.
    public var linkedTicketKey: String? {
        source == .ticket ? (externalKey ?? ticketKey) : ticketKey
    }

    /// Geht die Zeit auch als Worklog an ein Ticket?
    public var hasTicket: Bool { linkedTicketNumber != nil || linkedTicketKey != nil }

    /// Unteraufgaben erben von der übergeordneten Aufgabe, was sie nicht selbst festlegen:
    /// Kunde, Ticket, Work Log Type und Ziel.
    public func resolved(parent: TaskItem?) -> TaskItem {
        guard let parent, parentID == parent.id else { return self }
        var copy = self
        if copy.customerID == nil { copy.customerID = parent.customerID }
        if !copy.hasTicket, parent.hasTicket {
            copy.ticketNumber = parent.linkedTicketNumber
            copy.ticketKey = parent.linkedTicketKey
            copy.ticketTitle = parent.source == .ticket ? parent.title : parent.ticketTitle
        }
        if copy.worklogType == nil { copy.worklogType = parent.worklogType }
        if copy.longGoalID == nil { copy.longGoalID = parent.longGoalID }
        return copy
    }

    /// Länge des Zeitblocks im Kalender.
    public var blockMinutes: Int { max(15, estimateMinutes ?? 30) }

    public var scheduledInterval: DateInterval? {
        scheduledStart.map { DateInterval(start: $0, duration: TimeInterval(blockMinutes * 60)) }
    }
}

public struct TimeEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var taskID: UUID?
    public var start: Date
    /// `nil` = der Timer läuft noch.
    public var end: Date?
    public var note: String

    public init(id: UUID = UUID(), taskID: UUID?, start: Date, end: Date? = nil, note: String = "") {
        self.id = id
        self.taskID = taskID
        self.start = start
        self.end = end
        self.note = note
    }

    public var isRunning: Bool { end == nil }

    public func duration(now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}
