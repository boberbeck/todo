import Foundation

/// Art der Abwesenheit.
public enum AbsenceKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case sick
    case vacation

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sick: return "Krank"
        case .vacation: return "Urlaub"
        }
    }

    /// SF-Symbol für die Anzeige
    public var symbol: String {
        switch self {
        case .sick: return "cross.case"
        case .vacation: return "sun.max"
        }
    }

    /// Erkennt „krank“, „Krankheit“, „Urlaub“ usw. (für Claude)
    public static func parse(_ text: String) -> AbsenceKind? {
        let key = text.trimmingCharacters(in: .whitespaces).lowercased()
        if key.hasPrefix("krank") || key == "sick" || key == "krankheit" { return .sick }
        if key.hasPrefix("urlaub") || key == "vacation" || key == "frei" { return .vacation }
        return nil
    }
}

/// Ein Tag, an dem nicht gearbeitet wird (oder nur einen halben Tag).
public struct Absence: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var day: LocalDate
    public var kind: AbsenceKind
    public var halfDay: Bool
    public var note: String
    public var createdAt: Date

    public init(id: UUID = UUID(), day: LocalDate, kind: AbsenceKind, halfDay: Bool = false, note: String = "", createdAt: Date = Date()) {
        self.id = id
        self.day = day
        self.kind = kind
        self.halfDay = halfDay
        self.note = note
        self.createdAt = createdAt
    }

    /// Anteil am Arbeitstag, der wegfällt
    public var fraction: Double { halfDay ? 0.5 : 1 }

    public var label: String { halfDay ? "\(kind.label), halber Tag" : kind.label }
}

/// Regeln für Abwesenheiten: Arbeitstage, Wochenziel, Eintragen über mehrere Tage.
public enum Absences {
    /// Montag bis Freitag
    public static func isWorkday(_ day: LocalDate, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return weekday != 1 && weekday != 7
    }

    /// Arbeitstage von … bis einschließlich (Wochenenden fallen weg).
    public static func workdays(from start: LocalDate, through end: LocalDate, calendar: Calendar = .current) -> [LocalDate] {
        guard start <= end else { return [] }
        var days: [LocalDate] = []
        var day = start
        while day <= end, days.count < 400 {
            if isWorkday(day, calendar: calendar) { days.append(day) }
            day = day.adding(days: 1, calendar: calendar)
        }
        return days
    }

    public static func absence(on day: LocalDate, in absences: [Absence]) -> Absence? {
        absences.first { $0.day == day }
    }

    /// Abwesenheiten in der Woche ab `weekStart` (Montag).
    public static func inWeek(starting weekStart: LocalDate, _ absences: [Absence], calendar: Calendar = .current) -> [Absence] {
        let end = weekStart.adding(days: 6, calendar: calendar)
        return absences.filter { $0.day >= weekStart && $0.day <= end }.sorted { $0.day < $1.day }
    }

    /// Wochenziel: Tagesziel mal Arbeitstage, abzüglich Krank- und Urlaubstage (halber Tag zählt halb).
    public static func weeklyGoalMinutes(dailyMinutes: Int, weekStart: LocalDate, absences: [Absence], calendar: Calendar = .current) -> Int {
        let workdays = workdays(from: weekStart, through: weekStart.adding(days: 6, calendar: calendar), calendar: calendar)
        let missing = workdays.reduce(0.0) { sum, day in
            sum + (absence(on: day, in: absences)?.fraction ?? 0)
        }
        let days = max(0, Double(workdays.count) - missing)
        return Int((Double(dailyMinutes) * days).rounded())
    }

    /// Neue Einträge für einen Zeitraum, nur Arbeitstage. Ein halber Tag gilt nur, wenn es ein einzelner Tag ist.
    public static func make(kind: AbsenceKind, from start: LocalDate, through end: LocalDate, halfDay: Bool = false, note: String = "", now: Date = Date(), calendar: Calendar = .current) -> [Absence] {
        let days = workdays(from: start, through: max(start, end), calendar: calendar)
        let half = halfDay && days.count == 1
        return days.map { Absence(day: $0, kind: kind, halfDay: half, note: note, createdAt: now) }
    }

    /// Nächster Arbeitstag nach `day`, an dem man nicht ganz abwesend ist (für verschobene Aufgaben).
    public static func nextWorkingDay(after day: LocalDate, absences: [Absence], calendar: Calendar = .current) -> LocalDate {
        var candidate = day.adding(days: 1, calendar: calendar)
        for _ in 0..<60 {
            let away = absence(on: candidate, in: absences)
            if isWorkday(candidate, calendar: calendar), away == nil || away?.halfDay == true {
                return candidate
            }
            candidate = candidate.adding(days: 1, calendar: calendar)
        }
        return candidate
    }

    /// Kurz für Anzeigen: „2 Tage krank, 1 Tag Urlaub“
    public static func summary(_ absences: [Absence]) -> String? {
        let parts = AbsenceKind.allCases.compactMap { kind -> String? in
            let days = absences.filter { $0.kind == kind }.reduce(0.0) { $0 + $1.fraction }
            guard days > 0 else { return nil }
            let number = days == days.rounded() ? String(Int(days)) : String(format: "%.1f", days).replacingOccurrences(of: ".", with: ",")
            let unit = days == 1 ? "Tag" : "Tage"
            return kind == .sick ? "\(number) \(unit) krank" : "\(number) \(unit) Urlaub"
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
