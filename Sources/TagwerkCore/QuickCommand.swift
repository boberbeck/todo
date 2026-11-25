import Foundation

/// Wohin die Befehlszeile springen kann.
public enum CommandDestination: String, CaseIterable, Sendable {
    case start, plan, calendar, focus, customers, goals, review, planning, close

    public var label: String {
        switch self {
        case .start: return "Start"
        case .plan: return "Woche planen"
        case .calendar: return "Kalender"
        case .focus: return "Fokus"
        case .customers: return "Kunden"
        case .goals: return "Ziele"
        case .review: return "Rückblick"
        case .planning: return "Tag planen"
        case .close: return "Tag abschließen"
        }
    }

    public var symbol: String {
        switch self {
        case .start: return "house"
        case .plan: return "rectangle.split.3x1"
        case .calendar: return "calendar"
        case .focus: return "scope"
        case .customers: return "person.2"
        case .goals: return "flag.checkered"
        case .review: return "chart.bar"
        case .planning: return "sunrise"
        case .close: return "moon"
        }
    }

    /// Wörter, unter denen man die Seite findet (klein, ohne Umlaute).
    var keywords: [String] {
        switch self {
        case .start: return ["start", "heute", "startseite"]
        case .plan: return ["plan", "woche", "wochenplan", "planen"]
        case .calendar: return ["kalender", "termine"]
        case .focus: return ["fokus", "konzentrieren"]
        case .customers: return ["kunden", "kunde"]
        case .goals: return ["ziele", "ziel"]
        case .review: return ["ruckblick", "auswertung", "statistik", "woche auswerten"]
        case .planning: return ["tag planen", "tagesplanung", "morgen planen"]
        case .close: return ["tag abschliessen", "abschluss", "feierabend", "worklogs", "tagesabschluss"]
        }
    }
}

/// Was ein Befehl tut. Die App führt ihn aus.
public enum CommandAction: Equatable, Sendable {
    /// Timer für eine bestehende Aufgabe starten (ein laufender endet)
    case start(UUID)
    /// Neue Aufgabe für heute anlegen und gleich starten
    case startNew(title: String, customerID: UUID?)
    /// Timer läuft rückwirkend seit `since` (bestehende Aufgabe oder neue)
    case startSince(taskID: UUID?, title: String, customerID: UUID?, since: Date)
    /// Zeit nachtragen, die gerade zu Ende gegangen ist (bestehende Aufgabe oder neue, erledigte)
    case log(taskID: UUID?, title: String, customerID: UUID?, minutes: Int)
    /// Aufgabe anlegen; `day` nil = Eingang
    case add(title: String, customerID: UUID?, day: LocalDate?, estimateMinutes: Int?)
    case stop
    case complete(UUID)
    case focus(UUID)
    case startLunch
    case endLunch
    case open(CommandDestination)
    /// Krank oder Urlaub eintragen (nur Arbeitstage zählen)
    case absent(kind: AbsenceKind, from: LocalDate, through: LocalDate, halfDay: Bool)
    /// Fenster „Abwesenheit eintragen“ mit Zeitraum und Notiz
    case absenceForm(AbsenceKind)
}

/// Ein Vorschlag in der Befehlszeile: was ↩ tut.
public struct CommandSuggestion: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var action: CommandAction

    public init(id: String, title: String, detail: String, symbol: String, action: CommandAction) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.action = action
    }
}

/// Was die Befehlszeile über den Stand wissen muss.
public struct CommandContext: Sendable {
    public var tasks: [TaskItem]
    public var customers: [Customer]
    public var today: LocalDate
    public var runningTaskID: UUID?
    public var lunchRunning: Bool
    public var now: Date
    public var calendar: Calendar
    /// Heute schon krank oder Urlaub eingetragen?
    public var absentToday: Bool
    /// Heute schon erfasste Zeit (morgens ohne Zeit schlägt die Befehlszeile „Heute krank“ vor)
    public var trackedTodaySeconds: TimeInterval

