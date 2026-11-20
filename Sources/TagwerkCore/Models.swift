import Foundation

/// Art der Arbeit. Sie legt später in SAP die Leistung fest.
public enum WorkType: String, CaseIterable, Codable, Sendable, Identifiable {
    case wartung
    case stoerung
    case projekt
    case beratung

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .wartung: return "Wartung"
        case .stoerung: return "Störung"
        case .projekt: return "Projekt"
        case .beratung: return "Beratung"
        }
    }
}

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

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = 0,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        manageEngineAccount: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.manageEngineAccount = manageEngineAccount
    }
}

/// Ein PSP-Element (Projektaufgabe in SAP ByDesign), auf das Zeiten eines Kunden gebucht werden.
public struct PSPElement: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var customerID: UUID
    /// ID in ByDesign, z. B. die Projektaufgabe
    public var code: String
    public var title: String
    public var isActive: Bool
    public var lastUsedAt: Date?
    /// Tätigkeit aus SAP, z. B. „Beratung“ oder „Interne Besprechung“
    public var activity: String?

    public init(
        id: UUID = UUID(),
        customerID: UUID,
        code: String,
        title: String = "",
        isActive: Bool = true,
        lastUsedAt: Date? = nil,
        activity: String? = nil
    ) {
        self.id = id
        self.customerID = customerID
        self.code = code
        self.title = title
        self.isActive = isActive
        self.lastUsedAt = lastUsedAt
        self.activity = activity
    }

    /// Gleiche SAP-Aufgabe (Nummer) und gleiche Tätigkeit?
    public func matches(code: String?, activity: String?) -> Bool {
        guard let code, self.code.caseInsensitiveCompare(code) == .orderedSame else { return false }
        return PSPElement.sameActivity(self.activity, activity)
    }

    static func sameActivity(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = lhs?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let right = rhs?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return left == right
    }

    /// „CPSO8643-5 · Firewall · Beratung“
    public var label: String {
        var parts = [code]
        if !title.isEmpty { parts.append(title) }
        if let activity, !activity.isEmpty, activity != title { parts.append(activity) }
        return parts.joined(separator: " · ")
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
    public var workType: WorkType?
    /// PSP-Element in SAP ByDesign, einmal pro Aufgabe gewählt.
    public var pspElement: String?
    /// Beschreibung der Bearbeitung. Wird später zum Worklog-Text und zum SAP-Kommentar.
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
    /// Tätigkeit aus SAP (Activity), passend zum PSP-Element, z. B. „Interne Besprechung“.
    public var sapActivity: String?
    /// Langes Ziel, auf das die Aufgabe einzahlt (z. B. „AZ-305 bestehen“).
    public var longGoalID: UUID?

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
        workType: WorkType? = nil,
        pspElement: String? = nil,
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
        sapActivity: String? = nil,
        longGoalID: UUID? = nil
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
        self.workType = workType
        self.pspElement = pspElement
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
        self.sapActivity = sapActivity
        self.longGoalID = longGoalID
    }

    public var isDone: Bool { status == .done }

    public var isSubtask: Bool { parentID != nil }

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
    /// Kunde, Arbeitsart, SAP-Aufgabe mit Tätigkeit, Ticket und Work Log Type.
    public func resolved(parent: TaskItem?) -> TaskItem {
        guard let parent, parentID == parent.id else { return self }
        var copy = self
        if copy.customerID == nil { copy.customerID = parent.customerID }
        if copy.workType == nil { copy.workType = parent.workType }
        if copy.pspElement == nil {
            copy.pspElement = parent.pspElement
            copy.sapActivity = parent.sapActivity
        }
        if !copy.hasTicket, parent.hasTicket {
            copy.ticketNumber = parent.linkedTicketNumber
            copy.ticketKey = parent.linkedTicketKey
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

    /// Wohin die Zeit dieser Aufgabe beim Tagesabschluss gebucht wird.
    public var bookingTargets: String {
        hasTicket ? "SAP + ManageEngine" : "nur SAP"
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
