import Foundation

/// Liest eine Zeitschätzung am Ende eines Aufgabentitels.
///
/// Beispiele: "Angebot schreiben 1h30" → ("Angebot schreiben", 90),
/// "Logs prüfen 45m" → ("Logs prüfen", 45), "Review 1,5h" → ("Review", 90),
/// "Termin vorbereiten 0:20" → ("Termin vorbereiten", 20).
public enum DurationParser {
    public static func split(title raw: String) -> (title: String, minutes: Int?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let spaceIndex = trimmed.lastIndex(of: " ") else {
            return (trimmed, nil)
        }
        let lastToken = String(trimmed[trimmed.index(after: spaceIndex)...])
        let rest = String(trimmed[..<spaceIndex]).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty, let minutes = minutes(from: lastToken), minutes > 0 else {
            return (trimmed, nil)
        }
        return (rest, minutes)
    }

    /// Wandelt einen einzelnen Ausdruck wie "1h30", "90min", "1:15" oder "2h" in Minuten um.
    public static func minutes(from token: String) -> Int? {
        let text = token.lowercased().replacingOccurrences(of: ",", with: ".")
        if text.isEmpty { return nil }

        if text.contains(":") {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<60).contains(m) else {
                return nil
            }
            return h * 60 + m
        }

        if text.contains("h") {
            let parts = text.split(separator: "h", maxSplits: 1, omittingEmptySubsequences: false)
            guard let hours = Double(parts[0]), hours >= 0 else { return nil }
            var minutes = Int((hours * 60).rounded())
            if parts.count == 2 {
                var tail = String(parts[1])
                if tail.hasSuffix("min") { tail.removeLast(3) } else if tail.hasSuffix("m") { tail.removeLast() }
                if !tail.isEmpty {
                    guard let extra = Int(tail), (0..<60).contains(extra) else { return nil }
                    minutes += extra
                }
            }
            return minutes
        }

        var number = text
        if number.hasSuffix("min") {
            number.removeLast(3)
        } else if number.hasSuffix("m") {
            number.removeLast()
        } else {
            return nil
        }
        return Int(number)
    }
}
