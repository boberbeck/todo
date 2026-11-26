import Foundation

public enum RoundingMode: String, Codable, CaseIterable, Sendable {
    /// kaufmännisch auf den nächsten Schritt
    case nearest
    /// immer auf den nächsten Schritt aufrunden
    case up
}

/// Rechnen mit erfassten Zeiten. Alles hier ist reine Logik ohne Zustand.
public enum TimeMath {
    /// Wie viele Sekunden eines Eintrags in einen Zeitraum fallen (laufende Einträge zählen bis `now`).
    public static func overlap(of entry: TimeEntry, with interval: DateInterval, now: Date) -> TimeInterval {
        let end = entry.end ?? now
        guard end > entry.start else { return 0 }
        let start = max(entry.start, interval.start)
        let stop = min(end, interval.end)
        return max(0, stop.timeIntervalSince(start))
    }

    /// Gesamte erfasste Zeit einer Aufgabe.
    public static func tracked(taskID: UUID, entries: [TimeEntry], now: Date) -> TimeInterval {
        entries
            .filter { $0.taskID == taskID }
            .reduce(0) { $0 + $1.duration(now: now) }
    }

    /// Erfasste Zeit an einem Tag. Einträge über Mitternacht werden am Tageswechsel geteilt.
    public static func tracked(
        on day: LocalDate,
        entries: [TimeEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let interval = day.interval(calendar: calendar)
        return entries.reduce(0) { $0 + overlap(of: $1, with: interval, now: now) }
    }

    /// Erfasste Zeit einer Aufgabe an einem Tag.
    public static func tracked(
        taskID: UUID,
        on day: LocalDate,
        entries: [TimeEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> TimeInterval {
        tracked(on: day, entries: entries.filter { $0.taskID == taskID }, now: now, calendar: calendar)
    }

    /// "0:42" oder mit Sekunden "0:42:15".
    public static func format(_ seconds: TimeInterval, showSeconds: Bool = false) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if showSeconds {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", hours, minutes)
    }

    /// Minuten als "1:30".
    public static func format(minutes: Int) -> String {
        let value = max(0, minutes)
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    /// Rundet eine Dauer auf ganze Schritte (z. B. 15 Minuten) und gibt Minuten zurück.
    /// Jede Dauer über null ergibt mindestens einen Schritt.
    public static func rounded(_ seconds: TimeInterval, toMinutes step: Int, mode: RoundingMode) -> Int {
        guard seconds > 0, step > 0 else { return 0 }
        let units = seconds / Double(step * 60)
        let rule: FloatingPointRoundingRule = mode == .up ? .up : .toNearestOrAwayFromZero
        let whole = max(1, Int(units.rounded(rule)))
        return whole * step
    }
}

/// Verteilt sich überlappende Zeiträume (z. B. erfasste Zeit während eines Termins) im Kalender nebeneinander,
/// damit keiner den anderen verdeckt.
public enum CalendarLanes {
    public struct Item<ID: Hashable>: Sendable where ID: Sendable {
        public var id: ID
        public var start: Date
        public var end: Date

        public init(id: ID, start: Date, end: Date) {
            self.id = id
            self.start = start
            self.end = end
        }
    }

    /// Spalte (`index`) und Anzahl Spalten (`count`) der Gruppe, in der der Zeitraum liegt.
    public struct Lane: Equatable, Sendable {
        public var index: Int
        public var count: Int

        public init(index: Int, count: Int) {
            self.index = index
            self.count = count
        }

        public static let single = Lane(index: 0, count: 1)
    }

    public static func assign<ID: Hashable>(_ items: [Item<ID>]) -> [ID: Lane] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.end > rhs.end
        }
        var result: [ID: Lane] = [:]
        var group: [(id: ID, lane: Int)] = []
        var laneEnds: [Date] = []
        var groupEnd = Date.distantPast

        func closeGroup() {
            for member in group {
                result[member.id] = Lane(index: member.lane, count: max(1, laneEnds.count))
            }
            group = []
            laneEnds = []
        }

        for item in sorted {
            let end = max(item.end, item.start)
            if !group.isEmpty, item.start >= groupEnd {
                closeGroup()
            }
            if let free = laneEnds.firstIndex(where: { $0 <= item.start }) {
                laneEnds[free] = end
                group.append((item.id, free))
            } else {
                laneEnds.append(end)
                group.append((item.id, laneEnds.count - 1))
            }
            groupEnd = group.count == 1 ? end : max(groupEnd, end)
        }
        closeGroup()
        return result
    }
}
