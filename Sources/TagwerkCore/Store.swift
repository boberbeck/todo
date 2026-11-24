import Foundation

/// Alles, was die App beim Start lädt.
public struct Snapshot: Sendable, Equatable {
    public var customers: [Customer]
    public var tasks: [TaskItem]
    public var entries: [TimeEntry]
    public var pspElements: [PSPElement]
    public var bookings: [Booking]
    public var goals: [WeeklyGoal]
    public var longGoals: [LongGoal]
    /// Krank- und Urlaubstage
    public var absences: [Absence]
    /// Pausen
    public var breaks: [WorkBreak]

    public init(
        customers: [Customer] = [],
        tasks: [TaskItem] = [],
        entries: [TimeEntry] = [],
        pspElements: [PSPElement] = [],
        bookings: [Booking] = [],
        goals: [WeeklyGoal] = [],
        longGoals: [LongGoal] = [],
        absences: [Absence] = [],
        breaks: [WorkBreak] = []
    ) {
        self.customers = customers
        self.tasks = tasks
        self.entries = entries
        self.pspElements = pspElements
        self.bookings = bookings
        self.goals = goals
        self.longGoals = longGoals
        self.absences = absences
        self.breaks = breaks
    }
}

/// Speicherort der Daten. Die App nutzt `SQLiteStore`, Tests und Vorschauen `InMemoryStore`.
public protocol Store: AnyObject {
    func load() throws -> Snapshot
    func save(_ customer: Customer) throws
    func save(_ task: TaskItem) throws
    func save(_ entry: TimeEntry) throws
    func save(_ psp: PSPElement) throws
    func save(_ booking: Booking) throws
    func save(_ goal: WeeklyGoal) throws
    func deleteGoal(id: UUID) throws
    func save(_ goal: LongGoal) throws
    /// Löscht das Ziel; Aufgaben verlieren nur die Verknüpfung.
    func deleteLongGoal(id: UUID) throws
    func save(_ absence: Absence) throws
    func deleteAbsence(id: UUID) throws
    func save(_ workBreak: WorkBreak) throws
    func deleteBreak(id: UUID) throws
    /// Legt eine Sicherungskopie der Daten an.
    func backup(to url: URL) throws
    /// Löscht die Aufgabe, ihre Zeiteinträge und Buchungen.
    func deleteTask(id: UUID) throws
    func deleteEntry(id: UUID) throws
    func deletePSP(id: UUID) throws
    /// Ändert sich, wenn ein anderes Programm (z. B. der MCP-Server) Daten geschrieben hat.
    /// `nil`, wenn der Speicher das nicht erkennen kann.
    func changeToken() -> Int?
}

public extension Store {
    func changeToken() -> Int? { nil }
}

public final class InMemoryStore: Store {
    private var snapshot: Snapshot

    public init(_ snapshot: Snapshot = Snapshot()) {
        self.snapshot = snapshot
    }

    public func load() throws -> Snapshot { snapshot }

    public func save(_ customer: Customer) throws {
        upsert(customer, into: &snapshot.customers)
    }

    public func save(_ task: TaskItem) throws {
        upsert(task, into: &snapshot.tasks)
    }

    public func save(_ entry: TimeEntry) throws {
        upsert(entry, into: &snapshot.entries)
    }

    public func save(_ psp: PSPElement) throws {
        upsert(psp, into: &snapshot.pspElements)
    }

    public func save(_ booking: Booking) throws {
        upsert(booking, into: &snapshot.bookings)
    }

    public func save(_ goal: WeeklyGoal) throws {
        upsert(goal, into: &snapshot.goals)
    }

    public func deleteGoal(id: UUID) throws {
        snapshot.goals.removeAll { $0.id == id }
        for index in snapshot.tasks.indices where snapshot.tasks[index].goalID == id {
            snapshot.tasks[index].goalID = nil
        }
    }

    public func save(_ goal: LongGoal) throws {
        upsert(goal, into: &snapshot.longGoals)
    }

    public func deleteLongGoal(id: UUID) throws {
        snapshot.longGoals.removeAll { $0.id == id }
        for index in snapshot.tasks.indices where snapshot.tasks[index].longGoalID == id {
            snapshot.tasks[index].longGoalID = nil
        }
    }

    public func save(_ absence: Absence) throws {
        upsert(absence, into: &snapshot.absences)
    }

    public func deleteAbsence(id: UUID) throws {
        snapshot.absences.removeAll { $0.id == id }
    }

    public func save(_ workBreak: WorkBreak) throws {
        upsert(workBreak, into: &snapshot.breaks)
    }

    public func deleteBreak(id: UUID) throws {
        snapshot.breaks.removeAll { $0.id == id }
    }

    public func backup(to url: URL) throws {}

    public func deleteTask(id: UUID) throws {
        snapshot.tasks.removeAll { $0.id == id }
        snapshot.entries.removeAll { $0.taskID == id }
        snapshot.bookings.removeAll { $0.taskID == id }
    }

    public func deleteEntry(id: UUID) throws {
        snapshot.entries.removeAll { $0.id == id }
    }

    public func deletePSP(id: UUID) throws {
        snapshot.pspElements.removeAll { $0.id == id }
    }

    private func upsert<T: Identifiable>(_ item: T, into list: inout [T]) {
        if let index = list.firstIndex(where: { $0.id == item.id }) {
            list[index] = item
        } else {
            list.append(item)
        }
    }
}
