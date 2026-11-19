import Foundation
import TagwerkCore
@testable import TagwerkMCP
import XCTest

final class MCPServerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Donnerstag, 19.11.2026, 10:00 in Berlin
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
    }

    private func makeServer(_ snapshot: Snapshot = Snapshot(), clock: (() -> Date)? = nil) -> (MCPServer, InMemoryStore) {
        let store = InMemoryStore(snapshot)
        let fixed = now
        let tools = TagwerkTools(store: store, calendar: calendar, now: clock ?? { fixed })
        return (MCPServer(tools: tools), store)
    }

    private func send(_ server: MCPServer, _ message: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: message)
        let line = String(decoding: data, as: UTF8.self)
        let response = try XCTUnwrap(server.handle(line: line))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    }

    /// Ruft ein Werkzeug auf und gibt den Text der Antwort als JSON zurück.
    private func call(_ server: MCPServer, _ name: String, _ arguments: [String: Any] = [:]) throws -> (json: [String: Any], isError: Bool, text: String) {
        let response = try send(server, ["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": ["name": name, "arguments": arguments]])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        return (json, result["isError"] as? Bool ?? false, text)
    }

    func testInitializeEchoesSupportedVersion() throws {
        let (server, _) = makeServer()
        let response = try send(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]]])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "tagwerk")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual(response["id"] as? Int, 1)
    }

    func testUnknownVersionFallsBackToDefault() throws {
        let (server, _) = makeServer()
        let response = try send(server, ["jsonrpc": "2.0", "id": "a", "method": "initialize", "params": ["protocolVersion": "1999-01-01"]])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, MCPServer.defaultVersion)
        XCTAssertEqual(response["id"] as? String, "a")
    }

    func testNotificationsGetNoAnswer() {
        let (server, _) = makeServer()
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testErrors() throws {
        let (server, _) = makeServer()
        let unknown = try send(server, ["jsonrpc": "2.0", "id": 2, "method": "resources/list"])
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)

        let parse = try XCTUnwrap(server.handle(line: "{kaputt"))
        XCTAssertTrue(parse.contains("-32700"))

        let tool = try send(server, ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "gibtsnicht"]])
        XCTAssertEqual((tool["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testToolsListHasSchemas() throws {
        let (server, _) = makeServer()
        let response = try send(server, ["jsonrpc": "2.0", "id": 4, "method": "tools/list"])
        let tools = try XCTUnwrap((response["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let names = tools.compactMap { $0["name"] as? String }
        XCTAssertTrue(names.contains("tagesuebersicht"))
        XCTAssertTrue(names.contains("aufgabe_anlegen"))
        XCTAssertTrue(names.contains("timer_starten"))
        for tool in tools {
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object")
        }
    }

    func testAddTaskThenSeeItToday() throws {
        let customer = Customer(name: "Müller Logistik", colorIndex: 1)
        let (server, store) = makeServer(Snapshot(customers: [customer]))

        let added = try call(server, "aufgabe_anlegen", ["titel": "Backup prüfen 45m", "kunde": "müller", "datum": "heute", "arbeitsart": "Wartung"])
        XCTAssertFalse(added.isError, added.text)
        let task = try XCTUnwrap(try store.load().tasks.first)
        XCTAssertEqual(task.title, "Backup prüfen")
        XCTAssertEqual(task.estimateMinutes, 45)
        XCTAssertEqual(task.customerID, customer.id)
        XCTAssertEqual(task.workType, .wartung)
        XCTAssertEqual(task.plannedDate, LocalDate(year: 2026, month: 11, day: 19))

        let overview = try call(server, "tagesuebersicht")
        let tasks = try XCTUnwrap(overview.json["aufgaben"] as? [[String: Any]])
        XCTAssertEqual(tasks.first?["titel"] as? String, "Backup prüfen")
        XCTAssertEqual(tasks.first?["kunde"] as? String, "Müller Logistik")
        XCTAssertEqual(overview.json["geplant_min"] as? Int, 45)
    }

    func testTaskWithoutDateGoesToInbox() throws {
        let (server, store) = makeServer()
        _ = try call(server, "aufgabe_anlegen", ["titel": "Angebot lesen"])
        XCTAssertNil(try store.load().tasks.first?.plannedDate)
        let inbox = try call(server, "aufgaben", ["eingang": true])
        XCTAssertEqual(inbox.json["anzahl"] as? Int, 1)
    }

    func testUnknownCustomerIsAnError() throws {
        let (server, _) = makeServer(Snapshot(customers: [Customer(name: "Stadtwerke Nord", colorIndex: 0)]))
        let result = try call(server, "aufgabe_anlegen", ["titel": "x", "kunde": "Becker"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Stadtwerke Nord"))
    }

    func testUpdateTaskByShortID() throws {
        let task = TaskItem(title: "Server tauschen", plannedDate: LocalDate(year: 2026, month: 11, day: 19))
        let (server, store) = makeServer(Snapshot(tasks: [task]))
        let shortID = String(task.id.uuidString.prefix(8))
        let result = try call(server, "aufgabe_aendern", ["id": shortID, "psp": "CPSO8643-12", "beschreibung": "Platten getauscht", "datum": "eingang", "erledigt": true])
        XCTAssertFalse(result.isError, result.text)
        let saved = try XCTUnwrap(try store.load().tasks.first)
        XCTAssertEqual(saved.pspElement, "CPSO8643-12")
        XCTAssertEqual(saved.workDescription, "Platten getauscht")
        XCTAssertNil(saved.plannedDate)
        XCTAssertTrue(saved.isDone)
    }

    func testTimerStartAndStop() throws {
        let task = TaskItem(title: "Störung VPN")
        var current = now
        let (server, store) = makeServer(Snapshot(tasks: [task]), clock: { current })

        let started = try call(server, "timer_starten", ["id": task.id.uuidString])
        XCTAssertFalse(started.isError, started.text)
        XCTAssertNotNil(TimerLogic.running(in: try store.load().entries))

        current = now.addingTimeInterval(25 * 60)
        let stopped = try call(server, "timer_stoppen")
        XCTAssertEqual(stopped.json["minuten"] as? Int, 25)
        let entries = try store.load().entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(TimerLogic.running(in: entries))

        let again = try call(server, "timer_stoppen")
        XCTAssertNotNil(again.json["meldung"])
    }

    func testTimeReportSumsPerCustomer() throws {
        let customer = Customer(name: "Becker & Partner", colorIndex: 2)
        let task = TaskItem(title: "Beratung", customerID: customer.id, workType: .beratung, pspElement: "CPSO8643-1")
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))!
        let entries = [
            TimeEntry(taskID: task.id, start: monday, end: monday.addingTimeInterval(90 * 60)),
            TimeEntry(taskID: task.id, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800)),
            // Vorwoche, zählt nicht
            TimeEntry(taskID: task.id, start: monday.addingTimeInterval(-7 * 86400), end: monday.addingTimeInterval(-7 * 86400 + 3600)),
        ]
        let (server, _) = makeServer(Snapshot(customers: [customer], tasks: [task], entries: entries))
        let report = try call(server, "zeitauswertung")
        XCTAssertEqual(report.json["von"] as? String, "2026-11-16")
        XCTAssertEqual(report.json["bis"] as? String, "2026-11-22")
        XCTAssertEqual(report.json["summe_min"] as? Int, 120)
        let perCustomer = try XCTUnwrap(report.json["je_kunde"] as? [[String: Any]])
        XCTAssertEqual(perCustomer.first?["kunde"] as? String, "Becker & Partner")
        let perPSP = try XCTUnwrap(report.json["je_psp"] as? [[String: Any]])
        XCTAssertEqual(perPSP.first?["psp"] as? String, "CPSO8643-1")
    }

    func testDayCloseShowsMissingFields() throws {
        let task = TaskItem(title: "Ticket 4711", source: .ticket, externalID: "4711")
        let entry = TimeEntry(taskID: task.id, start: now.addingTimeInterval(-40 * 60), end: now.addingTimeInterval(-10 * 60))
        let (server, _) = makeServer(Snapshot(tasks: [task], entries: [entry]))
        let close = try call(server, "tagesabschluss")
        let lines = try XCTUnwrap(close.json["zeilen"] as? [[String: Any]])
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?["minuten"] as? Int, 30)
        let missing = try XCTUnwrap(lines.first?["fehlt"] as? [String])
        XCTAssertTrue(missing.contains(BookingIssue.missingPSP.message))
        XCTAssertEqual(close.json["offen_manageengine"] as? Int, 1)
    }

    func testDateParsing() throws {
        let tools = TagwerkTools(store: InMemoryStore(), calendar: calendar, now: { [now] in now })
        XCTAssertEqual(try tools.parseDay("morgen"), LocalDate(year: 2026, month: 11, day: 20))
        XCTAssertEqual(try tools.parseDay("2026-12-01"), LocalDate(year: 2026, month: 12, day: 1))
        XCTAssertEqual(try tools.parseDay("24.12.2026"), LocalDate(year: 2026, month: 12, day: 24))
        XCTAssertEqual(try tools.parseDay("3.1."), LocalDate(year: 2026, month: 1, day: 3))
        XCTAssertNil(try tools.parseDay(nil))
        XCTAssertThrowsError(try tools.parseDay("irgendwann"))
    }

    func testWeeklyGoal() throws {
        let (server, store) = makeServer()
        _ = try call(server, "wochenziel_anlegen", ["titel": "Migration abschließen"])
        let goal = try XCTUnwrap(try store.load().goals.first)
        XCTAssertEqual(goal.weekStart, LocalDate(year: 2026, month: 11, day: 16))
        let goals = try call(server, "wochenziele")
        XCTAssertEqual((goals.json["ziele"] as? [[String: Any]])?.count, 1)
    }
}
