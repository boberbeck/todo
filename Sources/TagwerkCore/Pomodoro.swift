import Foundation

/// Pomodoro nach Francesco Cirillo: konzentriert arbeiten (Standard 25 Minuten), dann kurze Pause (5 Minuten);
/// nach vier Runden eine lange Pause (15 Minuten). Alle Zeiten einstellbar.
public struct PomodoroSettings: Equatable, Sendable {
    public var workMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    /// Nach so vielen Arbeitsrunden kommt die lange Pause.
    public var roundsUntilLongBreak: Int

    public init(workMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15, roundsUntilLongBreak: Int = 4) {
        self.workMinutes = max(1, workMinutes)
        self.shortBreakMinutes = max(1, shortBreakMinutes)
        self.longBreakMinutes = max(1, longBreakMinutes)
        self.roundsUntilLongBreak = max(1, roundsUntilLongBreak)
    }
}

public struct PomodoroState: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case work
        case shortBreak
        case longBreak
        /// Pause vorbei, wartet auf „Weiter“
        case ready

        public var isBreak: Bool { self == .shortBreak || self == .longBreak }
    }

    public var phase: Phase
    public var phaseStart: Date
    /// Abgeschlossene Arbeitsrunden seit der letzten langen Pause
    public var completedInSet: Int
    /// Aufgabe, an der gearbeitet wird; nach der Pause geht es mit ihr weiter.
    public var taskID: UUID?

    public init(phase: Phase, phaseStart: Date, completedInSet: Int = 0, taskID: UUID? = nil) {
        self.phase = phase
        self.phaseStart = phaseStart
        self.completedInSet = completedInSet
        self.taskID = taskID
    }

    /// Die wievielte Runde gerade läuft (bzw. als Nächstes kommt), 1-basiert.
    public func round(settings: PomodoroSettings) -> Int {
        let current = phase == .work ? completedInSet + 1 : completedInSet
        return min(max(current, 1), settings.roundsUntilLongBreak)
    }
}

public enum Pomodoro {
    public static func duration(of phase: PomodoroState.Phase, settings: PomodoroSettings) -> TimeInterval? {
        switch phase {
        case .work: return TimeInterval(settings.workMinutes * 60)
        case .shortBreak: return TimeInterval(settings.shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(settings.longBreakMinutes * 60)
        case .ready: return nil
        }
    }

    /// Verbleibende Zeit der Phase (0, wenn sie vorbei ist oder keine Dauer hat).
    public static func remaining(_ state: PomodoroState, settings: PomodoroSettings, now: Date) -> TimeInterval {
        guard let duration = duration(of: state.phase, settings: settings) else { return 0 }
        return max(0, duration - now.timeIntervalSince(state.phaseStart))
    }

    /// Anteil der Phase, der schon vergangen ist (0…1).
    public static func progress(_ state: PomodoroState, settings: PomodoroSettings, now: Date) -> Double {
        guard let duration = duration(of: state.phase, settings: settings), duration > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(state.phaseStart) / duration))
    }

    /// Neue Arbeitsrunde. Nach einer Pause zählt die Runde weiter, sonst beginnt ein neuer Satz.
    public static func startWork(previous: PomodoroState?, taskID: UUID?, now: Date) -> PomodoroState {
        PomodoroState(phase: .work, phaseStart: now, completedInSet: previous?.completedInSet ?? 0, taskID: taskID ?? previous?.taskID)
    }

    /// Nächste Phase, wenn die aktuelle abgelaufen ist; sonst `nil`.
    /// Arbeit → kurze Pause (oder lange nach der letzten Runde) → bereit (wartet auf „Weiter“).
    public static func advance(_ state: PomodoroState, settings: PomodoroSettings, now: Date) -> PomodoroState? {
        guard let duration = duration(of: state.phase, settings: settings) else { return nil }
        let end = state.phaseStart.addingTimeInterval(duration)
        guard now >= end else { return nil }
        switch state.phase {
        case .work:
            let completed = state.completedInSet + 1
            let long = completed >= settings.roundsUntilLongBreak
            return PomodoroState(phase: long ? .longBreak : .shortBreak, phaseStart: end, completedInSet: completed, taskID: state.taskID)
        case .shortBreak:
            return PomodoroState(phase: .ready, phaseStart: end, completedInSet: state.completedInSet, taskID: state.taskID)
        case .longBreak:
            // Nach der langen Pause beginnt ein neuer Satz.
            return PomodoroState(phase: .ready, phaseStart: end, completedInSet: 0, taskID: state.taskID)
        case .ready:
            return nil
        }
    }

    /// Pause vorzeitig beenden.
    public static func skipBreak(_ state: PomodoroState, now: Date) -> PomodoroState {
        guard state.phase.isBreak else { return state }
        return PomodoroState(phase: .ready, phaseStart: now, completedInSet: state.phase == .longBreak ? 0 : state.completedInSet, taskID: state.taskID)
    }
}
