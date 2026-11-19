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
            createdAt: created,
            scheduledStart: created.addingTimeInterval(3600),
            calendarEventID: "EK-123"
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

        let psp = PSPElement(customerID: customer.id, code: "4711", title: "Wartung 2026", lastUsedAt: created)
        let booking = Booking(
            taskID: task.id,
            day: LocalDate(year: 2026, month: 11, day: 19),
            target: .manageEngine,
            minutes: 45,
            description: "Logs geprüft",
            pspElement: "4711",
            workType: .stoerung,
            ticketKey: "998877",
            status: .failed,
            lastError: "Zeitüberschreitung",
            attempts: 2,
            updatedAt: created
        )
        try reopened.save(psp)
        try reopened.save(booking)
        var account = customer
        account.manageEngineAccount = "Müller Logistik GmbH"
        try reopened.save(account)
        let withBookings = try reopened.load()
        XCTAssertEqual(withBookings.pspElements, [psp])
        XCTAssertEqual(withBookings.bookings, [booking])
        XCTAssertEqual(withBookings.customers.first?.manageEngineAccount, "Müller Logistik GmbH")

        try reopened.deleteTask(id: task.id)
        let empty = try reopened.load()
        XCTAssertTrue(empty.tasks.isEmpty)
        XCTAssertTrue(empty.entries.isEmpty, "Zeiten einer gelöschten Aufgabe verschwinden mit")
        XCTAssertTrue(empty.bookings.isEmpty, "Buchungen einer gelöschten Aufgabe verschwinden mit")
    }
}

final class FreeTimeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private let day = LocalDate(year: 2026, month: 11, day: 19)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        FreeTime.date(on: day, minutes: hour * 60 + minute, calendar: calendar)
    }

    private func event(_ from: Date, _ to: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: UUID().uuidString, title: "Termin", start: from, end: to, isAllDay: allDay)
    }

    func testWorkdayInterval() {
        let window = Workday(startMinutes: 8 * 60, endMinutes: 17 * 60).interval(on: day, calendar: calendar)
        XCTAssertEqual(window.start, at(8))
        XCTAssertEqual(window.end, at(17))
        XCTAssertEqual(Workday(startMinutes: 600, endMinutes: 500).durationMinutes, 0, "Ende vor Beginn ergibt keine Arbeitszeit")
    }

    func testMergeJoinsOverlaps() {
        let merged = FreeTime.merge([
            DateInterval(start: at(10), end: at(11)),
            DateInterval(start: at(9), end: at(10, 30)),
            DateInterval(start: at(13), end: at(14)),
        ])
        XCTAssertEqual(merged, [DateInterval(start: at(9), end: at(11)), DateInterval(start: at(13), end: at(14))])
    }

    func testFreeMinutesIgnoreAllDayAndOutsideEvents() {
        let window = DateInterval(start: at(8), end: at(17))
        let events = [
            event(at(9), at(9, 30)),
            event(at(10), at(11)),
            event(at(10, 30), at(11, 30)),
            event(at(7), at(8, 15)),
            event(at(18), at(19)),
            event(at(0), at(23, 59), allDay: true),
        ]
        // belegt: 8:00–8:15, 9:00–9:30, 10:00–11:30 → 15 + 30 + 90 = 135 Minuten
        XCTAssertEqual(FreeTime.freeMinutes(window: window, events: events), 9 * 60 - 135)
    }

    func testGaps() {
        let window = DateInterval(start: at(8), end: at(12))
        let gaps = FreeTime.gaps(in: window, busy: [DateInterval(start: at(9), end: at(10)), DateInterval(start: at(11), end: at(13))])
        XCTAssertEqual(gaps, [DateInterval(start: at(8), end: at(9)), DateInterval(start: at(10), end: at(11))])
    }

    func testSnapping() {
        XCTAssertEqual(FreeTime.snapUp(at(9, 7), stepMinutes: 15, calendar: calendar), at(9, 15))
        XCTAssertEqual(FreeTime.snapUp(at(9, 15), stepMinutes: 15, calendar: calendar), at(9, 15))
        XCTAssertEqual(FreeTime.snapNearest(at(9, 7), stepMinutes: 15, calendar: calendar), at(9))
        XCTAssertEqual(FreeTime.snapNearest(at(9, 8), stepMinutes: 15, calendar: calendar), at(9, 15))
    }

    func testAutoScheduleFillsGapsInOrder() {
        let gaps = [DateInterval(start: at(8), end: at(9)), DateInterval(start: at(10), end: at(12))]
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let result = FreeTime.autoSchedule(
            [(a, 45), (b, 90), (c, 30), (d, 120)],
            gaps: gaps,
            notBefore: at(8, 5),
            calendar: calendar
        )
        XCTAssertEqual(result[a], at(8, 15), "frühestens ab jetzt, auf 15 Minuten gerundet")
        XCTAssertEqual(result[b], at(10), "passt nicht mehr vor 9 Uhr")
        XCTAssertEqual(result[c], at(11, 30))
        XCTAssertNil(result[d], "kein Platz mehr")
    }

    func testDailyPlanningDue() {
        XCTAssertTrue(DailyPlanning.isDue(lastPlanned: nil, today: day))
        XCTAssertTrue(DailyPlanning.isDue(lastPlanned: day.adding(days: -1, calendar: calendar), today: day))
        XCTAssertFalse(DailyPlanning.isDue(lastPlanned: day, today: day))
    }

    func testTaskBlockLength() {
        XCTAssertEqual(TaskItem(title: "a").blockMinutes, 30)
        XCTAssertEqual(TaskItem(title: "b", estimateMinutes: 90).blockMinutes, 90)
        XCTAssertEqual(TaskItem(title: "c", estimateMinutes: 5).blockMinutes, 15)
    }
}

