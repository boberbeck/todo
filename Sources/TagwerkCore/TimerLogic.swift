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

    public static func start(taskID: UUID, entries: [TimeEntry], at now: Date) -> Change {
        if let running = running(in: entries), running.taskID == taskID {
            return Change()
        }
        var change = stop(entries: entries, at: now)
        change.started = TimeEntry(taskID: taskID, start: now)
        return change
    }
}
