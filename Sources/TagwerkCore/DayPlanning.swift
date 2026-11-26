import Foundation

/// Regeln für den Tagesplan.
public enum DayPlan {
    /// Aufgaben eines Tages in der geplanten Reihenfolge. Erledigte bleiben in der Liste stehen.
    /// Dazu gehören Unteraufgaben, die eigens an diesem Tag eingeplant sind; liegt ihre Aufgabe am selben Tag,
    /// stehen sie stattdessen dort darunter.
    public static func tasks(for day: LocalDate, in tasks: [TaskItem]) -> [TaskItem] {
        let parentDay = parentDays(in: tasks)
        return tasks
            .filter { task in
                guard task.plannedDate == day else { return false }
                guard let parentID = task.parentID else { return true }
                return parentDay[parentID] != day
            }
            .sorted { lhs, rhs in
                if lhs.dayOrder != rhs.dayOrder { return lhs.dayOrder < rhs.dayOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    /// Unteraufgabe mit eigenem Tag, der nicht der ihrer Aufgabe ist: steht dort als eigene Karte.
    public static func isPlannedOnItsOwn(_ task: TaskItem, in tasks: [TaskItem]) -> Bool {
        guard let parentID = task.parentID, let day = task.plannedDate else { return false }
        return tasks.first { $0.id == parentID }?.plannedDate != day
    }

    /// Tag jeder eingeplanten Aufgabe (ohne Unteraufgaben), nach ID.
    static func parentDays(in tasks: [TaskItem]) -> [UUID: LocalDate] {
        Dictionary(
            tasks.compactMap { task -> (UUID, LocalDate)? in
                guard !task.isSubtask, let day = task.plannedDate else { return nil }
                return (task.id, day)
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Nächste freie Position am Ende einer Tagesliste.
    public static func nextDayIndex(in dayTasks: [TaskItem]) -> Double {
        (dayTasks.map(\.dayOrder).max() ?? 0) + 1
    }

    /// Offene Aufgaben ohne Tag, neueste zuerst. Standardaufgaben gehören nicht dazu.
    public static func inbox(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { $0.plannedDate == nil && !$0.isDone && $0.parentID == nil && !$0.isStanding }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Standardaufgaben (z. B. „Organisatorisches“) in ihrer Reihenfolge.
    public static func standing(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { $0.isStanding && $0.parentID == nil }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.createdAt < rhs.createdAt
            }
    }

    /// Vorschläge beim ersten Start: Zeit, die zu keinem Kunden-Auftrag gehört.
    public static let defaultStandingTitles = ["Organisatorisches", "Interne Besprechung", "Weiterbildung"]

    /// Summe der Schätzungen in Minuten.
    public static func plannedMinutes(_ tasks: [TaskItem]) -> Int {
        tasks.reduce(0) { $0 + max(0, $1.estimateMinutes ?? 0) }
    }

    /// Mehr geplant, als Zeit da ist?
    public static func isOverplanned(plannedMinutes: Int, availableMinutes: Int) -> Bool {
        plannedMinutes > availableMinutes
    }

    /// Offene Aufgaben von früheren Tagen wandern auf heute. Gibt nur die geänderten Aufgaben zurück.
    /// Eigens eingeplante Unteraufgaben wandern mit; liegt ihre Aufgabe dann auch auf heute,
    /// stehen sie wieder einfach darunter.
    public static func rollOver(_ tasks: [TaskItem], to today: LocalDate) -> [TaskItem] {
        var nextIndex = nextDayIndex(in: self.tasks(for: today, in: tasks))
        var changed: [TaskItem] = []
        func isStale(_ task: TaskItem) -> Bool {
            !task.isDone && !task.isStanding && (task.plannedDate.map { $0 < today } ?? false)
        }
        let stale = tasks
            .filter { !$0.isSubtask && isStale($0) }
            .sorted { ($0.plannedDate!, $0.sortIndex) < ($1.plannedDate!, $1.sortIndex) }
        for var task in stale {
            task.plannedDate = today
            task.sortIndex = nextIndex
            nextIndex += 1
            changed.append(task)
        }
        let rolled = Set(stale.map(\.id))
        let parentDay = parentDays(in: tasks)
        let staleSubtasks = tasks
            .filter { $0.isSubtask && isStale($0) }
            .sorted { ($0.plannedDate!, $0.dayOrder) < ($1.plannedDate!, $1.dayOrder) }
        for var subtask in staleSubtasks {
            guard let parentID = subtask.parentID else { continue }
            let parentToday = rolled.contains(parentID) || parentDay[parentID] == today
            if parentToday {
                subtask.plannedDate = nil
                subtask.daySortIndex = nil
            } else {
                subtask.plannedDate = today
                subtask.daySortIndex = nextIndex
                nextIndex += 1
            }
            changed.append(subtask)
        }
        return changed
    }

    /// Die nächste offene Aufgabe nach `currentID` in der Tagesreihenfolge, sonst die erste offene.
    public static func nextOpenTask(after currentID: UUID?, in dayTasks: [TaskItem]) -> TaskItem? {
        let open = dayTasks.filter { !$0.isDone && $0.id != currentID }
        guard let currentID, let position = dayTasks.firstIndex(where: { $0.id == currentID }) else {
            return open.first
        }
        let later = dayTasks[(position + 1)...].first { !$0.isDone }
        return later ?? open.first
    }

    /// Unteraufgaben einer Aufgabe in ihrer Reihenfolge.
    public static func subtasks(of parentID: UUID, in tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.createdAt < rhs.createdAt
            }
    }

    public static func nextSortIndex(in tasks: [TaskItem]) -> Double {
        (tasks.map(\.sortIndex).max() ?? 0) + 1
    }

    /// Neue Reihenfolge nach Verschieben in einer Liste (wie `onMove` in SwiftUI).
    /// Gibt die Aufgaben mit neu durchnummeriertem `sortIndex` zurück.
    public static func reorder(_ dayTasks: [TaskItem], from source: IndexSet, to destination: Int) -> [TaskItem] {
        var items = dayTasks
        let moving = source.sorted().map { items[$0] }
        for index in source.sorted(by: >) {
            items.remove(at: index)
        }
        let removedBefore = source.filter { $0 < destination }.count
        let insertAt = min(max(0, destination - removedBefore), items.count)
        items.insert(contentsOf: moving, at: insertAt)
        for index in items.indices {
            // Unteraufgaben behalten ihre Reihenfolge unter der Aufgabe und bekommen eine eigene am Tag
            if items[index].isSubtask {
                items[index].daySortIndex = Double(index + 1)
            } else {
                items[index].sortIndex = Double(index + 1)
            }
        }
        return items
    }
}
