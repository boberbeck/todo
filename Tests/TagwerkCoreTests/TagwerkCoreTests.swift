import XCTest
@testable import TagwerkCore

final class LocalDateTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func testStringRoundTrip() {
        let date = LocalDate(year: 2026, month: 11, day: 19)
        XCTAssertEqual(date.string, "2026-11-19")
        XCTAssertEqual(LocalDate(string: "2026-11-19"), date)
        XCTAssertNil(LocalDate(string: "2026-13-01"))
        XCTAssertNil(LocalDate(string: "kein Datum"))
    }

    func testAddingDaysAcrossMonth() {
        let date = LocalDate(year: 2026, month: 11, day: 30)
        XCTAssertEqual(date.adding(days: 1, calendar: calendar), LocalDate(year: 2026, month: 12, day: 1))
        XCTAssertEqual(date.adding(days: -30, calendar: calendar), LocalDate(year: 2026, month: 10, day: 31))
    }

    func testStartOfWeekIsMonday() {
        // 19.11.2026 ist ein Donnerstag
        let thursday = LocalDate(year: 2026, month: 11, day: 19)
        XCTAssertEqual(thursday.startOfWeek(calendar: calendar), LocalDate(year: 2026, month: 11, day: 16))
    }

    func testComparison() {
        XCTAssertLessThan(LocalDate(year: 2026, month: 1, day: 31), LocalDate(year: 2026, month: 2, day: 1))
    }
}

final class TimeMathTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    func testFormat() {
        XCTAssertEqual(TimeMath.format(2535), "0:42")
        XCTAssertEqual(TimeMath.format(2535, showSeconds: true), "0:42:15")
        XCTAssertEqual(TimeMath.format(minutes: 90), "1:30")
        XCTAssertEqual(TimeMath.format(-5), "0:00")
    }

    func testRounding() {
        XCTAssertEqual(TimeMath.rounded(0, toMinutes: 15, mode: .nearest), 0)
        XCTAssertEqual(TimeMath.rounded(60, toMinutes: 15, mode: .nearest), 15, "kurze Zeiten zählen mindestens einen Schritt")
        XCTAssertEqual(TimeMath.rounded(22 * 60, toMinutes: 15, mode: .nearest), 15)
        XCTAssertEqual(TimeMath.rounded(23 * 60, toMinutes: 15, mode: .nearest), 30)
        XCTAssertEqual(TimeMath.rounded(16 * 60, toMinutes: 15, mode: .up), 30)
        XCTAssertEqual(TimeMath.rounded(45 * 60, toMinutes: 15, mode: .up), 45)
    }

    func testTrackedPerDaySplitsAtMidnight() {
        let day = LocalDate(year: 2026, month: 11, day: 19)
        let midnight = day.adding(days: 1, calendar: calendar).startDate(calendar: calendar)
        let entry = TimeEntry(taskID: UUID(), start: midnight.addingTimeInterval(-1800), end: midnight.addingTimeInterval(600))
        XCTAssertEqual(TimeMath.tracked(on: day, entries: [entry], now: midnight, calendar: calendar), 1800)
        let nextDay = day.adding(days: 1, calendar: calendar)
        XCTAssertEqual(TimeMath.tracked(on: nextDay, entries: [entry], now: midnight, calendar: calendar), 600)
    }

    func testRunningEntryCountsUntilNow() {
        let task = UUID()
        let start = Date(timeIntervalSince1970: 1_000_000)
        let entries = [
            TimeEntry(taskID: task, start: start, end: start.addingTimeInterval(600)),
            TimeEntry(taskID: task, start: start.addingTimeInterval(1200)),
            TimeEntry(taskID: UUID(), start: start, end: start.addingTimeInterval(999)),
        ]
        XCTAssertEqual(TimeMath.tracked(taskID: task, entries: entries, now: start.addingTimeInterval(1500)), 900)
    }
}