    public init(
        tasks: [TaskItem],
        customers: [Customer],
        today: LocalDate,
        runningTaskID: UUID?,
        lunchRunning: Bool,
        now: Date,
        calendar: Calendar = .current,
        absentToday: Bool = false,
        trackedTodaySeconds: TimeInterval = 0
    ) {
        self.tasks = tasks
        self.customers = customers
        self.today = today
        self.runningTaskID = runningTaskID
        self.lunchRunning = lunchRunning
        self.now = now
        self.calendar = calendar
        self.absentToday = absentToday
        self.trackedTodaySeconds = trackedTodaySeconds
    }
}

/// Die Befehlszeile (⌘K): Man tippt in normalem Deutsch, was man tut, Tagwerk macht daraus eine Aktion.
///
/// Beispiele:
/// - „VPN“ → Timer für „VPN-Störung prüfen“ starten
/// - „45m Telefonat Müller“ → 45 Minuten bis jetzt nachtragen (neue Aufgabe beim Kunden Müller)
/// - „seit 9:30 Angebot“ → Timer läuft seit 9:30
/// - „morgen Rechnung prüfen 30m“ → Aufgabe für morgen mit Schätzung
/// - „Mittag“, „fertig“, „stopp“, „Kalender“
/// - „krank“, „krank bis Freitag“, „Urlaub von Montag bis Freitag“
public enum QuickCommand {
    public static let maximumLogMinutes = 8 * 60

