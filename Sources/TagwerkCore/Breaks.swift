import Foundation

/// Eine Pause: zählt nicht als Arbeitszeit und wird nirgends gebucht, steht aber im Kalender und im Tagesabschluss.
public struct WorkBreak: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var start: Date
    /// `nil` = die Pause läuft noch.
    public var end: Date?
    public var note: String
    /// Aufgabe, die vor der Pause lief; mit „Weiter“ geht es dort weiter.
    public var resumeTaskID: UUID?

    public init(id: UUID = UUID(), start: Date, end: Date? = nil, note: String = "", resumeTaskID: UUID? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.note = note
        self.resumeTaskID = resumeTaskID
    }

    public var isRunning: Bool { end == nil }

    public func duration(now: Date = Date()) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }

    /// Wie viele Sekunden der Pause in einen Zeitraum fallen (laufende Pausen zählen bis `now`).
    public func overlap(with interval: DateInterval, now: Date) -> TimeInterval {
        let stop = min(end ?? now, interval.end)
        let begin = max(start, interval.start)
        return max(0, stop.timeIntervalSince(begin))
    }
}

/// Was sich durch eine Pause ändert: Pausen und erfasste Arbeitszeit, die dafür gekürzt, geteilt oder gelöscht wird.
public struct BreakChange: Equatable, Sendable {
    /// neue oder geänderte Einträge
    public var savedEntries: [TimeEntry] = []
    public var deletedEntries: [TimeEntry] = []
    /// neue oder geänderte Pausen
    public var savedBreaks: [WorkBreak] = []
    public var deletedBreaks: [WorkBreak] = []

    public init() {}

    public var isEmpty: Bool {
        savedEntries.isEmpty && deletedEntries.isEmpty && savedBreaks.isEmpty && deletedBreaks.isEmpty
    }
}

/// Regeln für Pausen: starten, beenden, nachtragen, und was das Arbeitszeitgesetz dazu sagt.
public enum Breaks {
    /// Kürzere Pausen gelten als versehentlich und werden verworfen.
    public static let minimumDuration: TimeInterval = 60
    /// Reste erfasster Zeit, die nach dem Ausschneiden kürzer sind, fallen weg.
    public static let minimumRemainder: TimeInterval = 60
    /// Laut Arbeitszeitgesetz zählen Pausen erst ab 15 Minuten am Stück.
    public static let countingMinimum: TimeInterval = 15 * 60

    public static func running(in breaks: [WorkBreak]) -> WorkBreak? {
        breaks.first { $0.isRunning }
    }

    /// Pause jetzt: hält den laufenden Timer an und merkt sich seine Aufgabe für „Weiter“.
    /// Läuft schon eine Pause, ändert sich nichts.
    public static func start(entries: [TimeEntry], breaks: [WorkBreak], at now: Date) -> BreakChange {
        var change = BreakChange()
        guard running(in: breaks) == nil else { return change }
        let runningTask = TimerLogic.running(in: entries)?.taskID
        let stop = TimerLogic.stop(entries: entries, at: now)
        change.savedEntries = stop.stopped
        change.deletedEntries = stop.discarded
        change.savedBreaks = [WorkBreak(start: now, resumeTaskID: runningTask)]
        return change
    }

    /// Beendet die laufende Pause. Unter einer Minute wird sie verworfen.
    public static func end(breaks: [WorkBreak], at now: Date) -> BreakChange {
        var change = BreakChange()
        guard var current = running(in: breaks) else { return change }
        current.end = max(now, current.start)
        if current.duration(now: now) < minimumDuration {
            change.deletedBreaks = [current]
        } else {
            change.savedBreaks = [current]
        }
        return change
    }

