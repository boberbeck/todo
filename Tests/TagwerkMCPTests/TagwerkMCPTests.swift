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

final class MCPSubtaskTests: XCTestCase {
    func testSubtaskWithTicketAndActivity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
        let ticket = TaskItem(title: "VPN", source: .ticket, externalID: "1240", externalKey: "100124")
        let parent = TaskItem(title: "Firewall-Umzug", plannedDate: LocalDate(year: 2026, month: 11, day: 19))
        let store = InMemoryStore(Snapshot(tasks: [ticket, parent]))
        let tools = TagwerkTools(store: store, calendar: calendar, now: { now })

        let text = try tools.call(name: "aufgabe_anlegen", arguments: [
            "titel": "Regeln exportieren",
            "unteraufgabe_von": String(parent.id.uuidString.prefix(8)),
            "ticket": "#1240",
            "psp": "CPSO8643-6",
            "taetigkeit": "Consulting",
        ])
        let subtask = try XCTUnwrap(try store.load().tasks.first { $0.title == "Regeln exportieren" })
        XCTAssertEqual(subtask.parentID, parent.id)
        XCTAssertNil(subtask.plannedDate)
        XCTAssertEqual(subtask.ticketNumber, "1240")
        XCTAssertEqual(subtask.ticketKey, "100124", "interne ID vom Ticket in Tagwerk")
        XCTAssertEqual(subtask.sapActivity, "Consulting")
        XCTAssertTrue(text.contains("unteraufgabe_von"), text)

        let inbox = try tools.call(name: "aufgaben", arguments: ["eingang": true])
        XCTAssertFalse(inbox.contains("Regeln exportieren"), "Unteraufgaben stehen nicht im Eingang")

        _ = try tools.call(name: "aufgabe_aendern", arguments: ["id": String(subtask.id.uuidString.prefix(8)), "ticket": ""])
        XCTAssertNil(try store.load().tasks.first { $0.id == subtask.id }?.ticketNumber)
    }
}

final class MCPLongGoalTests: XCTestCase {
    func testCreateGoalAndAssignTask() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
        let store = InMemoryStore()
        let tools = TagwerkTools(store: store, calendar: calendar, now: { now })

        _ = try tools.call(name: "ziel_anlegen", arguments: ["titel": "AZ-305 bestehen", "bis": "2027-01-15", "stunden": 40])
        let goal = try XCTUnwrap(try store.load().longGoals.first)
        XCTAssertEqual(goal.dueDate, LocalDate(year: 2027, month: 1, day: 15))
        XCTAssertEqual(goal.targetMinutes, 2400)

        _ = try tools.call(name: "aufgabe_anlegen", arguments: ["titel": "Modul 1 lernen 1h30", "ziel": "az-305"])
        let task = try XCTUnwrap(try store.load().tasks.first)
        XCTAssertEqual(task.longGoalID, goal.id)

        let list = try tools.call(name: "ziele", arguments: [:])
        XCTAssertTrue(list.contains("Modul 1 lernen"), list)
        XCTAssertTrue(list.contains("noetig_pro_woche_min"), list)

        _ = try tools.call(name: "aufgabe_aendern", arguments: ["id": String(task.id.uuidString.prefix(8)), "ziel": ""])
        XCTAssertNil(try store.load().tasks.first?.longGoalID)
        XCTAssertThrowsError(try tools.call(name: "aufgabe_aendern", arguments: ["id": String(task.id.uuidString.prefix(8)), "ziel": "Gibt es nicht"]))
    }
}

/// MCP über HTTP für Claude im Browser und auf dem Handy.
final class MCPHTTPTests: XCTestCase {
    private let token = "geheim-0123456789abcdef"