    public static func suggestions(for raw: String, in context: CommandContext, limit: Int = 8) -> [CommandSuggestion] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return idleSuggestions(context, limit: limit) }

        var result: [CommandSuggestion] = []
        let key = normalize(query)
        let customerID = customer(in: query, customers: context.customers)

        // Feste Wörter: stopp, fertig, Mittag, weiter
        result += keywordSuggestions(key, context)

        // „krank“, „krank bis Freitag“, „Urlaub morgen“
        let absenceParsed = absence(query, today: context.today, calendar: context.calendar)
        if let parsed = absenceParsed {
            result.append(absenceSuggestion(parsed, context))
            result.append(CommandSuggestion(
                id: "absence-form-\(parsed.kind.rawValue)",
                title: parsed.kind == .sick ? "Krank eintragen …" : "Urlaub eintragen …",
                detail: "Fenster mit Zeitraum, halbem Tag und Notiz",
                symbol: "calendar.badge.plus",
                action: .absenceForm(parsed.kind)
            ))
        }

        // „45m Telefonat“: Zeit bis jetzt nachtragen
        if let parsed = leadingDuration(query), !parsed.rest.isEmpty, parsed.minutes <= maximumLogMinutes {
            let start = context.now.addingTimeInterval(TimeInterval(-parsed.minutes * 60))
            let range = "\(clock(start, context.calendar))–\(clock(context.now, context.calendar))"
            if let match = bestTask(for: parsed.rest, in: context, minimumScore: 60) {
                result.append(CommandSuggestion(
                    id: "log-\(match.id)",
                    title: "\(TimeMath.format(minutes: parsed.minutes)) h auf „\(match.title)“ nachtragen",
                    detail: "\(range), endet jetzt",
                    symbol: "clock.arrow.circlepath",
                    action: .log(taskID: match.id, title: match.title, customerID: nil, minutes: parsed.minutes)
                ))
            }
            let title = cleanTitle(parsed.rest)
            result.append(CommandSuggestion(
                id: "log-new",
                title: "„\(title)“ nachtragen · \(TimeMath.format(minutes: parsed.minutes)) h",
                detail: "\(range) als erledigte Aufgabe von heute\(customerSuffix(customerID, context))",
                symbol: "clock.badge.checkmark",
                action: .log(taskID: nil, title: title, customerID: customerID, minutes: parsed.minutes)
            ))
        }

        // „seit 9:30 Angebot“: Timer rückwirkend
        if let parsed = sinceTime(query, on: context.today, calendar: context.calendar), !parsed.rest.isEmpty, parsed.date < context.now {
            let since = clock(parsed.date, context.calendar)
            if let match = bestTask(for: parsed.rest, in: context, minimumScore: 60) {
                result.append(CommandSuggestion(
                    id: "since-\(match.id)",
                    title: "„\(match.title)“ läuft seit \(since)",
                    detail: "Timer rückwirkend starten",
                    symbol: "play.circle",
                    action: .startSince(taskID: match.id, title: match.title, customerID: nil, since: parsed.date)
                ))
            }
            let title = cleanTitle(parsed.rest)
            result.append(CommandSuggestion(
                id: "since-new",
                title: "„\(title)“ läuft seit \(since)",
                detail: "Neue Aufgabe für heute, Timer rückwirkend\(customerSuffix(customerID, context))",
                symbol: "play.circle",
                action: .startSince(taskID: nil, title: title, customerID: customerID, since: parsed.date)
            ))
        }

        // „morgen Angebot 30m“, „neu …“, „+ …“, „später …“: Aufgabe anlegen
        if absenceParsed == nil, let parsed = planned(query, today: context.today, calendar: context.calendar) {
            let split = DurationParser.split(title: parsed.rest)
            let title = cleanTitle(split.title)
            if !title.isEmpty {
                let when = dayLabel(parsed.day, today: context.today, calendar: context.calendar)
                result.append(CommandSuggestion(
                    id: "add-\(parsed.day?.string ?? "inbox")",
                    title: "„\(title)“ \(parsed.day == nil ? "in den Eingang" : "für \(when) anlegen")",
                    detail: [split.minutes.map { "geschätzt \(TimeMath.format(minutes: $0)) h" }, customerName(customerID, context)]
                        .compactMap { $0 }.joined(separator: " · ").ifEmpty("Neue Aufgabe"),
                    symbol: parsed.day == nil ? "tray.and.arrow.down" : "plus.circle",
                    action: .add(title: title, customerID: customerID, day: parsed.day, estimateMinutes: split.minutes)
                ))
            }
        }

        // Bestehende Aufgaben
        for (task, _) in rankedTasks(for: query, in: context).prefix(4) {
            if task.id == context.runningTaskID {
                result.append(CommandSuggestion(
                    id: "focus-\(task.id)",
                    title: task.title,
                    detail: "Läuft gerade · im Fokus öffnen",
                    symbol: "scope",
                    action: .focus(task.id)
                ))
            } else {
                result.append(CommandSuggestion(
                    id: "start-\(task.id)",
                    title: task.title,
                    detail: taskDetail(task, context),
                    symbol: task.isStanding ? "pin" : "play.fill",
                    action: .start(task.id)
                ))
            }
        }

        // Seiten
        for destination in destinations(matching: key) {
            result.append(CommandSuggestion(
                id: "open-\(destination.rawValue)",
                title: destination.label,
                detail: "Öffnen",
                symbol: destination.symbol,
                action: .open(destination)
            ))
        }

        // Freier Text: neue Aufgabe jetzt starten oder anlegen
        if !looksLikeCommand(query), result.allSatisfy({ !$0.id.hasPrefix("log") && !$0.id.hasPrefix("since") && !$0.id.hasPrefix("add") && !$0.id.hasPrefix("absen") }) {
            let split = DurationParser.split(title: query)
            let title = cleanTitle(split.title)
            if !title.isEmpty, title.count >= 2 {
                result.append(CommandSuggestion(
                    id: "new-start",
                    title: "„\(title)“ jetzt starten",
                    detail: "Neue Aufgabe für heute, Timer läuft\(customerSuffix(customerID, context))",
                    symbol: "play.circle.fill",
                    action: .startNew(title: title, customerID: customerID)
                ))
                result.append(CommandSuggestion(
                    id: "new-today",
                    title: "„\(title)“ für heute anlegen",
                    detail: split.minutes.map { "geschätzt \(TimeMath.format(minutes: $0)) h" } ?? "Neue Aufgabe",
                    symbol: "plus.circle",
                    action: .add(title: title, customerID: customerID, day: context.today, estimateMinutes: split.minutes)
                ))
            }
        }

        var seen = Set<String>()
        return Array(result.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    // MARK: Ohne Eingabe

    static func idleSuggestions(_ context: CommandContext, limit: Int) -> [CommandSuggestion] {
        var result: [CommandSuggestion] = []
        if context.lunchRunning {
            result.append(CommandSuggestion(id: "lunch-end", title: "Mittagspause beenden", detail: "Weiter mit der Aufgabe von vorher", symbol: "play.fill", action: .endLunch))
        }
        if let id = context.runningTaskID, let running = context.tasks.first(where: { $0.id == id }) {
            if !running.isStanding {
                result.append(CommandSuggestion(id: "complete-\(id)", title: "„\(running.title)“ erledigt", detail: "Timer stoppt, die nächste Aufgabe kommt in den Fokus", symbol: "checkmark.circle", action: .complete(id)))
            }
            result.append(CommandSuggestion(id: "stop", title: "Timer stoppen", detail: "„\(running.title)“ anhalten", symbol: "stop.fill", action: .stop))
            result.append(CommandSuggestion(id: "lunch-start", title: "Mittagspause", detail: "Timer hält an, danach mit einem Klick weiter", symbol: "fork.knife", action: .startLunch))
        }
        let open = DayPlan.tasks(for: context.today, in: context.tasks).filter { !$0.isDone && $0.id != context.runningTaskID }
        for task in open.prefix(3) {
            result.append(CommandSuggestion(id: "start-\(task.id)", title: task.title, detail: taskDetail(task, context), symbol: "play.fill", action: .start(task.id)))
        }
        for task in DayPlan.standing(context.tasks).filter({ $0.id != context.runningTaskID }).prefix(2) {
            result.append(CommandSuggestion(id: "start-\(task.id)", title: task.title, detail: "Standardaufgabe · Timer starten", symbol: "pin", action: .start(task.id)))
        }
        // Morgens, bevor Zeit läuft: falls man krank ist
        if !context.absentToday, context.runningTaskID == nil, !context.lunchRunning, context.trackedTodaySeconds < 60 {
            result.append(absenceSuggestion((.sick, context.today, context.today, false), context))
        }
        result.append(CommandSuggestion(id: "open-close", title: CommandDestination.close.label, detail: "Zeiten prüfen, Worklogs senden", symbol: CommandDestination.close.symbol, action: .open(.close)))
        return Array(result.prefix(limit))
    }

    // MARK: Bausteine (öffentlich für Tests)

    /// Klein, ohne Umlaute und Akzente, ohne Ränder.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// „45m Telefonat“, „1h30 Doku“, „1,5 h Review“, „90 Minuten Workshop“ → Minuten und Rest.
    public static func leadingDuration(_ text: String) -> (minutes: Int, rest: String)? {
        let tokens = words(text)
        guard let first = tokens.first else { return nil }
        // „0:45 …“ ist eine Dauer, „9:30 …“ eine Uhrzeit
        if first.contains(":") {
            guard let minutes = DurationParser.minutes(from: first), minutes > 0, minutes < 4 * 60 else { return nil }
            return (minutes, tokens.dropFirst().joined(separator: " "))
        }
        if let minutes = DurationParser.minutes(from: first), minutes > 0 {
            return (minutes, tokens.dropFirst().joined(separator: " "))
        }
        guard tokens.count >= 2, let number = Double(first.replacingOccurrences(of: ",", with: ".")), number > 0 else { return nil }
        let unit = normalize(tokens[1])
        let factor: Double
        switch unit {
        case "m", "min", "min.", "minute", "minuten": factor = 1
        case "h", "std", "std.", "stunde", "stunden": factor = 60
        default: return nil
        }
        return (Int((number * factor).rounded()), tokens.dropFirst(2).joined(separator: " "))
    }

    /// „seit 9:30 Angebot“, „ab 14 Uhr Workshop“, „9.15 Doku“ → Uhrzeit heute und Rest.
    public static func sinceTime(_ text: String, on day: LocalDate, calendar: Calendar) -> (date: Date, rest: String)? {
        var tokens = words(text)
        guard !tokens.isEmpty else { return nil }
        var explicit = false
        if ["seit", "ab", "since"].contains(normalize(tokens[0])) {
            explicit = true
            tokens.removeFirst()
        }
        guard let first = tokens.first, let minutes = clockMinutes(first, explicit: explicit) else { return nil }
        tokens.removeFirst()
        if let next = tokens.first, normalize(next) == "uhr" { tokens.removeFirst() }
        let date = day.startDate(calendar: calendar).addingTimeInterval(TimeInterval(minutes * 60))
        return (date, tokens.joined(separator: " "))
    }

    /// „morgen …“, „heute …“, „montag …“, „neu …“, „+ …“, „später …“ → Tag (nil = Eingang) und Rest.
    public static func planned(_ text: String, today: LocalDate, calendar: Calendar) -> (day: LocalDate?, rest: String)? {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") {
            trimmed.removeFirst()
            return (today, trimmed.trimmingCharacters(in: .whitespaces))
        }
        var tokens = words(trimmed)
        guard tokens.count >= 2 else { return nil }
        let first = normalize(tokens[0])
        let day: LocalDate?
        switch first {
        case "heute", "neu", "neue": day = today
        case "morgen": day = today.adding(days: 1, calendar: calendar)
        case "ubermorgen": day = today.adding(days: 2, calendar: calendar)
        case "spater", "eingang", "irgendwann": day = nil
        default:
            guard let weekday = weekdays[first] else { return nil }
            let current = calendar.component(.weekday, from: today.startDate(calendar: calendar))
            var distance = (weekday - current + 7) % 7
            if distance == 0 { distance = 7 }
            day = today.adding(days: distance, calendar: calendar)
        }
        tokens.removeFirst()
        if first == "neue", let next = tokens.first, normalize(next) == "aufgabe" { tokens.removeFirst() }
        return (day, tokens.joined(separator: " "))
    }

    /// „krank“, „heute halber Tag krank“, „krank bis Freitag“, „Urlaub von Montag bis Freitag“, „krank 3 Tage“,
    /// „Urlaub 28.12. bis 2.1.“ → Art, Zeitraum und halber Tag (nur bei einem einzelnen Tag).
    public static func absence(_ text: String, today: LocalDate, calendar: Calendar) -> (kind: AbsenceKind, from: LocalDate, through: LocalDate, halfDay: Bool)? {
        let tokens = normalize(text).split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        let kind: AbsenceKind
        if tokens.contains(where: { $0.hasPrefix("krank") }) {
            kind = .sick
        } else if tokens.contains(where: { $0.hasPrefix("urlaub") }) {
            kind = .vacation
        } else {
            return nil
        }
        let half = tokens.contains { $0.hasPrefix("halb") || $0 == "½" }
        var from: LocalDate?
        var through: LocalDate?
        var dayCount: Int?
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "bis", index + 1 < tokens.count {
                through = absenceDay(tokens[index + 1], today: today, reference: from ?? today, calendar: calendar)
                index += 2
                continue
            }
            if let number = Int(token), index + 1 < tokens.count, tokens[index + 1].hasPrefix("tag") {
                dayCount = number
                index += 2
                continue
            }
            if from == nil, let day = absenceDay(token, today: today, reference: today, calendar: calendar) {
                from = day
            }
            index += 1
        }
        let start = from ?? today
        var end = through ?? start
        if let dayCount, dayCount > 1 { end = start.adding(days: dayCount - 1, calendar: calendar) }
        if end < start { end = start }
        return (kind, start, end, half && start == end)
    }

    /// Wie gut ein Aufgabentitel zur Eingabe passt (nil = gar nicht).
    public static func matchScore(title: String, query: String) -> Int? {
        let title = normalize(title)
        let query = normalize(query)
        guard !query.isEmpty else { return nil }
        if title == query { return 100 }
        if title.hasPrefix(query) { return 85 }
        let titleWords = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if titleWords.contains(where: { $0.hasPrefix(query) }) { return 70 }
        if title.contains(query) { return 50 }
        let queryWords = query.split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !queryWords.isEmpty else { return nil }
        let hits = queryWords.filter { word in titleWords.contains { $0.hasPrefix(word) } }
        if hits.count == queryWords.count { return 60 }
        if hits.count * 2 >= queryWords.count, hits.count >= 1 { return 35 }
        return nil
    }

    // MARK: Intern

    private static let weekdays: [String: Int] = [
        "sonntag": 1, "montag": 2, "dienstag": 3, "mittwoch": 4, "donnerstag": 5, "freitag": 6, "samstag": 7,
    ]

    /// „heute“, „morgen“, „Freitag“ (nächster ab `reference`, auch derselbe Tag), „28.11.“, „28.11.2026“.
    private static func absenceDay(_ token: String, today: LocalDate, reference: LocalDate, calendar: Calendar) -> LocalDate? {
        switch token {
        case "heute": return today
        case "morgen": return today.adding(days: 1, calendar: calendar)
        case "ubermorgen": return today.adding(days: 2, calendar: calendar)
        default:
            if let weekday = weekdays[token] {
                let current = calendar.component(.weekday, from: reference.startDate(calendar: calendar))
                return reference.adding(days: (weekday - current + 7) % 7, calendar: calendar)
            }
            let parts = token.split(separator: ".").compactMap { Int($0) }
            guard parts.count >= 2, (1...31).contains(parts[0]), (1...12).contains(parts[1]) else { return nil }
            var year = parts.count >= 3 ? parts[2] : today.year
            if year < 100 { year += 2000 }
            var day = LocalDate(year: year, month: parts[1], day: parts[0])
            // „2.1.“ im Dezember meint den Januar danach
            if parts.count < 3, day < today.adding(days: -31, calendar: calendar) {
                day = LocalDate(year: year + 1, month: parts[1], day: parts[0])
            }
            return day
        }
    }

    private static func absenceSuggestion(_ parsed: (kind: AbsenceKind, from: LocalDate, through: LocalDate, halfDay: Bool), _ context: CommandContext) -> CommandSuggestion {
        let what = parsed.kind == .sick ? "krank" : "Urlaub"
        let title: String
        if parsed.from == parsed.through {
            let day = capitalizedFirst(dayLabel(parsed.from, today: context.today, calendar: context.calendar))
            title = "\(day) \(parsed.halfDay ? "halber Tag " : "")\(what) eintragen"
        } else {
            let from = dayLabel(parsed.from, today: context.today, calendar: context.calendar)
            let through = dayLabel(parsed.through, today: context.today, calendar: context.calendar)
            title = "\(capitalizedFirst(what)) von \(from) bis \(through) eintragen"
        }
        let workdays = Absences.workdays(from: parsed.from, through: parsed.through, calendar: context.calendar).count
        let detail: String
        if workdays == 0 {
            detail = "Kein Arbeitstag im Zeitraum (Wochenende)"
        } else {
            let count = parsed.halfDay ? "½ Arbeitstag" : (workdays == 1 ? "1 Arbeitstag" : "\(workdays) Arbeitstage")
            detail = "\(count) · Wochenziel wird kleiner\(parsed.halfDay ? "" : ", offene Aufgaben rücken weiter")"
        }
        return CommandSuggestion(
            id: "absent-\(parsed.kind.rawValue)-\(parsed.from.string)-\(parsed.through.string)",
            title: title,
            detail: detail,
            symbol: parsed.kind.symbol,
            action: .absent(kind: parsed.kind, from: parsed.from, through: parsed.through, halfDay: parsed.halfDay)
        )
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    }

    /// „9:30“, „9.30“, „930“, „14“ (nur nach „seit“/„ab“) → Minuten seit Mitternacht.
    private static func clockMinutes(_ token: String, explicit: Bool) -> Int? {
        let parts = token.split(whereSeparator: { $0 == ":" || $0 == "." }).map(String.init)
        var hour: Int?
        var minute = 0
        if parts.count == 2 {
            hour = Int(parts[0])
            guard let value = Int(parts[1]), parts[1].count == 2 else { return nil }
            minute = value
        } else if parts.count == 1, explicit, let value = Int(parts[0]) {
            if parts[0].count >= 3 {
                hour = value / 100
                minute = value % 100
            } else {
                hour = value
            }
        }
        guard let hour, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        // Ohne „seit“ nur Uhrzeiten, die nach Arbeitszeit aussehen (sonst wäre „1:30“ eine Dauer)
        if !explicit, hour < 5 { return nil }
        return hour * 60 + minute
    }

    private static func keywordSuggestions(_ key: String, _ context: CommandContext) -> [CommandSuggestion] {
        var result: [CommandSuggestion] = []
        let stopWords = ["stop", "stopp", "stoppen", "anhalten", "timer stoppen"]
        let doneWords = ["erledigt", "fertig", "done", "abhaken"]
        let lunchWords = ["mittag", "mittagspause", "pause", "essen", "lunch"]
        let resumeWords = ["weiter", "zuruck", "pause beenden", "mittagspause beenden"]
        func matches(_ list: [String]) -> Bool {
            list.contains { $0 == key || ($0.hasPrefix(key) && key.count >= 3) }
        }
        if let id = context.runningTaskID, let running = context.tasks.first(where: { $0.id == id }) {
            if matches(doneWords), !running.isStanding {
                result.append(CommandSuggestion(id: "complete-\(id)", title: "„\(running.title)“ erledigt", detail: "Timer stoppt, die nächste Aufgabe kommt in den Fokus", symbol: "checkmark.circle", action: .complete(id)))
            }
            if matches(stopWords) {
                result.append(CommandSuggestion(id: "stop", title: "Timer stoppen", detail: "„\(running.title)“ anhalten", symbol: "stop.fill", action: .stop))
            }
        }
        if context.lunchRunning {
            if matches(resumeWords) || matches(lunchWords) {
                result.append(CommandSuggestion(id: "lunch-end", title: "Mittagspause beenden", detail: "Weiter mit der Aufgabe von vorher", symbol: "play.fill", action: .endLunch))
            }
        } else if matches(lunchWords) {
            result.append(CommandSuggestion(id: "lunch-start", title: "Mittagspause", detail: "Timer hält an, danach mit einem Klick weiter", symbol: "fork.knife", action: .startLunch))
        }
        return result
    }

    private static func looksLikeCommand(_ query: String) -> Bool {
        let key = normalize(query)
        let reserved = ["stop", "stopp", "stoppen", "anhalten", "erledigt", "fertig", "done", "mittag", "mittagspause", "pause", "weiter", "krank", "urlaub"]
        return reserved.contains(key) || CommandDestination.allCases.contains { $0.keywords.contains(key) }
    }

    private static func destinations(matching key: String) -> [CommandDestination] {
        guard key.count >= 3 else { return [] }
        return CommandDestination.allCases.filter { destination in
            destination.keywords.contains { $0.hasPrefix(key) } || normalize(destination.label).hasPrefix(key)
        }
    }

    /// Offene Aufgaben (mit Standardaufgaben), die zur Eingabe passen, beste zuerst.
    static func rankedTasks(for query: String, in context: CommandContext) -> [(TaskItem, Int)] {
        context.tasks
            .filter { !$0.isDone }
            .compactMap { task -> (TaskItem, Int)? in
                guard var score = matchScore(title: task.title, query: query) else { return nil }
                if task.plannedDate == context.today { score += 6 }
                if task.isStanding { score += 4 }
                if task.parentID != nil { score -= 3 }
                return (task, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.createdAt > rhs.0.createdAt
            }
    }

    private static func bestTask(for text: String, in context: CommandContext, minimumScore: Int) -> TaskItem? {
        guard let best = rankedTasks(for: text, in: context).first, best.1 >= minimumScore else { return nil }
        return best.0
    }

    /// Erster Kunde, dessen Name (oder erstes Wort davon) als Wort in der Eingabe steht.
    static func customer(in text: String, customers: [Customer]) -> UUID? {
        let tokens = Set(normalize(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        for customer in customers where !customer.isArchived {
            let nameWords = normalize(customer.name).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            guard let first = nameWords.first, first.count >= 3 else { continue }
            if tokens.contains(first) { return customer.id }
        }
        return nil
    }

    private static func customerName(_ id: UUID?, _ context: CommandContext) -> String? {
        guard let id else { return nil }
        return context.customers.first { $0.id == id }?.name
    }

    private static func customerSuffix(_ id: UUID?, _ context: CommandContext) -> String {
        customerName(id, context).map { " · \($0)" } ?? ""
    }

    private static func taskDetail(_ task: TaskItem, _ context: CommandContext) -> String {
        var parts: [String] = []
        if task.isStanding {
            parts.append("Standardaufgabe")
        } else if let day = task.plannedDate {
            parts.append(day == context.today ? "heute" : dayLabel(day, today: context.today, calendar: context.calendar))
        } else {
            parts.append("Eingang")
        }
        if let name = customerName(task.customerID, context) { parts.append(name) }
        parts.append("Timer starten")
        return parts.joined(separator: " · ")
    }

    public static func dayLabel(_ day: LocalDate?, today: LocalDate, calendar: Calendar) -> String {
        guard let day else { return "Eingang" }
        if day == today { return "heute" }
        if day == today.adding(days: 1, calendar: calendar) { return "morgen" }
        if day == today.adding(days: 2, calendar: calendar) { return "übermorgen" }
        let names = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
        let weekday = calendar.component(.weekday, from: day.startDate(calendar: calendar))
        return "\(names[weekday - 1]), \(day.day).\(day.month)."
    }

    private static func cleanTitle(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    private static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
