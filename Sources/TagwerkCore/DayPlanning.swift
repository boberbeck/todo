import Foundation

/// Regeln für den Tagesplan.
public enum DayPlan {
    /// Aufgaben eines Tages in der geplanten Reihenfolge. Erledigte bleiben in der Liste stehen.
    public static func tasks(for day: LocalDate, in tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { $0.plannedDate == day && $0.parentID == nil }
            .sorted { lhs, rhs in
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.createdAt < rhs.createdAt
            }
    }

    /// Offene Aufgaben ohne Tag, neueste zuerst.
    public static func inbox(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks
            .filter { $0.plannedDate == nil && !$0.isDone && $0.parentID == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Summe der Schätzungen in Minuten.
    public static func plannedMinutes(_ tasks: [TaskItem]) -> Int {
        tasks.reduce(0) { $0 + max(0, $1.estimateMinutes ?? 0) }
    }

    /// Mehr geplant, als Zeit da ist?
    public static func isOverplanned(plannedMinutes: Int, availableMinutes: Int) -> Bool {
        plannedMinutes > availableMinutes
    }

    /// Offene Aufgaben von früheren Tagen wandern auf heute. Gibt nur die geänderten Aufgaben zurück.
    public static func rollOver(_ tasks: [TaskItem], to today: LocalDate) -> [TaskItem] {
        var nextIndex = nextSortIndex(in: tasks.filter { $0.plannedDate == today })
        var changed: [TaskItem] = []
        let stale = tasks
            .filter { !$0.isDone && $0.parentID == nil && ($0.plannedDate.map { $0 < today } ?? false) }
            .sorted { ($0.plannedDate!, $0.sortIndex) < ($1.plannedDate!, $1.sortIndex) }
        for var task in stale {
            task.plannedDate = today
            task.sortIndex = nextIndex
            nextIndex += 1
            changed.append(task)
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
            items[index].sortIndex = Double(index + 1)
        }
        return items
    }
}
