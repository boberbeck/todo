import Foundation

/// Was im Kalender an einem erfassten Eintrag gezogen wird.
public enum EntryDrag: Sendable, Equatable {
    /// der ganze Block (Beginn und Ende gemeinsam)
    case move
    /// obere Kante: Beginn
    case start
    /// untere Kante: Ende
    case end
}

/// Erfasste Zeit nachträglich ändern: Verschieben und Kanten ziehen im Kalender, genaue Werte im Fenster.
/// Rastet auf fünf Minuten, bleibt am selben Tag, endet nicht in der Zukunft und überlappt keine anderen Einträge
/// (sonst zählte die Zeit doppelt, auch in SAP und im Ticket).
public enum EntryEditing {
    public static let step: TimeInterval = 5 * 60
    public static let minimum: TimeInterval = 5 * 60

    /// Neue Zeiten für einen Eintrag, an dem um `delta` Sekunden gezogen wird.
    /// Ein laufender Eintrag lässt sich nur am Beginn ändern.
    public static func dragged(
        _ entry: TimeEntry,
        _ drag: EntryDrag,
        by delta: TimeInterval,
        others: [TimeEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date?) {
        let original = (start: entry.start, end: entry.end)
        let end = entry.end ?? now
        let day = LocalDate(entry.start, calendar: calendar).interval(calendar: calendar)
        let bounds = room(around: entry, others: others, day: day, now: now)
        func snap(_ date: Date) -> Date {
            let offset = date.timeIntervalSince(day.start)
            return day.start.addingTimeInterval((offset / step).rounded() * step)
        }

        switch drag {
        case .start:
            let latest = end.addingTimeInterval(-minimum)
            guard latest >= bounds.lower else { return original }
            let start = min(latest, max(bounds.lower, snap(entry.start.addingTimeInterval(delta))))
            return (start, entry.end)
        case .end:
            guard entry.end != nil else { return original }
            let earliest = entry.start.addingTimeInterval(minimum)
            guard bounds.upper >= earliest else { return original }
            let newEnd = max(earliest, min(bounds.upper, snap(end.addingTimeInterval(delta))))
            return (entry.start, newEnd)
        case .move:
            guard entry.end != nil else { return original }
            let duration = end.timeIntervalSince(entry.start)
            let latestStart = bounds.upper.addingTimeInterval(-duration)
            guard latestStart >= bounds.lower else { return original }
            let start = min(latestStart, max(bounds.lower, snap(entry.start.addingTimeInterval(delta))))
            return (start, start.addingTimeInterval(duration))
        }
    }

    /// Wie weit der Eintrag reichen darf: vom Ende des vorigen bis zum Beginn des nächsten Eintrags,
    /// innerhalb des Tages und nicht über jetzt hinaus.
    static func room(around entry: TimeEntry, others: [TimeEntry], day: DateInterval, now: Date) -> (lower: Date, upper: Date) {
        let end = entry.end ?? now
        let neighbours = others.filter { $0.id != entry.id }
        let previousEnd = neighbours
            .filter { $0.start < entry.start }
            .map { $0.end ?? now }
            .max() ?? day.start
        let nextStart = neighbours
            .filter { $0.start >= entry.start }
            .map(\.start)
            .min() ?? day.end
        // Überschneidet sich der Eintrag schon jetzt, wenigstens nicht weiter wachsen lassen
        let lower = min(entry.start, max(day.start, previousEnd))
        let upper = max(end, min(day.end, now, nextStart))
        return (lower, upper)
    }

    /// Vorschlag für einen neuen Eintrag nach Doppelklick in eine freie Stelle des Kalenders:
    /// ab der Viertelstunde, in die geklickt wurde, `minutes` lang. Was schon vorbei ist, endet spätestens jetzt;
    /// vorhandene Einträge werden nicht überdeckt.
    public static func newSlot(
        near click: Date,
        minutes: Int = 60,
        entries: [TimeEntry],
        now: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let day = LocalDate(click, calendar: calendar).interval(calendar: calendar)
        let quarter: TimeInterval = 15 * 60
        var start = day.start.addingTimeInterval((click.timeIntervalSince(day.start) / quarter).rounded(.down) * quarter)
        let previousEnd = entries
            .filter { $0.start <= click }
            .map { $0.end ?? now }
            .filter { $0 <= click }
            .max()
        if let previousEnd, previousEnd > start { start = previousEnd }
        var end = start.addingTimeInterval(TimeInterval(max(5, minutes) * 60))
        if start < now { end = min(end, now) }
        if let nextStart = entries.map(\.start).filter({ $0 > click }).min() { end = min(end, nextStart) }
        end = min(end, day.end)
        if end <= start { end = start.addingTimeInterval(minimum) }
        return DateInterval(start: start, end: end)
    }

    /// Einträge, mit denen sich die Zeit von `start` bis `end` überschneiden würde.
    /// Sekunden zählen nicht: Im Fenster gibt man Minuten ein, der Timer endet aber auf die Sekunde.
    public static func conflicts(start: Date, end: Date, excluding id: UUID?, in entries: [TimeEntry], now: Date) -> [TimeEntry] {
        entries
            .filter { other in
                guard other.id != id else { return false }
                let overlap = min(end, other.end ?? now).timeIntervalSince(max(start, other.start))
                return overlap >= 60
            }
            .sorted { $0.start < $1.start }
    }

    /// Unveränderte Minute: die genaue Zeit (mit Sekunden) behalten, damit Einträge lückenlos aneinander anschließen.
    public static func keepingSeconds(_ date: Date, of original: Date?) -> Date {
        guard let original else { return date }
        let minute = { (value: Date) in Int((value.timeIntervalSince1970 / 60).rounded(.down)) }
        return minute(date) == minute(original) ? original : date
    }

    /// Was gegen die eingegebenen Zeiten spricht, oder `nil`, wenn sie passen.
    public static func problem(start: Date, end: Date?, excluding id: UUID?, in entries: [TimeEntry], now: Date) -> Problem? {
        let effectiveEnd = end ?? now
        if effectiveEnd <= start { return .endBeforeStart }
        if start > now || (end.map { $0 > now.addingTimeInterval(60) } ?? false) { return .inFuture }
        if let other = conflicts(start: start, end: effectiveEnd, excluding: id, in: entries, now: now).first {
            return .overlaps(other)
        }
        return nil
    }

    public enum Problem: Equatable, Sendable {
        case endBeforeStart
        case inFuture
        case overlaps(TimeEntry)
    }
}
