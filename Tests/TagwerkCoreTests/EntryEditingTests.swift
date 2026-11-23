import XCTest
@testable import TagwerkCore

final class EntryEditingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: hour, minute: minute))!
    }

    private func entry(_ from: (Int, Int), _ to: (Int, Int)?) -> TimeEntry {
        TimeEntry(taskID: UUID(), start: at(from.0, from.1), end: to.map { at($0.0, $0.1) })
    }

    private lazy var before = entry((8, 0), (9, 0))
    private lazy var edited = entry((9, 30), (11, 0))
    private lazy var after = entry((12, 0), (13, 0))

    private func drag(_ kind: EntryDrag, minutes: Double, now: Date? = nil) -> (start: Date, end: Date?) {
        EntryEditing.dragged(edited, kind, by: minutes * 60, others: [before, edited, after], now: now ?? at(17), calendar: calendar)
    }

    func testMoveKeepsDurationAndSnaps() {
        let moved = drag(.move, minutes: 22)
        XCTAssertEqual(moved.start, at(9, 50))
        XCTAssertEqual(moved.end, at(11, 20))
    }

    func testMoveStopsAtNeighbours() {
        XCTAssertEqual(drag(.move, minutes: -60).start, at(9, 0))
        XCTAssertEqual(drag(.move, minutes: -60).end, at(10, 30))
        XCTAssertEqual(drag(.move, minutes: 120).start, at(10, 30))
        XCTAssertEqual(drag(.move, minutes: 120).end, at(12, 0))
    }

    func testStartEdge() {
        XCTAssertEqual(drag(.start, minutes: 7).start, at(9, 35))
        XCTAssertEqual(drag(.start, minutes: -45).start, at(9, 0), "nicht in den vorigen Eintrag")
        XCTAssertEqual(drag(.start, minutes: 180).start, at(10, 55), "mindestens fünf Minuten bleiben")
        XCTAssertEqual(drag(.start, minutes: 7).end, at(11, 0))
    }

    func testEndEdge() {
        XCTAssertEqual(drag(.end, minutes: 31).end, at(11, 30))
        XCTAssertEqual(drag(.end, minutes: 120).end, at(12, 0), "nicht in den nächsten Eintrag")
        XCTAssertEqual(drag(.end, minutes: -120).end, at(9, 35))
        XCTAssertEqual(drag(.end, minutes: 31).start, at(9, 30))
    }

    func testEndNotInFuture() {
        XCTAssertEqual(drag(.end, minutes: 45, now: at(11, 20)).end, at(11, 20))
    }

    func testRunningEntryOnlyStartMoves() {
        let running = entry((15, 0), nil)
        let now = at(16, 10)
        let others = [before, edited, after, running]
        let earlier = EntryEditing.dragged(running, .start, by: -20 * 60, others: others, now: now, calendar: calendar)
        XCTAssertEqual(earlier.start, at(14, 40))
        XCTAssertNil(earlier.end)
        let moved = EntryEditing.dragged(running, .move, by: -20 * 60, others: others, now: now, calendar: calendar)
        XCTAssertEqual(moved.start, at(15, 0))
        XCTAssertNil(moved.end)
        let tooEarly = EntryEditing.dragged(running, .start, by: -3 * 3600, others: others, now: now, calendar: calendar)
        XCTAssertEqual(tooEarly.start, at(13, 0), "nicht in den vorigen Eintrag")
    }

    func testStaysOnItsDay() {
        let early = entry((0, 20), (1, 0))
        let moved = EntryEditing.dragged(early, .move, by: -60 * 60, others: [early], now: at(17), calendar: calendar)
        XCTAssertEqual(moved.start, at(0, 0))
        XCTAssertEqual(moved.end, at(0, 40))
    }

    func testProblems() {
        let entries = [before, edited, after]
        let now = at(17)
        XCTAssertNil(EntryEditing.problem(start: at(9, 0), end: at(9, 30), excluding: nil, in: entries, now: now))
        XCTAssertEqual(EntryEditing.problem(start: at(10, 0), end: at(9, 0), excluding: nil, in: entries, now: now), .endBeforeStart)
        XCTAssertEqual(EntryEditing.problem(start: at(16, 0), end: at(18, 0), excluding: nil, in: entries, now: now), .inFuture)
        XCTAssertEqual(EntryEditing.problem(start: at(8, 30), end: at(9, 45), excluding: nil, in: entries, now: now), .overlaps(before))
        // Der Eintrag selbst zählt nicht als Überschneidung
        XCTAssertNil(EntryEditing.problem(start: at(9, 15), end: at(11, 30), excluding: edited.id, in: entries, now: now))
        // Sekunden-Überlappung an der Grenze zählt nicht
        XCTAssertNil(EntryEditing.problem(start: at(8, 59).addingTimeInterval(30), end: at(9, 20), excluding: nil, in: entries, now: now))
    }

    func testKeepingSeconds() {
        let exact = at(9, 3).addingTimeInterval(27)
        XCTAssertEqual(EntryEditing.keepingSeconds(at(9, 3), of: exact), exact)
        XCTAssertEqual(EntryEditing.keepingSeconds(at(9, 4), of: exact), at(9, 4))
        XCTAssertEqual(EntryEditing.keepingSeconds(at(9, 4), of: nil), at(9, 4))
    }

    func testNewSlotStartsAtQuarterHour() {
        let slot = EntryEditing.newSlot(near: at(14, 40), entries: [before, edited, after], now: at(17), calendar: calendar)
        XCTAssertEqual(slot.start, at(14, 30))
        XCTAssertEqual(slot.end, at(15, 30))
    }

    func testNewSlotFitsBetweenEntriesAndEndsNow() {
        // zwischen „edited“ (bis 11:00) und „after“ (ab 12:00)
        let between = EntryEditing.newSlot(near: at(11, 40), entries: [before, edited, after], now: at(17), calendar: calendar)
        XCTAssertEqual(between.start, at(11, 30))
        XCTAssertEqual(between.end, at(12, 0))
        let rightAfter = EntryEditing.newSlot(near: at(11, 5), entries: [before, edited, after], now: at(17), calendar: calendar)
        XCTAssertEqual(rightAfter.start, at(11, 0))
        // gerade eben: endet jetzt
        let recent = EntryEditing.newSlot(near: at(16, 50), entries: [before, edited, after], now: at(17, 5), calendar: calendar)
        XCTAssertEqual(recent.start, at(16, 45))
        XCTAssertEqual(recent.end, at(17, 5))
        // Zukunft: volle Stunde
        let later = EntryEditing.newSlot(near: at(19, 10), entries: [before, edited, after], now: at(17), calendar: calendar)
        XCTAssertEqual(later.start, at(19, 0))
        XCTAssertEqual(later.end, at(20, 0))
    }
}
