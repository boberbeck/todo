import Foundation

/// Ein Termin aus dem Kalender, unabhängig von EventKit.
public struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// eindeutig je Vorkommen (auch bei Serienterminen)
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var calendarTitle: String
    /// `false` = nur als „belegt“ zeigen (z. B. private Termine)
    public var showsTitle: Bool

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String = "",
        calendarTitle: String = "",
        showsTitle: Bool = true
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = max(end, start)
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.showsTitle = showsTitle
    }

    public var interval: DateInterval { DateInterval(start: start, end: end) }

    public var minutes: Int { Int(end.timeIntervalSince(start) / 60) }

    public var displayTitle: String {
        showsTitle ? (title.isEmpty ? "Termin" : title) : "belegt"
    }
}

/// Arbeitszeit eines Tages, in Minuten nach Mitternacht.
public struct Workday: Equatable, Codable, Sendable {
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int = 8 * 60, endMinutes: Int = 17 * 60) {
        self.startMinutes = min(max(0, startMinutes), 24 * 60)
        self.endMinutes = min(max(self.startMinutes, endMinutes), 24 * 60)
    }

    public var durationMinutes: Int { endMinutes - startMinutes }

    public func interval(on day: LocalDate, calendar: Calendar = .current) -> DateInterval {
        let start = FreeTime.date(on: day, minutes: startMinutes, calendar: calendar)
        let end = FreeTime.date(on: day, minutes: endMinutes, calendar: calendar)
        return DateInterval(start: start, end: max(start, end))
    }
}

/// Freie Zeit und Zeitblöcke berechnen.
public enum FreeTime {
    /// Uhrzeit an einem Tag (Wanduhr, auch an Tagen mit Zeitumstellung).
    public static func date(on day: LocalDate, minutes: Int, calendar: Calendar = .current) -> Date {
        let start = day.startDate(calendar: calendar)
        if minutes >= 24 * 60 {
            return day.adding(days: 1, calendar: calendar).startDate(calendar: calendar)
        }
        return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: start) ?? start
    }

    /// Minuten seit Mitternacht.
    public static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Fasst überlappende oder aneinanderstoßende Zeiträume zusammen.
    public static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in sorted {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    public static func clip(_ interval: DateInterval, to window: DateInterval) -> DateInterval? {
        let start = max(interval.start, window.start)
        let end = min(interval.end, window.end)
        return end > start ? DateInterval(start: start, end: end) : nil
    }

    /// Belegte Zeit durch Termine innerhalb eines Fensters. Ganztägige Termine blockieren nichts.
    public static func busy(events: [CalendarEvent], within window: DateInterval) -> [DateInterval] {
        merge(events.filter { !$0.isAllDay }.compactMap { clip($0.interval, to: window) })
    }

    /// Lücken im Fenster, die nicht belegt sind.
    public static func gaps(in window: DateInterval, busy: [DateInterval]) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = window.start
        for block in merge(busy) {
            if block.start > cursor {
                gaps.append(DateInterval(start: cursor, end: min(block.start, window.end)))
            }
            cursor = max(cursor, block.end)
            if cursor >= window.end { break }
        }
        if cursor < window.end {
            gaps.append(DateInterval(start: cursor, end: window.end))
        }
        return gaps.filter { $0.duration > 0 }
    }

    public static func minutes(_ intervals: [DateInterval]) -> Int {
        Int(intervals.reduce(0) { $0 + $1.duration } / 60)
    }

    /// Freie Minuten der Arbeitszeit neben den Terminen.
    public static func freeMinutes(window: DateInterval, events: [CalendarEvent]) -> Int {
        minutes(gaps(in: window, busy: busy(events: events, within: window)))
    }

    /// Rundet auf den nächsten Schritt nach oben (z. B. 9:07 → 9:15).
    public static func snapUp(_ date: Date, stepMinutes: Int, calendar: Calendar = .current) -> Date {
        snap(date, stepMinutes: stepMinutes, rule: .up, calendar: calendar)
    }

    /// Rundet auf den nächstgelegenen Schritt (z. B. 9:07 → 9:00, 9:08 → 9:15).
    public static func snapNearest(_ date: Date, stepMinutes: Int, calendar: Calendar = .current) -> Date {
        snap(date, stepMinutes: stepMinutes, rule: .toNearestOrAwayFromZero, calendar: calendar)
    }

    private static func snap(_ date: Date, stepMinutes: Int, rule: FloatingPointRoundingRule, calendar: Calendar) -> Date {
        guard stepMinutes > 0 else { return date }
        let dayStart = calendar.startOfDay(for: date)
        let minutes = date.timeIntervalSince(dayStart) / 60
        let snapped = (minutes / Double(stepMinutes)).rounded(rule) * Double(stepMinutes)
        return dayStart.addingTimeInterval(snapped * 60)
    }

    /// Legt Aufgaben der Reihe nach in die erste passende Lücke, frühestens ab `notBefore`.
    /// Aufgaben, die nirgends mehr hineinpassen, fehlen im Ergebnis.
    public static func autoSchedule(
        _ items: [(id: UUID, minutes: Int)],
        gaps: [DateInterval],
        notBefore: Date,
        stepMinutes: Int = 15,
        calendar: Calendar = .current
    ) -> [UUID: Date] {
        var free: [DateInterval] = gaps.compactMap { gap in
            let start = snapUp(max(gap.start, notBefore), stepMinutes: stepMinutes, calendar: calendar)
            return start < gap.end ? DateInterval(start: start, end: gap.end) : nil
        }
        var result: [UUID: Date] = [:]
        for item in items {
            let needed = TimeInterval(max(item.minutes, stepMinutes) * 60)
            guard let index = free.firstIndex(where: { $0.duration >= needed }) else { continue }
            let slot = free[index]
            result[item.id] = slot.start
            let next = snapUp(slot.start.addingTimeInterval(needed), stepMinutes: stepMinutes, calendar: calendar)
            if next < slot.end {
                free[index] = DateInterval(start: next, end: slot.end)
            } else {
                free.remove(at: index)
            }
        }
        return result
    }
}

/// Ob die geführte Tagesplanung heute noch fällig ist.
public enum DailyPlanning {
    public static func isDue(lastPlanned: LocalDate?, today: LocalDate) -> Bool {
        guard let lastPlanned else { return true }
        return lastPlanned < today
    }
}