    /// Pause nachtragen (oder eine eingetragene ändern, mit `replacing`). Arbeitszeit, die in die Pause fällt,
    /// wird dort herausgeschnitten: gekürzt, geteilt oder, wenn sie ganz darin liegt, gelöscht.
    /// Überschneidet sich die Pause mit anderen Pausen, werden sie zu einer zusammengelegt.
    /// Endet die Pause in der Zukunft, wird sie auf jetzt gekürzt.
    public static func add(
        start rawStart: Date,
        end rawEnd: Date,
        note: String = "",
        replacing replacedID: UUID? = nil,
        entries: [TimeEntry],
        breaks: [WorkBreak],
        now: Date
    ) -> BreakChange {
        var change = BreakChange()
        let end = min(rawEnd, now)
        let start = rawStart
        guard end.timeIntervalSince(start) >= minimumDuration else { return change }

        // Pausen zusammenlegen
        var merged = WorkBreak(id: replacedID ?? UUID(), start: start, end: end, note: note)
        if let replacedID, let old = breaks.first(where: { $0.id == replacedID }) {
            merged.resumeTaskID = old.resumeTaskID
            // Eine laufende Pause bleibt laufend; nur ihr Beginn ändert sich.
            if old.isRunning { merged.end = nil }
        }
        for other in breaks where other.id != replacedID {
            let otherEnd = other.end ?? now
            guard other.start <= end, otherEnd >= start else { continue }
            merged.start = min(merged.start, other.start)
            if other.isRunning {
                merged.end = nil
            } else if let mergedEnd = merged.end {
                merged.end = max(mergedEnd, otherEnd)
            }
            if merged.note.isEmpty { merged.note = other.note }
            merged.resumeTaskID = merged.resumeTaskID ?? other.resumeTaskID
            change.deletedBreaks.append(other)
        }
        change.savedBreaks.append(merged)

        // Arbeitszeit ausschneiden
        let cutStart = merged.start
        let cutEnd = merged.end ?? now
        for entry in entries {
            let entryEnd = entry.end ?? now
            guard entry.start < cutEnd, entryEnd > cutStart else { continue }
            let before = cutStart.timeIntervalSince(entry.start)
            let after = entryEnd.timeIntervalSince(cutEnd)
            let keepsBefore = before >= minimumRemainder
            let keepsAfter = after >= minimumRemainder

            switch (keepsBefore, keepsAfter) {
            case (false, false):
                change.deletedEntries.append(entry)
            case (true, false):
                var shortened = entry
                shortened.end = cutStart
                change.savedEntries.append(shortened)
            case (false, true):
                var later = entry
                later.start = cutEnd
                change.savedEntries.append(later)
            case (true, true):
                var first = entry
                first.end = cutStart
                change.savedEntries.append(first)
                // Der zweite Teil übernimmt das Ende; ein laufender Timer läuft dort weiter.
                change.savedEntries.append(TimeEntry(taskID: entry.taskID, start: cutEnd, end: entry.end, note: entry.note))
            }
        }
        return change
    }

    /// Pausenzeit an einem Tag.
    public static func total(on day: LocalDate, breaks: [WorkBreak], now: Date, calendar: Calendar = .current) -> TimeInterval {
        let interval = day.interval(calendar: calendar)
        return breaks.reduce(0) { $0 + $1.overlap(with: interval, now: now) }
    }

    /// Pausen, die einen Tag berühren, nach Beginn sortiert.
    public static func on(_ day: LocalDate, _ breaks: [WorkBreak], now: Date, calendar: Calendar = .current) -> [WorkBreak] {
        let interval = day.interval(calendar: calendar)
        return breaks
            .filter { $0.overlap(with: interval, now: now) > 0 }
            .sorted { $0.start < $1.start }
    }

    /// Pause, die das Arbeitszeitgesetz für so viel Arbeit verlangt: über 6 Stunden 30 Minuten, über 9 Stunden 45 Minuten.
    public static func requiredMinutes(worked: TimeInterval) -> Int {
        if worked > 9 * 3600 { return 45 }
        if worked > 6 * 3600 { return 30 }
        return 0
    }

    /// Pausenminuten eines Tages, die zählen (je mindestens 15 Minuten am Stück).
    public static func countedMinutes(on day: LocalDate, breaks: [WorkBreak], now: Date, calendar: Calendar = .current) -> Int {
        let interval = day.interval(calendar: calendar)
        let seconds = breaks.reduce(0.0) { sum, item in
            let part = item.overlap(with: interval, now: now)
            return part >= countingMinimum ? sum + part : sum
        }
        return Int(seconds / 60)
    }

    /// Fehlt Pause? Gibt die fehlenden Minuten zurück (0 = alles gut).
    public static func missingMinutes(worked: TimeInterval, countedMinutes: Int) -> Int {
        max(0, requiredMinutes(worked: worked) - countedMinutes)
    }
}