final class DailyCloseTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private let day = LocalDate(year: 2026, month: 11, day: 19)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        FreeTime.date(on: day, minutes: hour * 60 + minute, calendar: calendar)
    }

    func testLinesRoundAndPickTargets() {
        let ticket = TaskItem(
            title: "VPN-Störung", source: .ticket, externalID: "1234", workType: .stoerung,
            pspElement: "4711", workDescription: "Logs geprüft", externalKey: "998877"
        )
        let todo = TaskItem(title: "Angebot schreiben")
        let entries = [
            TimeEntry(taskID: ticket.id, start: at(9), end: at(9, 20)),
            TimeEntry(taskID: ticket.id, start: at(11), end: at(11, 18)),
            TimeEntry(taskID: todo.id, start: at(8), end: at(8, 50)),
        ]
        let lines = DailyClose.lines(
            for: day, tasks: [ticket, todo], entries: entries, bookings: [],
            rules: BookingRules(roundingStep: 15, roundingMode: .nearest), now: at(18), calendar: calendar
        )
        XCTAssertEqual(lines.map(\.task.id), [todo.id, ticket.id], "sortiert nach erstem Start")
        let ticketLine = lines[1]
        XCTAssertEqual(ticketLine.minutes, 45, "38 Minuten werden zu 45")
        XCTAssertEqual(ticketLine.targets, [.sap, .manageEngine])
        XCTAssertTrue(ticketLine.issues.isEmpty)
        XCTAssertEqual(ticketLine.sapComment, "#1234 Logs geprüft")
        let todoLine = lines[0]
        XCTAssertEqual(todoLine.targets, [.sap])
        XCTAssertEqual(Set(todoLine.issues), [.missingPSP, .missingWorkType])
    }

    func testPrepareSkipsDoneAndIncompleteTargets() {
        let ticket = TaskItem(
            title: "Drucker", source: .ticket, externalID: "1241", workType: .wartung,
            pspElement: "4702", workDescription: "", externalKey: "555"
        )
        let entries = [TimeEntry(taskID: ticket.id, start: at(10), end: at(10, 30))]
        let lines = DailyClose.lines(
            for: day, tasks: [ticket], entries: entries, bookings: [],
            rules: BookingRules(), now: at(18), calendar: calendar
        )
        let prepared = DailyClose.prepare(lines[0], now: at(18))
        XCTAssertEqual(prepared.map(\.target), [.sap], "ohne Beschreibung kein Worklog")

        let entered = BookingQueue.entered(prepared[0], now: at(18))
        let again = DailyClose.lines(
            for: day, tasks: [ticket], entries: entries, bookings: [entered],
            rules: BookingRules(), now: at(18), calendar: calendar
        )
        XCTAssertTrue(DailyClose.prepare(again[0], now: at(18)).isEmpty, "Eingetragenes wird nie doppelt vorbereitet")
        XCTAssertFalse(again[0].changedAfterBooking)

        let longer = entries + [TimeEntry(taskID: ticket.id, start: at(14), end: at(14, 30))]
        let changed = DailyClose.lines(
            for: day, tasks: [ticket], entries: longer, bookings: [entered],
            rules: BookingRules(), now: at(18), calendar: calendar
        )
        XCTAssertTrue(changed[0].changedAfterBooking, "nachträglich geänderte Zeit wird gemeldet")
    }

    func testQueueRetriesWithBackoff() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let booking = Booking(taskID: UUID(), day: day, target: .manageEngine, minutes: 30, description: "x")
        XCTAssertEqual(BookingQueue.due([booking], target: .manageEngine, now: start).count, 1)
        XCTAssertTrue(BookingQueue.due([booking], target: .sap, now: start).isEmpty)

        let failed = BookingQueue.failed(booking, error: "offline", now: start)
        XCTAssertEqual(failed.attempts, 1)
        XCTAssertTrue(BookingQueue.due([failed], target: .manageEngine, now: start.addingTimeInterval(10)).isEmpty)
        XCTAssertEqual(BookingQueue.due([failed], target: .manageEngine, now: start.addingTimeInterval(31)).count, 1)
        XCTAssertEqual(BookingQueue.retryDelay(attempts: 3), 120)
        XCTAssertEqual(BookingQueue.retryDelay(attempts: 20), 3600)

        let confirmed = BookingQueue.confirmed(failed, reference: "WL-1", now: start)
        XCTAssertTrue(BookingQueue.due([confirmed], target: .manageEngine, now: start.addingTimeInterval(9999)).isEmpty)
        XCTAssertNil(confirmed.lastError)
    }

    func testSAPTransferList() {
        let booking = Booking(
            taskID: UUID(), day: day, target: .sap, minutes: 75,
            description: "#1234 Logs \"VPN\"; neu gestartet", pspElement: "4711", workType: .stoerung
        )
        let csv = SAPTransfer.csv([booking]) { $0 == .stoerung ? "S-100" : "" }
        XCTAssertEqual(csv, "Datum;PSP-Element;Leistung;Stunden;Kommentar\n19.11.2026;4711;S-100;1,25;\"#1234 Logs \"\"VPN\"\"; neu gestartet\"\n")
        XCTAssertEqual(SAPTransfer.hours(30), "0,50")
    }
}

