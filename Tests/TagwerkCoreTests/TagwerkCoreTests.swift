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
            description: "Logs geprüft & Tunnel neu", minutes: 90, start: start, worklogType: "Ticketbearbeitung"
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
        XCTAssertEqual((worklog?["type"] as? [String: Any])?["name"] as? String, "Ticketbearbeitung")
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

final class ReviewTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private let thursday = LocalDate(year: 2026, month: 11, day: 19)

    private func at(_ day: LocalDate, _ hour: Int, _ minute: Int = 0) -> Date {
        FreeTime.date(on: day, minutes: hour * 60 + minute, calendar: calendar)
    }

    func testWeekDays() {
        let days = WeeklyReview.days(ofWeekContaining: thursday, calendar: calendar)
        XCTAssertEqual(days.first, LocalDate(year: 2026, month: 11, day: 16))
        XCTAssertEqual(days.last, LocalDate(year: 2026, month: 11, day: 22))
    }

    func testGoalTimeCountsOnlyLinkedTasksInThatWeek() {
        let monday = thursday.startOfWeek(calendar: calendar)
        let goal = WeeklyGoal(weekStart: monday, title: "Netzumbau vorbereiten")
        let linked = TaskItem(title: "Plan", goalID: goal.id)
        let other = TaskItem(title: "Sonstiges")
        let entries = [
            TimeEntry(taskID: linked.id, start: at(thursday, 9), end: at(thursday, 10)),
            TimeEntry(taskID: linked.id, start: at(monday.adding(days: -1, calendar: calendar), 9), end: at(monday.adding(days: -1, calendar: calendar), 10)),
            TimeEntry(taskID: other.id, start: at(thursday, 11), end: at(thursday, 12)),
        ]
        XCTAssertEqual(
            WeeklyReview.trackedSeconds(for: goal, tasks: [linked, other], entries: entries, now: at(thursday, 18), calendar: calendar),
            3600
        )
    }

    func testIdleDiscardEndsEntryAtIdleStartAndContinues() {
        let task = UUID()
        let running = TimeEntry(taskID: task, start: at(thursday, 9))
        let change = TimerLogic.resolveIdle(entries: [running], idleStart: at(thursday, 10), now: at(thursday, 10, 25), decision: .discard)
        XCTAssertEqual(change.stopped.first?.end, at(thursday, 10))
        XCTAssertEqual(change.started?.taskID, task)
        XCTAssertEqual(change.started?.start, at(thursday, 10, 25))
    }

    func testIdleAssignMovesPauseToOtherTask() {
        let task = UUID()
        let call = UUID()
        let running = TimeEntry(taskID: task, start: at(thursday, 9))
        let change = TimerLogic.resolveIdle(entries: [running], idleStart: at(thursday, 10), now: at(thursday, 10, 25), decision: .assign(to: call))
        XCTAssertEqual(change.stopped.count, 2)
        XCTAssertEqual(change.stopped.last?.taskID, call)
        XCTAssertEqual(change.stopped.last?.start, at(thursday, 10))
        XCTAssertEqual(change.stopped.last?.end, at(thursday, 10, 25))
        XCTAssertEqual(change.started?.taskID, task)
    }

    func testIdleKeepChangesNothing() {
        let running = TimeEntry(taskID: UUID(), start: at(thursday, 9))
        XCTAssertEqual(TimerLogic.resolveIdle(entries: [running], idleStart: at(thursday, 10), now: at(thursday, 11), decision: .keep), TimerLogic.Change())
    }

    func testEmailHeaderParsing() {
        let mail = """
        Received: from mail.example.com
        From: =?UTF-8?Q?J=C3=BCrgen_M=C3=BCller?= <juergen@example.com>
        To: ich@example.com
        Subject: =?UTF-8?B?UsO8Y2tmcmFnZQ==?= zur
         Rechnung 4711
        Date: Thu, 19 Nov 2026 09:12:00 +0100
        Message-ID: <abc@example.com>

        Hallo, Subject: nicht hier
        """
        let header = EmailHeaderParser.parse(Data(mail.utf8))
        XCTAssertEqual(header.subject, "Rückfrage zur Rechnung 4711")
        XCTAssertEqual(header.from, "Jürgen Müller")
        XCTAssertEqual(header.messageID, "<abc@example.com>")
    }

    func testEmailFromWithoutName() {
        let header = EmailHeaderParser.parse(Data("From: <service@example.com>\nSubject: Test\n\nx".utf8))
        XCTAssertEqual(header.from, "service@example.com")
        XCTAssertEqual(header.subject, "Test")
    }

    func testBackupRotation() {
        let names = [
            "tagwerk-2026-11-19.sqlite", "tagwerk-2026-11-17.sqlite", "tagwerk-2026-11-18.sqlite",
            "tagwerk-2026-11-01.sqlite", "notiz.txt",
        ]
        XCTAssertEqual(BackupPolicy.filesToDelete(names, keep: 2), ["tagwerk-2026-11-17.sqlite", "tagwerk-2026-11-01.sqlite"])
        XCTAssertEqual(BackupPolicy.fileName(for: thursday), "tagwerk-2026-11-19.sqlite")
    }

    func testTimeExport() {
        let customer = Customer(name: "Müller; Logistik")
        let task = TaskItem(title: "VPN", customerID: customer.id, source: .ticket, externalID: "1234", workType: .stoerung, pspElement: "4711")
        let entry = TimeEntry(taskID: task.id, start: at(thursday, 9), end: at(thursday, 9, 45))
        let csv = TimeExport.csv(entries: [entry], tasks: [task], customers: [customer], now: at(thursday, 18), calendar: calendar)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], "19.11.2026;09:00;09:45;45;\"Müller; Logistik\";VPN;Ticket;1234;Störung;4711;")
    }

    func testSQLiteGoalsAndBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tagwerk-goal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try SQLiteStore(url: folder.appendingPathComponent("tagwerk.sqlite"))
        let goal = WeeklyGoal(weekStart: thursday.startOfWeek(calendar: calendar), title: "Angebote raus", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let task = TaskItem(title: "Angebot A", createdAt: Date(timeIntervalSince1970: 1_700_000_000), goalID: goal.id)
        try store.save(goal)
        try store.save(task)
        XCTAssertEqual(try store.load().goals, [goal])
        XCTAssertEqual(try store.load().tasks.first?.goalID, goal.id)

        let backupURL = folder.appendingPathComponent("Backups/tagwerk-2026-11-19.sqlite")
        try store.backup(to: backupURL)
        let restored = try SQLiteStore(url: backupURL).load()
        XCTAssertEqual(restored.goals, [goal], "die Sicherung lässt sich wieder öffnen")

        try store.deleteGoal(id: goal.id)
        let after = try store.load()
        XCTAssertTrue(after.goals.isEmpty)
        XCTAssertNil(after.tasks.first?.goalID, "Aufgaben verlieren nur die Verknüpfung")
    }
}