    private func handler() -> (MCPHTTPHandler, InMemoryStore) {
        let store = InMemoryStore()
        let tools = TagwerkTools(store: store, calendar: Calendar(identifier: .gregorian), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        return (MCPHTTPHandler(server: MCPServer(tools: tools), token: token), store)
    }

    func testParsesRequestOnlyWhenComplete() {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let raw = "POST /mcp/abc?x=1 HTTP/1.1\r\nHost: tagwerk\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let data = Data(raw.utf8)
        XCTAssertNil(HTTPRequest.parse(data.dropLast(5)), "Inhalt noch nicht vollständig")
        let request = HTTPRequest.parse(data)
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/mcp/abc")
        XCTAssertEqual(request?.headers["content-type"], "application/json")
        XCTAssertEqual(request.map { String(decoding: $0.body, as: UTF8.self) }, body)
    }

    func testAnswersOnlyWithToken() throws {
        let (handler, store) = handler()
        let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#
        XCTAssertEqual(handler.respond(to: HTTPRequest(method: "POST", path: "/mcp/falsch", body: Data(initialize.utf8))).status, 404)
        XCTAssertEqual(handler.respond(to: HTTPRequest(method: "POST", path: "/", body: Data(initialize.utf8))).status, 404)

        let path = MCPHTTPHandler.path(token: token)
        let response = handler.respond(to: HTTPRequest(method: "POST", path: path + "/", body: Data(initialize.utf8)))
        XCTAssertEqual(response.status, 200)
        XCTAssertNotNil(response.headers["Mcp-Session-Id"])
        XCTAssertTrue(String(decoding: response.body, as: UTF8.self).contains("2025-06-18"))

        let notification = handler.respond(to: HTTPRequest(method: "POST", path: path, body: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)))
        XCTAssertEqual(notification.status, 202)
        XCTAssertEqual(handler.respond(to: HTTPRequest(method: "GET", path: path)).status, 405)
        XCTAssertEqual(handler.respond(to: HTTPRequest(method: "POST", path: path, body: Data("kein json".utf8))).status, 400)

        let call = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"aufgabe_anlegen","arguments":{"titel":"Vom Handy"}}}"#
        XCTAssertEqual(handler.respond(to: HTTPRequest(method: "POST", path: path, body: Data(call.utf8))).status, 200)
        XCTAssertEqual(try store.load().tasks.first?.title, "Vom Handy")
    }

    func testResponseFormat() {
        let text = String(decoding: HTTPResponse(status: 202).serialized(), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 202 Accepted\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 0\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"))
    }
}


final class MCPEntityTests: XCTestCase {
    func testHTMLEntitiesBecomeCharacters() throws {
        let store = InMemoryStore()
        let tools = TagwerkTools(store: store)
        _ = try tools.call(name: "aufgabe_anlegen", arguments: ["titel": "Konfiguration nach environments/&lt;env&gt;/ &amp; Modul"])
        XCTAssertEqual(try store.load().tasks.first?.title, "Konfiguration nach environments/<env>/ & Modul")
    }
}

/// Krank- und Urlaubstage über Claude
final class MCPAbsenceTests: XCTestCase {
    func testSickDayMovesOpenTasks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // Freitag, 27. November 2026
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 8))!
        let friday = LocalDate(year: 2026, month: 11, day: 27)
        let task = TaskItem(title: "Angebot schreiben", plannedDate: friday)
        let store = InMemoryStore(Snapshot(tasks: [task]))
        let tools = TagwerkTools(store: store, calendar: calendar, now: { now })

        let answer = try tools.call(name: "abwesenheit_eintragen", arguments: ["art": "krank"])
        XCTAssertTrue(answer.contains("Krank"), answer)
        let snapshot = try store.load()
        XCTAssertEqual(snapshot.absences.map(\.day), [friday])
        // auf Montag verschoben, nicht aufs Wochenende
        XCTAssertEqual(snapshot.tasks.first?.plannedDate, LocalDate(year: 2026, month: 11, day: 30))

        let list = try tools.call(name: "abwesenheiten", arguments: [:])
        XCTAssertTrue(list.contains("1 Tag krank"), list)

        _ = try tools.call(name: "abwesenheit_entfernen", arguments: ["datum": "heute"])
        XCTAssertTrue(try store.load().absences.isEmpty)
        XCTAssertThrowsError(try tools.call(name: "abwesenheit_eintragen", arguments: ["art": "homeoffice"]))
    }
}