final class ManageEngineAPITests: XCTestCase {
    private let config = ManageEngineConfig(baseURL: "https://helpdesk.example.com/", authKind: .authtoken, technicianID: "301")

    private func inputData(_ request: URLRequest) throws -> [String: Any] {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let value = components?.queryItems?.first { $0.name == "input_data" }?.value ?? ""
        return try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] ?? [:]
    }

    func testNotConfigured() {
        XCTAssertThrowsError(try ManageEngineAPI.connectionTest(config: ManageEngineConfig(), token: "x"))
    }

    func testAssignedRequestsRequest() throws {
        let request = try ManageEngineAPI.assignedRequests(config: config, token: "SECRET")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v3/requests")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authtoken"), "SECRET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), ManageEngineAPI.acceptHeader)
        let listInfo = try inputData(request)["list_info"] as? [String: Any]
        let criteria = listInfo?["search_criteria"] as? [[String: Any]]
        XCTAssertEqual(criteria?.first?["value"] as? String, "301")
    }

    func testCloudUsesZohoHeader() throws {
        let cloud = ManageEngineConfig(baseURL: "https://sdpondemand.manageengine.eu/app/itdesk", authKind: .zohoOAuth, technicianID: "7")
        let request = try ManageEngineAPI.connectionTest(config: cloud, token: "T")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Zoho-oauthtoken T")
        XCTAssertEqual(request.url?.path, "/app/itdesk/api/v3/requests")
        XCTAssertEqual(ManageEngineAPI.webURL(for: "55", config: cloud), "https://sdpondemand.manageengine.eu/app/itdesk/ui/requests/55/details")
    }

    func testWorklogRequest() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let request = try ManageEngineAPI.addWorklog(
            config: config, token: "SECRET", requestKey: "998877",
            description: "Logs geprüft & Tunnel neu", minutes: 90, start: start
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://helpdesk.example.com/api/v3/requests/998877/worklogs")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("input_data="))
        let json = String(body.dropFirst("input_data=".count)).removingPercentEncoding ?? ""
        let worklog = (try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["worklog"] as? [String: Any]
        XCTAssertEqual(worklog?["description"] as? String, "Logs geprüft & Tunnel neu")
        XCTAssertEqual((worklog?["owner"] as? [String: Any])?["id"] as? String, "301")
        XCTAssertEqual((worklog?["time_spent"] as? [String: Any])?["hours"] as? String, "1")
        XCTAssertEqual((worklog?["time_spent"] as? [String: Any])?["minutes"] as? String, "30")
        XCTAssertEqual((worklog?["start_time"] as? [String: Any])?["value"] as? String, "1800000000000")
        XCTAssertEqual((worklog?["end_time"] as? [String: Any])?["value"] as? String, "1800005400000")
    }

    func testParseTickets() throws {
        let json = """
        {"requests": [
          {"id": "998877", "display_id": "1234", "subject": "VPN geht nicht", "status": {"name": "Open", "in_progress": true}, "account": {"name": "Müller Logistik"}},
          {"id": 555, "subject": "Drucker", "status": {"name": "Closed"}}
        ], "response_status": [{"status_code": 2000, "status": "success"}]}
        """
        let tickets = try ManageEngineAPI.parseTickets(Data(json.utf8), config: config)
        XCTAssertEqual(tickets.count, 2)
        XCTAssertEqual(tickets[0].key, "998877")
        XCTAssertEqual(tickets[0].number, "1234")
        XCTAssertEqual(tickets[0].accountName, "Müller Logistik")
        XCTAssertTrue(tickets[0].isOpen)
        XCTAssertEqual(tickets[1].key, "555")
        XCTAssertEqual(tickets[1].number, "555")
        XCTAssertFalse(tickets[1].isOpen)
        XCTAssertEqual(tickets[1].webURL, "https://helpdesk.example.com/WorkOrder.do?woMode=viewWO&woID=555")
    }

    func testParseWorklogAndErrors() throws {
        let ok = #"{"worklog": {"id": "WL-42"}, "response_status": {"status_code": 2000, "status": "success"}}"#
        XCTAssertEqual(try ManageEngineAPI.parseWorklogID(Data(ok.utf8)), "WL-42")
        let error = #"{"response_status": {"status_code": 4000, "status": "failed", "messages": [{"message": "Ungültiger Schlüssel"}]}}"#
        XCTAssertThrowsError(try ManageEngineAPI.parseWorklogID(Data(error.utf8))) { thrown in
            XCTAssertEqual(thrown as? ManageEngineError, .server("Ungültiger Schlüssel"))
        }
    }
}
