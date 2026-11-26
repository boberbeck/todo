import XCTest
@testable import TagwerkCore

final class QuickCommandTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    // Dienstag, 24. November 2026, 14:00
    private let today = LocalDate(year: 2026, month: 11, day: 24)
    private var now: Date { at(14) }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        today.startDate(calendar: calendar).addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
    }

    private let mueller = Customer(name: "Müller Logistik")
    private lazy var vpn = TaskItem(title: "VPN-Störung prüfen", customerID: mueller.id, plannedDate: today, sortIndex: 1)
    private lazy var offer = TaskItem(title: "Angebot Wartungsvertrag", plannedDate: today, sortIndex: 2)
    private let organisation = TaskItem(title: "Organisatorisches", sortIndex: 1, isStanding: true)
    private let done = TaskItem(title: "VPN Altlast", status: .done)

    private func context(running: UUID? = nil, lunch: Bool = false) -> CommandContext {
        CommandContext(
            tasks: [vpn, offer, organisation, done],
            customers: [mueller],
            today: today,
            runningTaskID: running,
            lunchRunning: lunch,
            now: now,
            calendar: calendar
        )
    }

    private func actions(_ query: String, running: UUID? = nil, lunch: Bool = false) -> [CommandAction] {
        QuickCommand.suggestions(for: query, in: context(running: running, lunch: lunch)).map(\.action)
    }

    // MARK: Bausteine

    func testLeadingDuration() {
        XCTAssertEqual(QuickCommand.leadingDuration("45m Telefonat Müller")?.minutes, 45)
        XCTAssertEqual(QuickCommand.leadingDuration("45m Telefonat Müller")?.rest, "Telefonat Müller")
        XCTAssertEqual(QuickCommand.leadingDuration("1h30 Doku")?.minutes, 90)
        XCTAssertEqual(QuickCommand.leadingDuration("1,5 h Review")?.minutes, 90)
        XCTAssertEqual(QuickCommand.leadingDuration("90 Minuten Workshop")?.minutes, 90)
        XCTAssertEqual(QuickCommand.leadingDuration("0:45 Call")?.minutes, 45)
        XCTAssertNil(QuickCommand.leadingDuration("9:30 Angebot"), "das ist eine Uhrzeit")
        XCTAssertNil(QuickCommand.leadingDuration("VPN prüfen"))
        XCTAssertNil(QuickCommand.leadingDuration("Team Sitzung"))
        XCTAssertNil(QuickCommand.leadingDuration("Monatsbericht schreiben"))
    }

    func testSinceTime() {
        let since = QuickCommand.sinceTime("seit 9:30 Angebot", on: today, calendar: calendar)
        XCTAssertEqual(since?.date, at(9, 30))
        XCTAssertEqual(since?.rest, "Angebot")
        let later = QuickCommand.sinceTime("ab 14 Uhr Workshop", on: today, calendar: calendar)
        XCTAssertEqual(later?.date, at(14))
        XCTAssertEqual(later?.rest, "Workshop")
        XCTAssertEqual(QuickCommand.sinceTime("9.15 Doku", on: today, calendar: calendar)?.date, at(9, 15))
        XCTAssertEqual(QuickCommand.sinceTime("seit 930 Doku", on: today, calendar: calendar)?.date, at(9, 30))
        XCTAssertNil(QuickCommand.sinceTime("1:30 Doku", on: today, calendar: calendar), "ohne „seit“ eine Dauer")
        XCTAssertNil(QuickCommand.sinceTime("14 Workshop", on: today, calendar: calendar), "Zahl ohne „seit“ ist keine Uhrzeit")
    }

    func testPlannedDays() {
        let tomorrow = QuickCommand.planned("morgen Rechnung prüfen 30m", today: today, calendar: calendar)
        XCTAssertEqual(tomorrow?.day, LocalDate(year: 2026, month: 11, day: 25))
        XCTAssertEqual(tomorrow?.rest, "Rechnung prüfen 30m")
        XCTAssertEqual(QuickCommand.planned("+ Angebot", today: today, calendar: calendar)?.day, today)
        let later = QuickCommand.planned("später Idee sammeln", today: today, calendar: calendar)
        XCTAssertNotNil(later)
        XCTAssertNil(later?.day ?? nil, "später = Eingang")
        XCTAssertEqual(QuickCommand.planned("Freitag Bericht", today: today, calendar: calendar)?.day, LocalDate(year: 2026, month: 11, day: 27))
        XCTAssertEqual(QuickCommand.planned("dienstag Bericht", today: today, calendar: calendar)?.day, LocalDate(year: 2026, month: 12, day: 1), "heute ist Dienstag: nächste Woche")
        XCTAssertEqual(QuickCommand.planned("neue Aufgabe Server prüfen", today: today, calendar: calendar)?.rest, "Server prüfen")
        XCTAssertNil(QuickCommand.planned("Angebot", today: today, calendar: calendar))
    }

    func testMatchScore() {
        XCTAssertEqual(QuickCommand.matchScore(title: "VPN-Störung prüfen", query: "vpn"), 85)
        XCTAssertEqual(QuickCommand.matchScore(title: "VPN-Störung prüfen", query: "stör"), 70)
        XCTAssertEqual(QuickCommand.matchScore(title: "VPN-Störung prüfen", query: "prüfen vpn"), 60)
        XCTAssertEqual(QuickCommand.matchScore(title: "Organisatorisches", query: "ORGANISATORISCHES"), 100)
        XCTAssertNil(QuickCommand.matchScore(title: "VPN-Störung prüfen", query: "xyz"))
    }

    // MARK: Vorschläge

    func testStartsExistingTask() {
        XCTAssertEqual(actions("vpn").first, .start(vpn.id))
        XCTAssertFalse(actions("vpn").contains(.start(done.id)), "Erledigtes wird nicht vorgeschlagen")
        XCTAssertEqual(actions("orga").first, .start(organisation.id), "Standardaufgaben gehören dazu")
        XCTAssertEqual(actions("vpn", running: vpn.id).first, .focus(vpn.id), "läuft schon: Fokus statt Neustart")
    }

    func testLogsTimeUntilNow() {
        XCTAssertEqual(actions("45m Telefonat Müller").first, .log(taskID: nil, title: "Telefonat Müller", customerID: mueller.id, minutes: 45))
        XCTAssertEqual(actions("30m vpn").first, .log(taskID: vpn.id, title: vpn.title, customerID: nil, minutes: 30))
        let suggestion = QuickCommand.suggestions(for: "45m Telefonat Müller", in: context()).first
        XCTAssertEqual(suggestion?.detail.hasPrefix("13:15–14:00"), true, suggestion?.detail ?? "")
        XCTAssertFalse(actions("12h Schlafen").contains { if case .log = $0 { return true } else { return false } }, "mehr als 8 Stunden nicht")
    }

    func testStartsSince() {
        XCTAssertEqual(actions("seit 9:30 Angebot").first, .startSince(taskID: offer.id, title: offer.title, customerID: nil, since: at(9, 30)))
        XCTAssertEqual(actions("seit 13 Uhr Doku").first, .startSince(taskID: nil, title: "Doku", customerID: nil, since: at(13)))
        XCTAssertFalse(actions("seit 16 Uhr Doku").contains { if case .startSince = $0 { return true } else { return false } }, "nicht in der Zukunft")
    }

    func testAddsPlannedTask() {
        XCTAssertEqual(actions("morgen Rechnung prüfen 30m").first,
                       .add(title: "Rechnung prüfen", customerID: nil, day: LocalDate(year: 2026, month: 11, day: 25), estimateMinutes: 30))
        XCTAssertEqual(actions("später Idee für Müller").first, .add(title: "Idee für Müller", customerID: mueller.id, day: nil, estimateMinutes: nil))
    }

    func testKeywords() {
        XCTAssertEqual(actions("fertig", running: vpn.id).first, .complete(vpn.id))
        XCTAssertEqual(actions("stopp", running: vpn.id).first, .stop)
        XCTAssertEqual(actions("mittag").first, .startLunch)
        XCTAssertEqual(actions("weiter", lunch: true).first, .endLunch)
        XCTAssertFalse(actions("fertig").contains(.stop), "ohne laufenden Timer nichts zu stoppen")
        XCTAssertFalse(actions("fertig", running: organisation.id).contains(.complete(organisation.id)), "Standardaufgaben werden nie erledigt")
    }

    func testNavigation() {
        XCTAssertTrue(actions("kalender").contains(.open(.calendar)))
        XCTAssertTrue(actions("feierabend").contains(.open(.close)))
        XCTAssertTrue(actions("rückblick").contains(.open(.review)))
        XCTAssertFalse(actions("kalender").contains { if case .startNew = $0 { return true } else { return false } }, "Seitennamen sind keine neuen Aufgaben")
    }

    func testFreeTextCreatesTask() {
        let result = actions("Doku schreiben")
        XCTAssertEqual(result.first, .startNew(title: "Doku schreiben", customerID: nil))
        XCTAssertTrue(result.contains(.add(title: "Doku schreiben", customerID: nil, day: today, estimateMinutes: nil)))
        XCTAssertEqual(actions("telefonat müller").first, .startNew(title: "Telefonat müller", customerID: mueller.id))
    }

    func testAbsenceParsing() {
        let parse = { (text: String) in QuickCommand.absence(text, today: self.today, calendar: self.calendar) }
        XCTAssertEqual(parse("krank")?.from, today)
        XCTAssertEqual(parse("krank")?.through, today)
        XCTAssertEqual(parse("krank")?.kind, .sick)
        XCTAssertEqual(parse("heute halber Tag krank")?.halfDay, true)
        XCTAssertEqual(parse("krank bis Freitag")?.through, LocalDate(year: 2026, month: 11, day: 27))
        XCTAssertEqual(parse("Urlaub morgen")?.from, LocalDate(year: 2026, month: 11, day: 25))
        XCTAssertEqual(parse("Urlaub morgen")?.kind, .vacation)
        let week = parse("Urlaub von Montag bis Freitag")
        XCTAssertEqual(week?.from, LocalDate(year: 2026, month: 11, day: 30))
        XCTAssertEqual(week?.through, LocalDate(year: 2026, month: 12, day: 4))
        XCTAssertEqual(parse("krank 3 Tage")?.through, LocalDate(year: 2026, month: 11, day: 26))
        XCTAssertEqual(parse("Urlaub 28.12. bis 2.1.")?.through, LocalDate(year: 2027, month: 1, day: 2))
        XCTAssertEqual(parse("halber Tag krank bis Freitag")?.halfDay, false, "halber Tag nur bei einem Tag")
        XCTAssertNil(parse("Angebot schreiben"))
    }

    func testAbsenceSuggestions() {
        XCTAssertEqual(actions("krank").first, .absent(kind: .sick, from: today, through: today, halfDay: false))
        XCTAssertTrue(actions("krank").contains(.absenceForm(.sick)))
        XCTAssertFalse(actions("krank").contains { if case .startNew = $0 { return true } else { return false } })
        XCTAssertEqual(QuickCommand.suggestions(for: "krank", in: context()).first?.title, "Heute krank eintragen")
        XCTAssertEqual(QuickCommand.suggestions(for: "krank bis freitag", in: context()).first?.detail.hasPrefix("4 Arbeitstage"), true)
        XCTAssertFalse(actions("Freitag krank").contains { if case .add = $0 { return true } else { return false } }, "kein „Krank“ als Aufgabe")
        // Morgens ohne erfasste Zeit steht „Heute krank“ schon ohne Eingabe da
        let morning = CommandContext(tasks: [vpn], customers: [], today: today, runningTaskID: nil, lunchRunning: false, now: now, calendar: calendar)
        XCTAssertTrue(QuickCommand.suggestions(for: "", in: morning).map(\.action).contains(.absent(kind: .sick, from: today, through: today, halfDay: false)))
        let working = CommandContext(tasks: [vpn], customers: [], today: today, runningTaskID: nil, lunchRunning: false, now: now, calendar: calendar, trackedTodaySeconds: 3600)
        XCTAssertFalse(QuickCommand.suggestions(for: "", in: working).map(\.action).contains(.absent(kind: .sick, from: today, through: today, halfDay: false)))
    }

    func testSwitchesRunningTask() {
        // Läuft die falsche Aufgabe, bietet der beste Treffer auch „Zeit umhängen“ an
        XCTAssertTrue(actions("angebot", running: vpn.id).contains(.switchRunning(offer.id)))
        XCTAssertFalse(actions("angebot").contains(.switchRunning(offer.id)), "ohne laufenden Timer nichts umzuhängen")
        XCTAssertEqual(actions("wechseln zu angebot", running: vpn.id).first, .switchRunning(offer.id))
        XCTAssertEqual(actions("eigentlich orga", running: vpn.id).first, .switchRunning(organisation.id))
        XCTAssertFalse(actions("wechseln zu vpn", running: vpn.id).contains(.switchRunning(vpn.id)), "nicht auf sich selbst")
        XCTAssertFalse(actions("wechseln zu angebot", running: vpn.id).contains { if case .startNew = $0 { return true } else { return false } })
        XCTAssertEqual(QuickCommand.switchRest("umhängen auf Angebot"), "Angebot")
        XCTAssertEqual(QuickCommand.switchRest("Wechseln Doku"), "Doku")
        XCTAssertNil(QuickCommand.switchRest("wechseln"))
        XCTAssertNil(QuickCommand.switchRest("Angebot wechseln"))
    }

    func testIdleSuggestions() {
        let idle = actions("", running: vpn.id)
        XCTAssertEqual(idle.first, .complete(vpn.id))
        XCTAssertTrue(idle.contains(.stop))
        XCTAssertTrue(idle.contains(.startLunch))
        XCTAssertTrue(idle.contains(.start(offer.id)))
        XCTAssertTrue(idle.contains(.start(organisation.id)))
        XCTAssertFalse(idle.contains(.start(vpn.id)))
        XCTAssertEqual(actions("", lunch: true).first, .endLunch)
        XCTAssertLessThanOrEqual(QuickCommand.suggestions(for: "", in: context(running: vpn.id)).count, 8)
    }
}

final class TimerSwitchTests: XCTestCase {
    func testReassignMovesRunningEntryWithItsTime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let wrong = UUID()
        let right = UUID()
        let earlier = TimeEntry(taskID: wrong, start: start.addingTimeInterval(-3600), end: start.addingTimeInterval(-1800))
        let running = TimeEntry(taskID: wrong, start: start)
        let moved = TimerLogic.reassignRunning(to: right, entries: [earlier, running])
        XCTAssertEqual(moved?.id, running.id, "derselbe Eintrag, nur die Aufgabe ändert sich")
        XCTAssertEqual(moved?.taskID, right)
        XCTAssertEqual(moved?.start, start, "die Zeit seit dem Start wandert mit")
        XCTAssertNil(moved?.end, "läuft weiter")
        XCTAssertNil(TimerLogic.reassignRunning(to: wrong, entries: [earlier, running]), "schon die richtige Aufgabe")
        XCTAssertNil(TimerLogic.reassignRunning(to: right, entries: [earlier]), "nichts läuft")
    }
}