final class DurationParserTests: XCTestCase {
    func testParsesTrailingEstimate() {
        XCTAssertEqual(DurationParser.split(title: "Angebot schreiben 1h30").title, "Angebot schreiben")
        XCTAssertEqual(DurationParser.split(title: "Angebot schreiben 1h30").minutes, 90)
        XCTAssertEqual(DurationParser.split(title: "Logs prüfen 45m").minutes, 45)
        XCTAssertEqual(DurationParser.split(title: "Logs prüfen 45min").minutes, 45)
        XCTAssertEqual(DurationParser.split(title: "Review 1,5h").minutes, 90)
        XCTAssertEqual(DurationParser.split(title: "Review 2h").minutes, 120)
        XCTAssertEqual(DurationParser.split(title: "Termin vorbereiten 0:20").minutes, 20)
    }

    func testLeavesNormalTitlesAlone() {
        XCTAssertEqual(DurationParser.split(title: "Bericht").title, "Bericht")
        XCTAssertNil(DurationParser.split(title: "Bericht").minutes)
        XCTAssertNil(DurationParser.split(title: "Neues Programm").minutes)
        XCTAssertNil(DurationParser.split(title: "Mit dem Team").minutes)
        XCTAssertNil(DurationParser.split(title: "Hinweis:").minutes)
        XCTAssertNil(DurationParser.split(title: "1h").minutes, "ein Titel nur aus Zeit bleibt Titel")
        XCTAssertEqual(DurationParser.split(title: "  Kunde anrufen  ").title, "Kunde anrufen")
    }
}

