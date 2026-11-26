import XCTest
@testable import TagwerkCore

/// Unteraufgaben mit eigenem Tag: stehen dort als eigene Karte, ohne die Reihenfolge unter der Aufgabe zu ändern.
final class SubtaskPlanningTests: XCTestCase {
    private let monday = LocalDate(year: 2026, month: 11, day: 23)
    private let tuesday = LocalDate(year: 2026, month: 11, day: 24)

    func testSubtaskWithOwnDayAppearsThere() {
        let parent = TaskItem(title: "Sicherheitslücke PHP", plannedDate: monday, sortIndex: 1)
        let followsParent = TaskItem(title: "VMQPDEV01 updaten", sortIndex: 1, parentID: parent.id)
        let sameDay = TaskItem(title: "VMQPTES01 updaten", plannedDate: monday, sortIndex: 2, parentID: parent.id)
        let ownDay = TaskItem(title: "VMQPPRO01 updaten", plannedDate: tuesday, sortIndex: 3, parentID: parent.id, daySortIndex: 0.5)
        let other = TaskItem(title: "Angebot", plannedDate: tuesday, sortIndex: 1)
        let tasks = [parent, followsParent, sameDay, ownDay, other]

        XCTAssertEqual(DayPlan.tasks(for: monday, in: tasks).map(\.id), [parent.id], "am Tag der Aufgabe stehen Unteraufgaben darunter")
        XCTAssertEqual(DayPlan.tasks(for: tuesday, in: tasks).map(\.id), [ownDay.id, other.id], "eigene Position am Tag")
        XCTAssertTrue(DayPlan.isPlannedOnItsOwn(ownDay, in: tasks))
        XCTAssertFalse(DayPlan.isPlannedOnItsOwn(sameDay, in: tasks))
        XCTAssertFalse(DayPlan.isPlannedOnItsOwn(followsParent, in: tasks))
        XCTAssertTrue(DayPlan.inbox(tasks).isEmpty, "Unteraufgaben nie im Eingang")
        // Reihenfolge unter der Aufgabe bleibt
        XCTAssertEqual(DayPlan.subtasks(of: parent.id, in: tasks).map(\.id), [followsParent.id, sameDay.id, ownDay.id])

        // Liegt die Aufgabe im Eingang, steht die eingeplante Unteraufgabe trotzdem an ihrem Tag
        var unplanned = parent
        unplanned.plannedDate = nil
        XCTAssertEqual(DayPlan.tasks(for: monday, in: [unplanned, sameDay]).map(\.id), [sameDay.id])
    }

    func testReorderKeepsSubtaskOrderUnderParent() {
        let parent = TaskItem(title: "Aufgabe", sortIndex: 1)
        let subtask = TaskItem(title: "Schritt", plannedDate: tuesday, sortIndex: 4, parentID: parent.id)
        let first = TaskItem(title: "Erste", plannedDate: tuesday, sortIndex: 1)
        let day = DayPlan.tasks(for: tuesday, in: [parent, subtask, first])
        XCTAssertEqual(day.map(\.id), [first.id, subtask.id])
        let reordered = DayPlan.reorder(day, from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(reordered.map(\.id), [subtask.id, first.id])
        XCTAssertEqual(reordered[0].sortIndex, 4, "Reihenfolge unter der Aufgabe bleibt")
        XCTAssertEqual(reordered[0].daySortIndex, 1)
        XCTAssertEqual(reordered[1].sortIndex, 2)
        XCTAssertEqual(DayPlan.nextDayIndex(in: reordered), 3)
    }

    func testRollOverTakesPlannedSubtasksAlong() {
        let wednesday = LocalDate(year: 2026, month: 11, day: 25)
        let staleParent = TaskItem(title: "Alt", plannedDate: monday, sortIndex: 1)
        let withParent = TaskItem(title: "Mit Aufgabe", plannedDate: tuesday, sortIndex: 1, parentID: staleParent.id)
        let futureParent = TaskItem(title: "Später", plannedDate: LocalDate(year: 2026, month: 11, day: 30), sortIndex: 1)
        let alone = TaskItem(title: "Allein", plannedDate: tuesday, sortIndex: 2, parentID: futureParent.id, daySortIndex: 9)
        let done = TaskItem(title: "Fertig", plannedDate: tuesday, status: .done, sortIndex: 3, parentID: futureParent.id)
        let todayTask = TaskItem(title: "Heute", plannedDate: wednesday, sortIndex: 4)
        let changed = DayPlan.rollOver([staleParent, withParent, futureParent, alone, done, todayTask], to: wednesday)

        XCTAssertEqual(Set(changed.map(\.id)), [staleParent.id, withParent.id, alone.id])
        let parent = changed.first { $0.id == staleParent.id }
        XCTAssertEqual(parent?.plannedDate, wednesday)
        XCTAssertEqual(parent?.sortIndex, 5)
        let follows = changed.first { $0.id == withParent.id }
        XCTAssertNil(follows?.plannedDate, "Aufgabe wandert auch auf heute: wieder einfach darunter")
        XCTAssertEqual(follows?.sortIndex, 1)
        let own = changed.first { $0.id == alone.id }
        XCTAssertEqual(own?.plannedDate, wednesday)
        XCTAssertEqual(own?.daySortIndex, 6)
        XCTAssertEqual(own?.sortIndex, 2, "Reihenfolge unter der Aufgabe bleibt")
    }

    func testDaySortIndexStoredInSQLite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("subtask-day-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteStore(url: url)
        let parent = TaskItem(title: "Aufgabe", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        let subtask = TaskItem(title: "Schritt", plannedDate: tuesday, sortIndex: 2, createdAt: Date(timeIntervalSince1970: 1_800_000_100),
                               parentID: parent.id, daySortIndex: 3.5)
        try store.save(parent)
        try store.save(subtask)
        let loaded = try store.load().tasks.first { $0.id == subtask.id }
        XCTAssertEqual(loaded?.daySortIndex, 3.5)
        XCTAssertNil(try store.load().tasks.first { $0.id == parent.id }?.daySortIndex)
    }
}
