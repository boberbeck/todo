import XCTest
@testable import TagwerkCore

final class BreakTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    private let day = LocalDate(year: 2026, month: 11, day: 24)
    private let taskA = UUID()
    private let taskB = UUID()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        day.startDate(calendar: calendar).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    func testStartStopsTimerAndRemembersTask() {
        let running = TimeEntry(taskID: taskA, start: at(9))
        let change = Breaks.start(entries: [running], breaks: [], at: at(12))
        XCTAssertEqual(change.savedEntries.count, 1)
        XCTAssertEqual(change.savedEntries.first?.end, at(12))
        XCTAssertEqual(change.savedBreaks.count, 1)
        XCTAssertTrue(change.savedBreaks[0].isRunning)
        XCTAssertEqual(change.savedBreaks[0].resumeTaskID, taskA)
        // Läuft schon eine Pause, passiert nichts
        XCTAssertTrue(Breaks.start(entries: [], breaks: change.savedBreaks, at: at(12, 5)).isEmpty)
    }

    func testEndDiscardsAccidentalBreak() {
        let current = WorkBreak(start: at(12))
        let short = Breaks.end(breaks: [current], at: at(12, 3))
        XCTAssertEqual(short.deletedBreaks.map(\.id), [current.id])
        let lunch = Breaks.end(breaks: [current], at: at(12, 30))
        XCTAssertEqual(lunch.savedBreaks.first?.end, at(12, 30))
        XCTAssertTrue(Breaks.end(breaks: [], at: at(13)).isEmpty)
    }

    func testAddingCutsWorkOutOfEntries() {
        // 9–13 durchgelaufen, Mittag 12–12:30 vergessen
        let morning = TimeEntry(taskID: taskA, start: at(9), end: at(13), note: "Notiz")
        // ganz in der Pause
        let inside = TimeEntry(taskID: taskB, start: at(12, 5), end: at(12, 20))
        let change = Breaks.add(start: at(12), end: at(12, 30), entries: [morning, inside], breaks: [], now: at(17))
        XCTAssertEqual(change.savedBreaks.count, 1)
        XCTAssertEqual(change.deletedEntries.map(\.id), [inside.id])
        XCTAssertEqual(change.savedEntries.count, 2)
        let first = change.savedEntries.first { $0.id == morning.id }
        XCTAssertEqual(first?.end, at(12))
        let second = change.savedEntries.first { $0.id != morning.id }
        XCTAssertEqual(second?.start, at(12, 30))
        XCTAssertEqual(second?.end, at(13))
        XCTAssertEqual(second?.taskID, taskA)
        XCTAssertEqual(second?.note, "Notiz")
    }

    func testAddingTrimsEdgesAndKeepsRunningTimer() {
        let before = TimeEntry(taskID: taskA, start: at(11), end: at(12, 15))
        let running = TimeEntry(taskID: taskB, start: at(12, 10))
        let change = Breaks.add(start: at(12), end: at(12, 30), entries: [before, running], breaks: [], now: at(14))
        XCTAssertEqual(change.savedEntries.first { $0.id == before.id }?.end, at(12))
        let moved = change.savedEntries.first { $0.id == running.id }
        XCTAssertEqual(moved?.start, at(12, 30))
        XCTAssertNil(moved?.end, "Der Timer läuft weiter")
    }

    func testAddingMergesOverlappingBreaksAndClampsToNow() {
        let earlier = WorkBreak(start: at(12), end: at(12, 20), note: "Mittag")
        let change = Breaks.add(start: at(12, 10), end: at(12, 45), entries: [], breaks: [earlier], now: at(12, 40))
        XCTAssertEqual(change.deletedBreaks.map(\.id), [earlier.id])
        XCTAssertEqual(change.savedBreaks.first?.start, at(12))
        XCTAssertEqual(change.savedBreaks.first?.end, at(12, 40))
        XCTAssertEqual(change.savedBreaks.first?.note, "Mittag")
        // zu kurz oder ganz in der Zukunft: nichts
        XCTAssertTrue(Breaks.add(start: at(13), end: at(14), entries: [], breaks: [], now: at(12, 40)).isEmpty)
    }

    func testEditingKeepsIdentity() {
        let lunch = WorkBreak(start: at(12), end: at(12, 30))
        let change = Breaks.add(start: at(12, 15), end: at(12, 45), replacing: lunch.id, entries: [], breaks: [lunch], now: at(15))
        XCTAssertTrue(change.deletedBreaks.isEmpty)
        XCTAssertEqual(change.savedBreaks.map(\.id), [lunch.id])
        XCTAssertEqual(change.savedBreaks.first?.start, at(12, 15))
        // laufende Pause bleibt laufend
        let current = WorkBreak(start: at(14))
        let edited = Breaks.add(start: at(13, 50), end: at(15), replacing: current.id, entries: [], breaks: [current], now: at(15))
        XCTAssertNil(edited.savedBreaks.first?.end)
        XCTAssertEqual(edited.savedBreaks.first?.start, at(13, 50))
    }

    func testWorkingTimeAct() {
        XCTAssertEqual(Breaks.requiredMinutes(worked: 6 * 3600), 0)
        XCTAssertEqual(Breaks.requiredMinutes(worked: 6 * 3600 + 60), 30)
        XCTAssertEqual(Breaks.requiredMinutes(worked: 9.5 * 3600), 45)
        let breaks = [
            WorkBreak(start: at(10), end: at(10, 10)), // zählt nicht (unter 15 Minuten)
            WorkBreak(start: at(12), end: at(12, 20)),
        ]
        XCTAssertEqual(Breaks.countedMinutes(on: day, breaks: breaks, now: at(18), calendar: calendar), 20)
        XCTAssertEqual(Breaks.total(on: day, breaks: breaks, now: at(18), calendar: calendar), 30 * 60)
        XCTAssertEqual(Breaks.missingMinutes(worked: 7 * 3600, countedMinutes: 20), 10)
        XCTAssertEqual(Breaks.on(day, breaks, now: at(18), calendar: calendar).count, 2)
    }

    func testStoredInSQLite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("break-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteStore(url: url)
        let lunch = WorkBreak(start: at(12), end: at(12, 30), note: "Mittag", resumeTaskID: taskA)
        let running = WorkBreak(start: at(15))
        try store.save(lunch)
        try store.save(running)
        XCTAssertEqual(try store.load().breaks, [lunch, running])
        try store.deleteBreak(id: lunch.id)
        XCTAssertEqual(try store.load().breaks, [running])
    }
}