final class DayPlanTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 19)

    func testRollOverMovesOnlyOpenPastTasks() {
        let yesterday = LocalDate(year: 2026, month: 11, day: 18)
        let openOld = TaskItem(title: "offen", plannedDate: yesterday, sortIndex: 1)
        let doneOld = TaskItem(title: "erledigt", plannedDate: yesterday, status: .done, sortIndex: 2)
        let todayTask = TaskItem(title: "heute", plannedDate: today, sortIndex: 5)
        let inbox = TaskItem(title: "eingang")
        let changed = DayPlan.rollOver([openOld, doneOld, todayTask, inbox], to: today)
        XCTAssertEqual(changed.map(\.id), [openOld.id])
        XCTAssertEqual(changed.first?.plannedDate, today)
        XCTAssertEqual(changed.first?.sortIndex, 6, "wandert ans Ende des heutigen Plans")
    }

    func testPlannedMinutesAndOverplanning() {
        let tasks = [
            TaskItem(title: "a", estimateMinutes: 90),
            TaskItem(title: "b", estimateMinutes: nil),
            TaskItem(title: "c", estimateMinutes: 45),
        ]
        XCTAssertEqual(DayPlan.plannedMinutes(tasks), 135)
        XCTAssertTrue(DayPlan.isOverplanned(plannedMinutes: 500, availableMinutes: 480))
        XCTAssertFalse(DayPlan.isOverplanned(plannedMinutes: 480, availableMinutes: 480))
    }

    func testNextOpenTask() {
        let a = TaskItem(title: "a", plannedDate: today, sortIndex: 1)
        let b = TaskItem(title: "b", plannedDate: today, status: .done, sortIndex: 2)
        let c = TaskItem(title: "c", plannedDate: today, sortIndex: 3)
        let day = [a, b, c]
        XCTAssertEqual(DayPlan.nextOpenTask(after: a.id, in: day)?.id, c.id)
        XCTAssertEqual(DayPlan.nextOpenTask(after: c.id, in: day)?.id, a.id, "springt an den Anfang zurück")
        XCTAssertEqual(DayPlan.nextOpenTask(after: nil, in: day)?.id, a.id)
    }

    func testReorderMatchesListMoveSemantics() {
        let a = TaskItem(title: "a", sortIndex: 1)
        let b = TaskItem(title: "b", sortIndex: 2)
        let c = TaskItem(title: "c", sortIndex: 3)
        // a hinter c schieben
        let moved = DayPlan.reorder([a, b, c], from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(moved.map(\.title), ["b", "c", "a"])
        XCTAssertEqual(moved.map(\.sortIndex), [1, 2, 3])
        // c an den Anfang
        let front = DayPlan.reorder([a, b, c], from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(front.map(\.title), ["c", "a", "b"])
    }

    func testDayTasksKeepDoneOnesInOrder() {
        let first = TaskItem(title: "erst", plannedDate: today, status: .done, sortIndex: 1)
        let second = TaskItem(title: "dann", plannedDate: today, sortIndex: 2)
        let other = TaskItem(title: "morgen", plannedDate: today.adding(days: 1), sortIndex: 0)
        XCTAssertEqual(DayPlan.tasks(for: today, in: [second, other, first]).map(\.title), ["erst", "dann"])
    }
}

final class TimerLogicTests: XCTestCase {
    func testStartStopsRunningEntry() {
        let start = Date(timeIntervalSince1970: 1_000)
        let taskA = UUID()
        let taskB = UUID()
        let running = TimeEntry(taskID: taskA, start: start)
        let change = TimerLogic.start(taskID: taskB, entries: [running], at: start.addingTimeInterval(600))
        XCTAssertEqual(change.stopped.count, 1)
        XCTAssertEqual(change.stopped.first?.end, start.addingTimeInterval(600))
        XCTAssertEqual(change.started?.taskID, taskB)
    }

    func testStartingSameTaskTwiceChangesNothing() {
        let task = UUID()
        let running = TimeEntry(taskID: task, start: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(TimerLogic.start(taskID: task, entries: [running], at: Date(timeIntervalSince1970: 60)), TimerLogic.Change())
    }

    func testVeryShortEntriesAreDiscarded() {
        let running = TimeEntry(taskID: UUID(), start: Date(timeIntervalSince1970: 0))
        let change = TimerLogic.stop(entries: [running], at: Date(timeIntervalSince1970: 2))
        XCTAssertTrue(change.stopped.isEmpty)
        XCTAssertEqual(change.discarded.count, 1)
    }
}

final class SQLiteStoreTests: XCTestCase {
    func testSaveAndLoadEverything() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tagwerk-test-\(UUID().uuidString)")
            .appendingPathComponent("tagwerk.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let customer = Customer(name: "Kunde A", colorIndex: 2, createdAt: created)
        let task = TaskItem(
            title: "VPN-Störung prüfen",
            customerID: customer.id,
            source: .ticket,
            externalID: "1234",
            plannedDate: LocalDate(year: 2026, month: 11, day: 19),
            estimateMinutes: 60,
            workType: .stoerung,
            pspElement: "4711",
            workDescription: "Logs geprüft",
            sortIndex: 3,
            createdAt: created
        )
        let entry = TimeEntry(taskID: task.id, start: created, end: created.addingTimeInterval(900), note: "")
        let running = TimeEntry(taskID: task.id, start: created.addingTimeInterval(1000))

        do {
            let store = try SQLiteStore(url: url)
            try store.save(customer)
            try store.save(task)
            try store.save(entry)
            try store.save(running)
        }

        let reopened = try SQLiteStore(url: url)
        let snapshot = try reopened.load()
        XCTAssertEqual(snapshot.customers, [customer])
        XCTAssertEqual(snapshot.tasks, [task])
        XCTAssertEqual(Set(snapshot.entries), Set([entry, running]))

        var changed = task
        changed.status = .done
        changed.completedAt = created.addingTimeInterval(2000)
        changed.plannedDate = nil
        try reopened.save(changed)
        XCTAssertEqual(try reopened.load().tasks, [changed], "Speichern überschreibt statt zu verdoppeln")

        try reopened.deleteTask(id: task.id)
        let empty = try reopened.load()
        XCTAssertTrue(empty.tasks.isEmpty)
        XCTAssertTrue(empty.entries.isEmpty, "Zeiten einer gelöschten Aufgabe verschwinden mit")
    }
}