final class SAPImportTests: XCTestCase {
    func testTaskIDs() {
        XCTAssertTrue(SAPImport.looksLikeTaskID("CPSO8643-12"))
        XCTAssertTrue(SAPImport.looksLikeTaskID("P1000-3"))
        XCTAssertTrue(SAPImport.looksLikeTaskID("CPSO8643-12-1"))
        XCTAssertFalse(SAPImport.looksLikeTaskID("2026-11-19"))
        XCTAssertFalse(SAPImport.looksLikeTaskID("UTF-8"))
        XCTAssertFalse(SAPImport.looksLikeTaskID("Projektaufgabenbestätigung"))
        XCTAssertFalse(SAPImport.looksLikeTaskID("cpso8643-1"))
        XCTAssertEqual(SAPImport.projectKey(of: "CPSO8643-12"), "CPSO8643")
    }

    func testTableWithHeader() {
        let text = """
        Kategorie\tAufgabennummer\tAufgabenname\tKunde
        Projektaufgabenbestätigung\tCPSO8643-12\tFirewall erneuern\tMüller Logistik GmbH
        Projektaufgabenbestätigung\tCPSO8643-1\tWartung\tMüller Logistik GmbH
        Projektaufgabenbestätigung\tCPSO8643-1\tWartung\tMüller Logistik GmbH
        """
        let rows = SAPImport.rows(fromText: text)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].code, "CPSO8643-12")
        XCTAssertEqual(rows[0].title, "Firewall erneuern")
        XCTAssertEqual(rows[0].project, "CPSO8643")
        XCTAssertEqual(rows[0].customerName, "Müller Logistik GmbH")
        XCTAssertEqual(rows[0].category, "Projektaufgabenbestätigung")
    }

    func testTableWithoutHeaderAndSemicolons() {
        let rows = SAPImport.rows(fromText: "Projektaufgabenbestätigung;CPSO8643-5;Migration Exchange\nSumme;;\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].code, "CPSO8643-5")
        XCTAssertEqual(rows[0].title, "Migration Exchange")
    }

    func testLinesCopiedFromBrowser() {
        let rows = SAPImport.rows(fromText: "Projektaufgabenbestätigung CPSO8643-7\nCPSO8643-8 Netzwerk\nGruppieren nach Kategorie")
        XCTAssertEqual(rows.map(\.code), ["CPSO8643-7", "CPSO8643-8"])
        XCTAssertEqual(rows[1].title, "Netzwerk")
    }

    func testLinesFromWebPage() {
        // So liest sich eine Tabelle aus Div-Zellen: jede Zelle eine Zeile
        let text = """
        Kategorie
        Aufgabennummer
        Aufgabenname
        Projektaufgabenbestätigung
        CPSO8643-12
        Firewall erneuern
        Projektaufgabenbestätigung
        CPSO8643-1
        Wartung 2026
        """
        let rows = SAPImport.rows(fromText: text)
        XCTAssertEqual(rows.map(\.code), ["CPSO8643-12", "CPSO8643-1"])
        XCTAssertEqual(rows.map(\.title), ["Firewall erneuern", "Wartung 2026"])
    }

    func testActivityColumn() {
        let cells = [
            ["Kategorie", "Aufgabennummer", "Tätigkeit"],
            ["Projektaufgabenbestätigung", "CPSO9001-1", "Interne Besprechung"],
        ]
        let rows = SAPImport.rows(fromCells: cells)
        XCTAssertEqual(rows.first?.activity, "Interne Besprechung")
        XCTAssertEqual(rows.first?.title, "Interne Besprechung", "ohne Namensspalte wird die Tätigkeit zum Namen")

        let customer = Customer(name: "Intern", colorIndex: 0)
        let existing = [PSPElement(customerID: customer.id, code: "CPSO9001-1", title: "Interne Besprechung")]
        let plan = SAPImport.plan(rows: rows, existing: existing, customers: [customer])
        let saved = SAPImport.apply(plan, customerFor: { $0.suggestedCustomerID }, deactivateMissing: false)
        XCTAssertEqual(saved.first?.activity, "Interne Besprechung")
        XCTAssertEqual(saved.first?.label, "CPSO9001-1 · Interne Besprechung")
    }

    func testSQLiteKeepsActivity() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tagwerk-psp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try SQLiteStore(url: folder.appendingPathComponent("tagwerk.sqlite"))
        let psp = PSPElement(customerID: UUID(), code: "CPSO9001-1", title: "Besprechung", activity: "Interne Tätigkeit")
        try store.save(psp)
        XCTAssertEqual(try store.load().pspElements, [psp])
        let ticket = TaskItem(title: "Ticket", source: .ticket, createdAt: Date(timeIntervalSince1970: 1_700_000_000), worklogType: "Fehlalarm")
        try store.save(ticket)
        XCTAssertEqual(try store.load().tasks.first?.worklogType, "Fehlalarm")
    }

    func testChangeTrackingForSync() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tagwerk-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try SQLiteStore(url: folder.appendingPathComponent("tagwerk.sqlite"))
        let start = Date().addingTimeInterval(-1)
        let task = TaskItem(title: "Abgleich vorbereiten")
        let entry = TimeEntry(taskID: task.id, start: Date().addingTimeInterval(-600), end: Date())
        try store.save(task)
        try store.save(entry)
        var changes = try store.changes(since: start)
        XCTAssertEqual(changes.modified["task"], [task.id])
        XCTAssertEqual(changes.modified["time_entry"], [entry.id])
        XCTAssertTrue(changes.deleted.isEmpty)

        try store.deleteEntry(id: entry.id)
        changes = try store.changes(since: start)
        XCTAssertEqual(changes.deleted.map(\.id), [entry.id])
        XCTAssertEqual(changes.deleted.first?.entity, "time_entry")
        XCTAssertTrue(try store.changes(since: Date().addingTimeInterval(60)).isEmpty)
    }

    func testGroupRowsAreNoTitles() {
        let cells = [
            ["Kategorie: Projektaufgabenbestätigung (null)", "CPSO8643-1"],
            ["Gruppieren nach...", "CPSO8643-2"],
            ["Projektaufgabenbestätigung", "CPSO8643-3", "Firewall"],
        ]
        let rows = SAPImport.rows(fromCells: cells)
        XCTAssertEqual(rows.map(\.title), ["", "", "Firewall"])
    }

    func testOCRRepair() {
        XCTAssertEqual(SAPImport.repairOCRCell("CPSO8643 – 12"), "CPSO8643-12")
        XCTAssertEqual(SAPImport.repairOCRCell("Wartung - Server"), "Wartung - Server")
        let rows = [
            SAPTaskRow(code: "CPSO8643-1", title: "A"),
            SAPTaskRow(code: "CPS08643-2", title: "B"),
            SAPTaskRow(code: "CPSO8643-4", title: "C"),
            SAPTaskRow(code: "CPS08643-1", title: "A doppelt"),
        ]
        let repaired = SAPImport.repairOCRCodes(rows)
        XCTAssertEqual(repaired.map(\.code), ["CPSO8643-1", "CPSO8643-2", "CPSO8643-4"])
        XCTAssertEqual(repaired[1].project, "CPSO8643")
    }

    func testCSVQuotes() {
        let cells = TableText.cells(from: "Aufgabennummer,Aufgabenname\n\"CPSO1-2\",\"Beratung, vor Ort\"\n")
        XCTAssertEqual(cells[1], ["CPSO1-2", "Beratung, vor Ort"])
    }

    func testHTMLTable() {
        let html = "<table><tr><th>Aufgabennummer</th><th>Aufgabenname</th></tr><tr><td><span>CPSO8643-9</span></td><td>Gr&uuml;ne&nbsp;Wiese &amp; Co</td></tr></table>"
        let rows = SAPImport.rows(fromCells: HTMLTable.cells(from: html))
        XCTAssertEqual(rows.first?.code, "CPSO8643-9")
        XCTAssertEqual(rows.first?.title, "Grüne Wiese & Co")
    }

    func testXLSXSheet() {
        let shared = """
        <?xml version="1.0" encoding="UTF-8"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Aufgabennummer</t></si><si><t>Aufgabenname</t></si><si><t>CPSO8643-10</t></si><si><r><t>Back</t></r><r><t>up</t></r></si></sst>
        """
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>
        <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>42</v></c><c r="C2" t="s"><v>3</v></c></row>
        <row r="3"><c r="A3" t="inlineStr"><is><t>CPSO8643-11</t></is></c><c r="C3" t="inlineStr"><is><t>Monitoring</t></is></c></row>
        </sheetData></worksheet>
        """
        let cells = XLSXSheet.cells(sheet: Data(sheet.utf8), sharedStrings: Data(shared.utf8))
        XCTAssertEqual(cells[0], ["Aufgabennummer", "", "Aufgabenname"])
        XCTAssertEqual(cells[1], ["CPSO8643-10", "42", "Backup"])
        let rows = SAPImport.rows(fromCells: cells)
        XCTAssertEqual(rows.map(\.code), ["CPSO8643-10", "CPSO8643-11"])
        XCTAssertEqual(rows.map(\.title), ["Backup", "Monitoring"])
        XCTAssertEqual(XLSXSheet.columnIndex(of: "AB12"), 27)
    }

    func testSpreadsheetML() {
        let xml = """
        <?xml version="1.0"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        <Worksheet ss:Name="Aufgaben"><Table>
        <Row><Cell><Data ss:Type="String">Aufgabennummer</Data></Cell><Cell><Data ss:Type="String">Aufgabenname</Data></Cell></Row>
        <Row><Cell><Data ss:Type="String">CPSO8643-4</Data></Cell><Cell ss:Index="2"><Data ss:Type="String">Projekt Netzumbau</Data></Cell></Row>
        </Table></Worksheet></Workbook>
        """
        let data = Data(xml.utf8)
        XCTAssertTrue(SpreadsheetML.isSpreadsheetML(data))
        let rows = SAPImport.rows(fromCells: SpreadsheetML.cells(from: data))
        XCTAssertEqual(rows.first?.code, "CPSO8643-4")
        XCTAssertEqual(rows.first?.title, "Projekt Netzumbau")
    }

    func testPlanAndApply() {
        let mueller = Customer(name: "Müller Logistik", colorIndex: 1, manageEngineAccount: "Müller Logistik GmbH")
        let stadtwerke = Customer(name: "Stadtwerke Nord", colorIndex: 2)
        let existing = [
            PSPElement(customerID: mueller.id, code: "CPSO8643-1", title: "Wartung"),
            PSPElement(customerID: mueller.id, code: "CPSO8643-2", title: "Störungen"),
            PSPElement(customerID: mueller.id, code: "CPSO8643-4", title: "Netzumbau", isActive: false),
            PSPElement(customerID: stadtwerke.id, code: "CPSO9000-1", title: "Support"),
        ]
        let rows = [
            SAPTaskRow(code: "CPSO8643-1", title: "Wartung"),
            SAPTaskRow(code: "CPSO8643-4", title: "Netzumbau"),
            SAPTaskRow(code: "CPSO8643-12", title: "Firewall"),
            SAPTaskRow(code: "CPSO8700-1", title: "Rollout", customerName: "Stadtwerke Nord GmbH"),
            SAPTaskRow(code: "CPSO8800-1", title: "Beratung", customerName: "Hansa Spedition"),
        ]
        let plan = SAPImport.plan(rows: rows, existing: existing, customers: [mueller, stadtwerke])
        XCTAssertEqual(plan.groups.map(\.project), ["CPSO8643", "CPSO8700", "CPSO8800"])
        XCTAssertEqual(plan.groups[0].suggestedCustomerID, mueller.id)
        XCTAssertEqual(plan.groups[1].suggestedCustomerID, stadtwerke.id)
        XCTAssertNil(plan.groups[2].suggestedCustomerID)
        XCTAssertEqual(plan.groups[0].items.map(\.change), [.unchanged, .reactivated, .new])
        // CPSO8643-2 fehlt in SAP, CPSO9000-1 gehört zu einem anderen Projekt und bleibt
        XCTAssertEqual(plan.missing.map(\.code), ["CPSO8643-2"])

        let saved = SAPImport.apply(plan, customerFor: { group in
            group.project == "CPSO8800" ? nil : group.suggestedCustomerID
        }, deactivateMissing: true)
        let byCode = Dictionary(uniqueKeysWithValues: saved.map { ($0.code, $0) })
        XCTAssertNil(byCode["CPSO8643-1"], "Unverändertes wird nicht gespeichert")
        XCTAssertEqual(byCode["CPSO8643-4"]?.isActive, true)
        XCTAssertEqual(byCode["CPSO8643-12"]?.customerID, mueller.id)
        XCTAssertEqual(byCode["CPSO8700-1"]?.customerID, stadtwerke.id)
        XCTAssertNil(byCode["CPSO8800-1"], "Übersprungenes Projekt")
        XCTAssertEqual(byCode["CPSO8643-2"]?.isActive, false)
    }

    func testRenamedTask() {
        let customer = Customer(name: "Becker", colorIndex: 0)
        let existing = [PSPElement(customerID: customer.id, code: "CPSO1-1", title: "Alt")]
        let plan = SAPImport.plan(rows: [SAPTaskRow(code: "CPSO1-1", title: "Neu")], existing: existing, customers: [customer])
        XCTAssertEqual(plan.groups.first?.items.first?.change, .renamed("Alt"))
        let saved = SAPImport.apply(plan, customerFor: { $0.suggestedCustomerID }, deactivateMissing: false)
        XCTAssertEqual(saved.first?.title, "Neu")
        XCTAssertEqual(saved.first?.id, existing[0].id)
    }
}

final class ManageEngineTechnicianTests: XCTestCase {
    private let technicians = [
        ManageEngineTechnician(id: "1501", name: "Björn Lulay", email: "b.lulay@example.com"),
        ManageEngineTechnician(id: "1502", name: "Anna Schmidt", email: "aschmidt@example.com"),
    ]

    func testLoginNameMatchesInitialAndLastName() {
        XCTAssertEqual(ManageEngineAPI.technicians(matching: "blulay", in: technicians).map(\.id), ["1501"])
        XCTAssertEqual(ManageEngineAPI.technicians(matching: "aschmidt", in: technicians).map(\.id), ["1502"])
        XCTAssertEqual(ManageEngineAPI.technicians(matching: "Lulay", in: technicians).map(\.id), ["1501"])
        XCTAssertEqual(ManageEngineAPI.technicians(matching: "1502", in: technicians).map(\.id), ["1502"])
        XCTAssertTrue(ManageEngineAPI.technicians(matching: "xyz", in: technicians).isEmpty)
    }

    func testNumericID() {
        XCTAssertTrue(ManageEngineConfig(baseURL: "https://x", technicianID: " 1501 ").technicianIDIsNumeric)
        XCTAssertFalse(ManageEngineConfig(baseURL: "https://x", technicianID: "blulay").technicianIDIsNumeric)
        let config = ManageEngineConfig(baseURL: "https://helpdesk.example.com", technicianID: "blulay")
        XCTAssertThrowsError(try ManageEngineAPI.assignedRequests(config: config, token: "T")) { error in
            XCTAssertEqual(error as? ManageEngineError, .technicianNotNumeric)
        }
        XCTAssertNoThrow(try ManageEngineAPI.connectionTest(config: config, token: "T"))
        XCTAssertNoThrow(try ManageEngineAPI.connectionTest(config: ManageEngineConfig(baseURL: "https://helpdesk.example.com"), token: "T"))
    }

    func testTechnicianListRequest() throws {
        let config = ManageEngineConfig(baseURL: "https://helpdesk.example.com", technicianID: "blulay")
        let request = try ManageEngineAPI.technicianList(config: config, token: "T", query: "Lulay")
        XCTAssertEqual(request.url?.path, "/api/v3/technicians")
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        let input = components?.queryItems?.first { $0.name == "input_data" }?.value ?? ""
        let listInfo = (try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any])?["list_info"] as? [String: Any]
        let criteria = listInfo?["search_criteria"] as? [[String: Any]]
        XCTAssertEqual(criteria?.first?["value"] as? String, "Lulay")
        XCTAssertEqual(criteria?.last?["logical_operator"] as? String, "or")

        let all = try ManageEngineAPI.technicianList(config: config, token: "T", startIndex: 101, path: "/api/v3/users")
        XCTAssertEqual(all.url?.path, "/api/v3/users")
        XCTAssertFalse(all.url?.absoluteString.contains("search_criteria") ?? true)
    }

    func testParseTechnicianListAndLoginName() throws {
        let json = """
        {"users":[
          {"id":"1501","name":"Björn Lulay","email_id":"bjoern@example.com","login_name":"blulay","is_technician":true},
          {"id":"77","name":"Anfragender","is_technician":false}
        ],"list_info":{"has_more_rows":true},"response_status":[{"status_code":2000,"status":"success"}]}
        """
        let result = try ManageEngineAPI.parseTechnicianList(Data(json.utf8))
        XCTAssertEqual(result.technicians.map(\.id), ["1501"])
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.technicians.first?.loginName, "blulay")
        // passt über den Anmeldenamen, auch wenn die Mail-Adresse anders aussieht
        let other = [ManageEngineTechnician(id: "9", name: "Bernd Lutz", email: "b.lutz@example.com", loginName: "DOMAIN\\blulay")]
        XCTAssertEqual(ManageEngineAPI.technicians(matching: "blulay", in: other).map(\.id), ["9"])
    }

    func testParseTechnicians() throws {
        let json = """
        {"requests":[
          {"id":"1","technician":{"id":"1501","name":"Björn Lulay","email_id":"b.lulay@example.com"}},
          {"id":"2","technician":{"id":1502,"name":"Anna Schmidt"}},
          {"id":"3","technician":{"id":"1501","name":"Björn Lulay"}},
          {"id":"4","technician":null}
        ],"response_status":[{"status_code":2000,"status":"success"}]}
        """
        let parsed = try ManageEngineAPI.parseTechnicians(Data(json.utf8))
        XCTAssertEqual(parsed.map(\.id), ["1502", "1501"])
        XCTAssertEqual(parsed.last?.email, nil)
    }
}
