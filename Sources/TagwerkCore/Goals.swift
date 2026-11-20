import Foundation

/// Ein langes Ziel über mehrere Wochen, z. B. „AZ-305 bestehen“: mit Zieldatum und Stundenziel.
/// Aufgaben (und ihre Unteraufgaben) zahlen darauf ein.
public struct LongGoal: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var customerID: UUID?
    /// Bis wann, z. B. der Prüfungstermin
    public var dueDate: LocalDate?
    /// Wie viele Minuten insgesamt hineinfließen sollen, z. B. 40 Stunden Lernen
    public var targetMinutes: Int?
    public var notes: String
    public var isDone: Bool
    public var completedAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        customerID: UUID? = nil,
        dueDate: LocalDate? = nil,
        targetMinutes: Int? = nil,
        notes: String = "",
        isDone: Bool = false,
        completedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.customerID = customerID
        self.dueDate = dueDate
        self.targetMinutes = targetMinutes
        self.notes = notes
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}

/// Stand eines Ziels: erfasste Zeit, Aufgaben, verbleibende Zeit und nötiges Tempo.
public struct GoalProgress: Equatable, Sendable {
    public var trackedSeconds: TimeInterval
    public var trackedThisWeek: TimeInterval
    public var openTasks: Int
    public var doneTasks: Int
    public var targetMinutes: Int?
    /// Tage bis zum Zieldatum (0 = heute, negativ = überfällig)
    public var daysLeft: Int?
    /// 0…1: Stunden gegen das Stundenziel, ohne Stundenziel erledigte gegen alle Aufgaben
    public var fraction: Double?
    /// Minuten pro Woche, die bis zum Zieldatum noch nötig sind
    public var minutesPerWeekNeeded: Int?
    /// Liegt das Ziel hinter dem Plan (Zeit vergeht schneller, als Stunden dazukommen)?
    public var isBehind: Bool

    public var trackedMinutes: Int { Int(trackedSeconds / 60) }
}

public enum Goals {
    /// Gehört die Aufgabe zum Ziel, direkt oder über ihre übergeordnete Aufgabe?
    public static func belongs(_ task: TaskItem, to goalID: UUID, tasksByID: [UUID: TaskItem]) -> Bool {
        if task.longGoalID == goalID { return true }
        guard task.longGoalID == nil, let parentID = task.parentID else { return false }
        return tasksByID[parentID]?.longGoalID == goalID
    }

    public static func tasks(of goal: LongGoal, in tasks: [TaskItem]) -> [TaskItem] {
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return tasks.filter { belongs($0, to: goal.id, tasksByID: byID) }
    }

    public static func progress(
        of goal: LongGoal,
        tasks: [TaskItem],
        entries: [TimeEntry],
        today: LocalDate,
        now: Date,
        calendar: Calendar = .current
    ) -> GoalProgress {
        let linked = Goals.tasks(of: goal, in: tasks)
        let ids = Set(linked.map(\.id))
        let goalEntries = entries.filter { entry in entry.taskID.map { ids.contains($0) } ?? false }
        let tracked = goalEntries.reduce(0) { $0 + $1.duration(now: now) }
        let week = WeeklyReview.interval(ofWeekStarting: today.startOfWeek(calendar: calendar), calendar: calendar)
        let thisWeek = goalEntries.reduce(0) { $0 + TimeMath.overlap(of: $1, with: week, now: now) }
        // Gezählt werden die Aufgaben selbst; Unteraufgaben sind Schritte darin.
        let topLevel = linked.filter { $0.parentID == nil || !ids.contains($0.parentID!) }
        let done = topLevel.filter(\.isDone).count

        let daysLeft = goal.dueDate.map { days(from: today, to: $0, calendar: calendar) }
        var fraction: Double?
        var perWeek: Int?
        var behind = false
        if let target = goal.targetMinutes, target > 0 {
            fraction = min(1, tracked / Double(target * 60))
            let remaining = max(0, target - Int(tracked / 60))
            if let daysLeft {
                let weeks = max(Double(max(daysLeft, 0) + 1) / 7, 1.0 / 7)
                perWeek = remaining == 0 ? 0 : Int((Double(remaining) / weeks).rounded(.up))
                let start = LocalDate(goal.createdAt, calendar: calendar)
                let total = max(1, days(from: start, to: goal.dueDate!, calendar: calendar))
                let elapsed = min(total, max(0, days(from: start, to: today, calendar: calendar)))
                let expected = Double(elapsed) / Double(total)
                behind = !goal.isDone && remaining > 0 && (daysLeft < 0 || (fraction ?? 0) + 0.1 < expected)
            }
        } else if !topLevel.isEmpty {
            fraction = Double(done) / Double(topLevel.count)
            if let daysLeft { behind = !goal.isDone && daysLeft < 0 && done < topLevel.count }
        }
        return GoalProgress(
            trackedSeconds: tracked,
            trackedThisWeek: thisWeek,
            openTasks: topLevel.count - done,
            doneTasks: done,
            targetMinutes: goal.targetMinutes,
            daysLeft: daysLeft,
            fraction: goal.isDone ? 1 : fraction,
            minutesPerWeekNeeded: goal.isDone ? nil : perWeek,
            isBehind: behind
        )
    }

    /// Aktive Ziele zuerst nach Zieldatum (ohne Datum zuletzt), dann erledigte.
    public static func sorted(_ goals: [LongGoal]) -> [LongGoal] {
        goals.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.createdAt < rhs.createdAt
            }
        }
    }

    static func days(from start: LocalDate, to end: LocalDate, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start.startDate(calendar: calendar), to: end.startDate(calendar: calendar)).day ?? 0
    }
}