final class StandingTaskTests: XCTestCase {
    func testStandingTasksStayOutOfInboxAndRollOver() {
        let today = LocalDate(year: 2026, month: 11, day: 24)
        let standing = TaskItem(title: "Organisatorisches", sortIndex: 2, isStanding: true)
        let meeting = TaskItem(title: "Interne Besprechung", sortIndex: 1, isStanding: true)
        let normal = TaskItem(title: "Angebot schreiben")
        // eine Standardaufgabe mit Tag (z. B. aus Versehen) wandert nicht mit
        var stale = TaskItem(title: "Weiterbildung", plannedDate: LocalDate(year: 2026, month: 11, day: 20), isStanding: true)
        stale.sortIndex = 3
        let tasks = [standing, meeting, normal, stale]
        XCTAssertEqual(DayPlan.inbox(tasks).map(\.id), [normal.id])
        XCTAssertEqual(DayPlan.standing(tasks).map(\.title), ["Interne Besprechung", "Organisatorisches", "Weiterbildung"])
        XCTAssertTrue(DayPlan.rollOver(tasks, to: today).isEmpty)
    }

    func testStoredInSQLite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("standing-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteStore(url: url)
        let task = TaskItem(title: "Organisatorisches", createdAt: Date(timeIntervalSince1970: 1_800_000_000), isStanding: true)
        try store.save(task)
        XCTAssertEqual(try store.load().tasks.first?.isStanding, true)
    }
}