final class MCPBreakTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    func testBreakStopsTimerAndResumes() throws {
        var now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!
        let task = TaskItem(title: "Angebot schreiben", plannedDate: LocalDate(year: 2026, month: 11, day: 24))
        let running = TimeEntry(taskID: task.id, start: now.addingTimeInterval(-3600))
        let store = InMemoryStore(Snapshot(tasks: [task], entries: [running]))
        let tools = TagwerkTools(store: store, calendar: calendar, now: { now })

        let started = try tools.call(name: "pause_starten", arguments: [:])
        XCTAssertTrue(started.contains("Angebot schreiben"), started)
        XCTAssertNil(TimerLogic.running(in: try store.load().entries))
        XCTAssertNotNil(Breaks.running(in: try store.load().breaks))

        now = now.addingTimeInterval(30 * 60)
        let ended = try tools.call(name: "pause_beenden", arguments: [:])
        XCTAssertTrue(ended.contains("Angebot schreiben"), ended)
        let snapshot = try store.load()
        XCTAssertNil(Breaks.running(in: snapshot.breaks))
        XCTAssertEqual(TimerLogic.running(in: snapshot.entries)?.taskID, task.id)

        let overview = try tools.call(name: "tagesuebersicht", arguments: [:])
        XCTAssertTrue(overview.contains("pause_min"), overview)
    }

    func testAddingBreakCutsWork() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 15))!
        let day = LocalDate(year: 2026, month: 11, day: 24)
        let task = TaskItem(title: "Server", plannedDate: day)
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 11))!
        let entry = TimeEntry(taskID: task.id, start: start, end: start.addingTimeInterval(3 * 3600))
        let store = InMemoryStore(Snapshot(tasks: [task], entries: [entry]))
        let tools = TagwerkTools(store: store, calendar: calendar, now: { now })

        let answer = try tools.call(name: "pause_eintragen", arguments: ["von": "12:00", "dauer_min": 30])
        XCTAssertTrue(answer.contains("angepasste_zeiteintraege"), answer)
        let snapshot = try store.load()
        XCTAssertEqual(snapshot.breaks.count, 1)
        XCTAssertEqual(snapshot.entries.count, 2)
        XCTAssertEqual(TimeMath.tracked(on: day, entries: snapshot.entries, now: now, calendar: calendar), 2.5 * 3600)
        XCTAssertThrowsError(try tools.call(name: "pause_eintragen", arguments: ["von": "25:00", "bis": "26:00"]))
        XCTAssertThrowsError(try tools.call(name: "pause_eintragen", arguments: ["von": "16:00", "bis": "17:00"]))
        XCTAssertEqual(try tools.clockTime("1230", on: day), calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12, minute: 30)))
        XCTAssertEqual(try tools.clockTime("9 Uhr", on: day), calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 9)))
    }

    func testStandingTasks() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 9))!
        let store = InMemoryStore()
        let tools = TagwerkTools(store: store, calendar: calendar, now: { now })
        let answer = try tools.call(name: "standardaufgaben", arguments: ["anlegen": "Organisatorisches"])
        XCTAssertTrue(answer.contains("Standardaufgabe"), answer)
        let task = try XCTUnwrap(try store.load().tasks.first)
        XCTAssertTrue(task.isStanding)
        // zweimal anlegen: bleibt eine
        _ = try tools.call(name: "standardaufgaben", arguments: ["anlegen": "organisatorisches"])
        XCTAssertEqual(try store.load().tasks.count, 1)
        XCTAssertThrowsError(try tools.call(name: "aufgabe_aendern", arguments: ["id": String(task.id.uuidString.prefix(8)), "erledigt": true]))
        let inbox = try tools.call(name: "aufgaben", arguments: ["eingang": true])
        XCTAssertFalse(inbox.contains("Organisatorisches"), inbox)
    }
}
