import Foundation

/// Es läuft höchstens ein Timer. Wer einen neuen startet, beendet den laufenden.
public enum TimerLogic {
    /// Einträge, die kürzer sind, werden beim Stoppen verworfen (versehentliche Klicks).
    public static let minimumDuration: TimeInterval = 5

    public static func running(in entries: [TimeEntry]) -> TimeEntry? {
        entries.first { $0.isRunning }
    }

    public struct Change: Equatable, Sendable {
        /// beendete Einträge, die gespeichert werden
        public var stopped: [TimeEntry] = []
        /// zu kurze Einträge, die gelöscht werden
        public var discarded: [TimeEntry] = []
        /// neu gestarteter Eintrag
        public var started: TimeEntry?
        /// laufender Eintrag mit früherem Beginn („läuft eigentlich schon seit …“)
        public var restarted: TimeEntry?
    }

    public static func stop(entries: [TimeEntry], at now: Date) -> Change {
        var change = Change()
        for var entry in entries where entry.isRunning {
            entry.end = max(now, entry.start)
            if entry.duration(now: now) < minimumDuration {
                change.discarded.append(entry)
            } else {
                change.stopped.append(entry)
            }
        }
        return change
    }

    /// Vergessen zu starten: Der Timer läuft rückwirkend seit `since`. Er beginnt frühestens dort,
    /// wo der letzte erfasste Eintrag endet, damit sich keine Zeiten doppeln. Läuft schon ein Timer
    /// für eine andere Aufgabe, endet der dort; läuft er für dieselbe, rückt sein Beginn nach vorn.
    public static func start(taskID: UUID, entries: [TimeEntry], since: Date, now: Date) -> Change {
        let current = running(in: entries)
        var start = min(since, now)
        let latestEnd = entries.compactMap { entry -> Date? in
            guard entry.id != current?.id, let end = entry.end, end <= now else { return nil }
            return end
        }.max()
        if let latestEnd, start < latestEnd { start = latestEnd }
        if let current, current.taskID == taskID {
            var change = Change()
            guard start < current.start else { return change }
            var earlier = current
            earlier.start = start
            change.restarted = earlier
            return change
        }
        if let current { start = max(start, current.start) }
        return self.start(taskID: taskID, entries: entries, at: start)
    }

    public static func start(taskID: UUID, entries: [TimeEntry], at now: Date) -> Change {
        if let running = running(in: entries), running.taskID == taskID {
            return Change()
        }
        var change = stop(entries: entries, at: now)
        change.started = TimeEntry(taskID: taskID, start: now)
        return change
    }
}
