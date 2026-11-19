import Foundation

/// Ein Kalendertag ohne Uhrzeit, z. B. der Tag, für den eine Aufgabe geplant ist.
/// Wird als "JJJJ-MM-TT" gespeichert.
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            return nil
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> LocalDate {
        LocalDate(now, calendar: calendar)
    }

    public var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { string }

    /// Beginn des Tages (00:00 Uhr) im angegebenen Kalender.
    public func startDate(calendar: Calendar = .current) -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    /// Der ganze Tag als Zeitraum, von 00:00 bis 00:00 des Folgetages.
    public func interval(calendar: Calendar = .current) -> DateInterval {
        let start = startDate(calendar: calendar)
        let end = adding(days: 1, calendar: calendar).startDate(calendar: calendar)
        return DateInterval(start: start, end: end)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> LocalDate {
        let start = startDate(calendar: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return LocalDate(moved, calendar: calendar)
    }

    /// Montag der Woche, in der dieser Tag liegt.
    public func startOfWeek(calendar: Calendar = .current) -> LocalDate {
        var monday = calendar
        monday.firstWeekday = 2
        let start = startDate(calendar: calendar)
        let weekStart = monday.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        return LocalDate(weekStart, calendar: calendar)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = LocalDate(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Ungültiges Datum: \(raw)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}
