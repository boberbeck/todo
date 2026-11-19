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

    public init(
        id: UUID = UUID(),
        customerID: UUID,
        code: String,
        title: String = "",
        isActive: Bool = true,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.customerID = customerID
        self.code = code
        self.title = title
        self.isActive = isActive
        self.lastUsedAt = lastUsedAt
    }

    public var label: String {
        title.isEmpty ? code : "\(code) · \(title)"
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
        externalKey: String? = nil
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
    }

    public var isDone: Bool { status == .done }

    /// Länge des Zeitblocks im Kalender.
    public var blockMinutes: Int { max(15, estimateMinutes ?? 30) }

    public var scheduledInterval: DateInterval? {
        scheduledStart.map { DateInterval(start: $0, duration: TimeInterval(blockMinutes * 60)) }
    }

    /// Wohin die Zeit dieser Aufgabe beim Tagesabschluss gebucht wird.
    public var bookingTargets: String {
        source == .ticket ? "SAP + ManageEngine" : "nur SAP"
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
