import XCTest
@testable import TagwerkCore

final class AbsenceTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    // Montag, 23. November 2026
    private let monday = LocalDate(year: 2026, month: 11, day: 23)

    func testWorkdaysSkipWeekends() {
        let days = Absences.workdays(from: monday, through: monday.adding(days: 6, calendar: calendar), calendar: calendar)
        XCTAssertEqual(days.count, 5)
        XCTAssertEqual(days.first, monday)
        XCTAssertEqual(days.last, LocalDate(year: 2026, month: 11, day: 27))
        XCTAssertTrue(Absences.workdays(from: monday.adding(days: 1, calendar: calendar), through: monday, calendar: calendar).isEmpty)
    }

    func testWeeklyGoalShrinksWithAbsences() {
        let absences = [
            Absence(day: monday, kind: .sick),
            Absence(day: monday.adding(days: 2, calendar: calendar), kind: .sick, halfDay: true),
            // Samstag zählt nicht
            Absence(day: monday.adding(days: 5, calendar: calendar), kind: .vacation),
        ]
        XCTAssertEqual(Absences.weeklyGoalMinutes(dailyMinutes: 360, weekStart: monday, absences: [], calendar: calendar), 1800)
        XCTAssertEqual(Absences.weeklyGoalMinutes(dailyMinutes: 360, weekStart: monday, absences: absences, calendar: calendar), 1260)
    }

    func testMakeRangeAndHalfDay() {
        // Donnerstag bis Dienstag: Do, Fr, Mo, Di
        let thursday = monday.adding(days: 3, calendar: calendar)
        let range = Absences.make(kind: .sick, from: thursday, through: thursday.adding(days: 5, calendar: calendar), halfDay: true, calendar: calendar)
        XCTAssertEqual(range.count, 4)
        XCTAssertFalse(range.contains { $0.halfDay }, "halber Tag nur bei einem einzelnen Tag")
        let single = Absences.make(kind: .sick, from: monday, through: monday, halfDay: true, calendar: calendar)
        XCTAssertEqual(single.count, 1)
        XCTAssertTrue(single[0].halfDay)
    }

    func testNextWorkingDaySkipsAbsencesAndWeekend() {
        let friday = monday.adding(days: 4, calendar: calendar)
        let nextMonday = monday.adding(days: 7, calendar: calendar)
        let absences = [Absence(day: nextMonday, kind: .sick)]
        XCTAssertEqual(Absences.nextWorkingDay(after: friday, absences: absences, calendar: calendar), nextMonday.adding(days: 1, calendar: calendar))
        XCTAssertEqual(Absences.nextWorkingDay(after: monday, absences: [], calendar: calendar), monday.adding(days: 1, calendar: calendar))
    }

    func testParseAndSummary() {
        XCTAssertEqual(AbsenceKind.parse("Krank"), .sick)
        XCTAssertEqual(AbsenceKind.parse("krankheit"), .sick)
        XCTAssertEqual(AbsenceKind.parse("Urlaub"), .vacation)
        XCTAssertNil(AbsenceKind.parse("Homeoffice"))
        let summary = Absences.summary([
            Absence(day: monday, kind: .sick),
            Absence(day: monday.adding(days: 1, calendar: calendar), kind: .sick, halfDay: true),
            Absence(day: monday.adding(days: 2, calendar: calendar), kind: .vacation),
        ])
        XCTAssertEqual(summary, "1,5 Tage krank, 1 Tag Urlaub")
        XCTAssertNil(Absences.summary([]))
    }

    func testStoredInSQLite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("absence-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try SQLiteStore(url: url)
        let absence = Absence(day: monday, kind: .sick, halfDay: true, note: "Erkältung", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(absence)
        XCTAssertEqual(try store.load().absences, [absence])
        try store.deleteAbsence(id: absence.id)
        XCTAssertTrue(try store.load().absences.isEmpty)
    }
}
