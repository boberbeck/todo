import Foundation
import TagwerkCore

public struct ToolError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Die Werkzeuge, die Claude über MCP nutzen kann. Arbeiten direkt auf der Tagwerk-Datenbank.
/// Buchungen nach ManageEngine oder SAP gibt es hier bewusst nicht; die bleiben in der App.
public final class TagwerkTools {
    public static let instructions = """
    Tagwerk ist die Aufgaben- und Zeiterfassungs-App des Nutzers (Mac). Aufgaben gehören optional zu einem Kunden, \
    haben einen geplanten Tag (sonst liegen sie im Eingang), eine Schätzung in Minuten, eine Arbeitsart \
    (Wartung, Störung, Projekt, Beratung) und ein PSP-Element für SAP. Es läuft höchstens ein Timer. \
    IDs aus den Antworten sind für Änderungen nötig; die ersten 8 Zeichen reichen. \
    Datumsangaben: heute, morgen, gestern, JJJJ-MM-TT oder TT.MM.JJJJ. Gebucht wird nur in der App selbst.
    """

    private let store: Store
    private let defaults: UserDefaults?
    private let calendar: Calendar
    private let now: () -> Date

    public init(store: Store, defaults: UserDefaults? = nil, calendar: Calendar = .current, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    public var names: [String] {
        definitions.compactMap { $0["name"] as? String }
    }

    // MARK: Beschreibung der Werkzeuge

    public var definitions: [[String: Any]] {
        [
            tool(
                "tagesuebersicht",
                "Aufgaben eines Tages (Standard: heute) mit Status, Schätzung, erfasster Zeit, Zeitblock und laufendem Timer.",
                properties: ["datum": text("Tag, z. B. heute oder 2026-11-19")]
            ),
            tool(
                "aufgaben",
                "Aufgaben suchen und auflisten, z. B. offene Aufgaben eines Kunden oder den Eingang.",
                properties: [
                    "status": choice(["offen", "erledigt", "alle"], "Standard: offen"),
                    "kunde": text("Kundenname oder Teil davon"),
                    "eingang": flag("true = nur Aufgaben ohne geplanten Tag"),
                    "suche": text("Text in Titel, Notiz oder Beschreibung"),
                    "limit": number("Höchstens so viele (Standard 50)"),
                ]
            ),
            tool(
                "aufgabe_anlegen",
                "Neue Aufgabe anlegen. Ohne Datum landet sie im Eingang. Eine Zeit am Titelende wie „1h30“ wird zur Schätzung.",
                properties: [
                    "titel": text("Titel der Aufgabe"),
                    "kunde": text("Kundenname"),
                    "datum": text("Geplanter Tag, z. B. heute; leer = Eingang"),
                    "schaetzung_min": number("Geschätzte Dauer in Minuten"),
                    "notizen": text("Notizen"),
                    "arbeitsart": choice(WorkType.allCases.map(\.label), "Art der Arbeit, legt die Leistung in SAP fest"),
                    "psp": text("PSP-Element in SAP ByDesign"),
                    "taetigkeit": text("Tätigkeit (Activity) aus SAP zum PSP-Element"),
                    "ticket": text("Ticketnummer aus ManageEngine; die Zeit geht dann auch als Worklog dorthin"),
                    "unteraufgabe_von": text("ID der übergeordneten Aufgabe; dann ist dies eine Unteraufgabe"),
                ],
                required: ["titel"]
            ),
            tool(
                "aufgabe_aendern",
                "Eine Aufgabe ändern: Titel, Notiz, Tag, Schätzung, Arbeitsart, PSP-Element mit Tätigkeit, Ticket, Beschreibung der Bearbeitung, Kunde oder erledigt.",
                properties: [
                    "id": text("ID der Aufgabe (die ersten 8 Zeichen reichen)"),
                    "titel": text("Neuer Titel"),
                    "notizen": text("Neue Notizen"),
                    "datum": text("Neuer Tag; „eingang“ nimmt die Aufgabe aus dem Plan"),
                    "schaetzung_min": number("Schätzung in Minuten, 0 entfernt sie"),
                    "arbeitsart": choice(WorkType.allCases.map(\.label) + ["keine"], "Arbeitsart"),
                    "psp": text("PSP-Element; leer entfernt es"),
                    "taetigkeit": text("Tätigkeit (Activity) aus SAP; leer entfernt sie"),
                    "ticket": text("Ticketnummer zuordnen; leer entfernt die Zuordnung"),
                    "beschreibung": text("Beschreibung der Bearbeitung (Text für Worklog und SAP)"),
                    "kunde": text("Kundenname; leer entfernt den Kunden"),
                    "erledigt": flag("true = erledigt, false = wieder offen"),
                ],
                required: ["id"]
            ),
            tool(
                "timer_starten",
                "Startet den Timer für eine Aufgabe. Ein laufender Timer wird dabei beendet.",
                properties: ["id": text("ID der Aufgabe")],
                required: ["id"]
            ),
            tool(
                "timer_stoppen",
                "Stoppt den laufenden Timer."
            ),
            tool(
                "zeitauswertung",
                "Erfasste Zeit in einem Zeitraum (Standard: diese Woche), summiert je Tag, Kunde, PSP-Element und Arbeitsart.",
                properties: [
                    "von": text("Erster Tag"),
                    "bis": text("Letzter Tag"),
                    "details": flag("true = auch die einzelnen Zeiteinträge"),
                ]
            ),
            tool(
                "tagesabschluss",
                "Was für einen Tag zu buchen ist: gerundete Zeit je Aufgabe, Status für SAP und ManageEngine und was noch fehlt.",
                properties: ["datum": text("Tag, Standard: heute")]
            ),
            tool(
                "kunden",
                "Alle Kunden mit PSP-Elementen, ManageEngine-Konto, offenen Aufgaben und Stunden im laufenden Monat."
            ),
            tool(
                "wochenziele",
                "Wochenziele einer Woche (Standard: diese Woche) mit erfasster Zeit.",
                properties: ["woche": text("Ein Tag in der gewünschten Woche")]
            ),
            tool(
                "wochenziel_anlegen",
                "Ein Wochenziel anlegen.",
                properties: [
                    "titel": text("Was soll in der Woche klappen?"),
                    "kunde": text("Kundenname"),
                    "woche": text("Ein Tag in der Woche, Standard: diese Woche"),
                ],
                required: ["titel"]
            ),
        ]
    }

    // MARK: Aufruf

    public func call(name: String, arguments: [String: Any]) throws -> String {
        switch name {
        case "tagesuebersicht": return try dayOverview(arguments)
        case "aufgaben": return try listTasks(arguments)
        case "aufgabe_anlegen": return try addTask(arguments)
        case "aufgabe_aendern": return try updateTask(arguments)
        case "timer_starten": return try startTimer(arguments)
        case "timer_stoppen": return try stopTimer()
        case "zeitauswertung": return try timeReport(arguments)
        case "tagesabschluss": return try dayClose(arguments)
        case "kunden": return try customers()
        case "wochenziele": return try weeklyGoals(arguments)
        case "wochenziel_anlegen": return try addWeeklyGoal(arguments)
        default: throw ToolError("Unbekanntes Werkzeug: \(name)")
        }
    }

    // MARK: Werkzeuge

    private func dayOverview(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        let day = try parseDay(string(arguments, "datum")) ?? today
        let dayTasks = DayPlan.tasks(for: day, in: snapshot.tasks)
        let leftovers = snapshot.tasks.filter { task in
            !task.isDone && (task.plannedDate.map { $0 < day } ?? false)
        }
        var result: [String: Any] = [
            "datum": day.string,
            "wochentag": weekdayName(day),
            "aufgaben": dayTasks.map { describe($0, in: snapshot, day: day) },
            "geplant_min": DayPlan.plannedMinutes(dayTasks.filter { !$0.isDone }),
            "erfasst_min": minutes(TimeMath.tracked(on: day, entries: snapshot.entries, now: now(), calendar: calendar)),
            "im_eingang": DayPlan.inbox(snapshot.tasks).count,
        ]
        if !leftovers.isEmpty, day == today {
            result["uebrig_von_frueher"] = leftovers.map { describe($0, in: snapshot, day: nil) }
        }
        if let running = runningInfo(snapshot) {
            result["laufender_timer"] = running
        }
        return json(result)
    }

    private func listTasks(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        var tasks = snapshot.tasks
        switch string(arguments, "status")?.lowercased() ?? "offen" {
        case "erledigt": tasks = tasks.filter(\.isDone)
        case "alle": break
        default: tasks = tasks.filter { !$0.isDone }
        }
        if let name = string(arguments, "kunde") {
            let customer = try resolveCustomer(name, in: snapshot.customers)
            tasks = tasks.filter { $0.customerID == customer.id }
        }
        if bool(arguments, "eingang") == true {
            tasks = tasks.filter { $0.plannedDate == nil && $0.parentID == nil }
        }
        if let query = string(arguments, "suche") {
            tasks = tasks.filter { task in
                [task.title, task.notes, task.workDescription].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
        }
        tasks.sort { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            switch (lhs.plannedDate, rhs.plannedDate) {
            case let (left?, right?) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.createdAt > rhs.createdAt
            }
        }
        let limit = max(1, int(arguments, "limit") ?? 50)
        return json([
            "anzahl": tasks.count,
            "aufgaben": tasks.prefix(limit).map { describe($0, in: snapshot, day: nil) },
        ])
    }

    private func addTask(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        guard let rawTitle = string(arguments, "titel") else { throw ToolError("Titel fehlt.") }
        let parsed = DurationParser.split(title: rawTitle)
        guard !parsed.title.isEmpty else { throw ToolError("Titel fehlt.") }
        let parent = try string(arguments, "unteraufgabe_von").map { reference -> TaskItem in
            let found = try resolveTask(reference, in: snapshot.tasks)
            return found.parentID.flatMap { id in snapshot.tasks.first { $0.id == id } } ?? found
        }
        let customer = try string(arguments, "kunde").map { try resolveCustomer($0, in: snapshot.customers) }
        var plannedDate: LocalDate?
        if parent == nil { plannedDate = try plannedDay(from: string(arguments, "datum")) }
        var task = TaskItem(
            title: parsed.title,
            notes: string(arguments, "notizen") ?? "",
            customerID: customer?.id ?? parent?.customerID,
            plannedDate: plannedDate,
            estimateMinutes: int(arguments, "schaetzung_min") ?? parsed.minutes,
            workType: try string(arguments, "arbeitsart").map { try workType($0) },
            pspElement: string(arguments, "psp"),
            sortIndex: parent.map { parent in DayPlan.nextSortIndex(in: DayPlan.subtasks(of: parent.id, in: snapshot.tasks)) }
                ?? DayPlan.nextSortIndex(in: snapshot.tasks.filter { $0.plannedDate == plannedDate && $0.parentID == nil }),
            createdAt: now(),
            parentID: parent?.id,
            sapActivity: sapActivityArgument(arguments)
        )
        if let number = string(arguments, "ticket") {
            assignTicket(number, to: &task, in: snapshot)
        }
        try store.save(task)
        let updated = try store.load()
        return json(["angelegt": describe(task, in: updated, day: nil)])
    }

    private func updateTask(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        var task = try resolveTask(string(arguments, "id") ?? "", in: snapshot.tasks)

        if let title = string(arguments, "titel") { task.title = title }
        if arguments["notizen"] != nil { task.notes = rawString(arguments, "notizen") ?? "" }
        if let description = rawString(arguments, "beschreibung") { task.workDescription = description }
        if arguments["datum"] != nil {
            let newDay = try plannedDay(from: string(arguments, "datum"))
            if newDay != task.plannedDate {
                task.plannedDate = newDay
                task.scheduledStart = nil
                task.sortIndex = DayPlan.nextSortIndex(in: snapshot.tasks.filter { $0.plannedDate == newDay })
            }
        }
        if let estimate = int(arguments, "schaetzung_min") { task.estimateMinutes = estimate > 0 ? estimate : nil }
        if arguments["arbeitsart"] != nil {
            if let value = string(arguments, "arbeitsart"), value.lowercased() != "keine" {
                task.workType = try workType(value)
            } else {
                task.workType = nil
            }
        }
        if arguments["psp"] != nil {
            task.pspElement = string(arguments, "psp")
            if task.pspElement == nil { task.sapActivity = nil }
        }
        if arguments["taetigkeit"] != nil { task.sapActivity = sapActivityArgument(arguments) }
        if arguments["ticket"] != nil {
            if let number = string(arguments, "ticket") {
                assignTicket(number, to: &task, in: snapshot)
            } else {
                task.ticketNumber = nil
                task.ticketKey = nil
            }
        }
        if arguments["kunde"] != nil {
            task.customerID = try string(arguments, "kunde").map { try resolveCustomer($0, in: snapshot.customers).id }
        }
        if let done = bool(arguments, "erledigt"), done != task.isDone {
            if done {
                task.status = .done
                task.completedAt = now()
                if let running = TimerLogic.running(in: snapshot.entries), running.taskID == task.id {
                    try persist(TimerLogic.stop(entries: snapshot.entries, at: now()))
                }
            } else {
                task.status = .open
                task.completedAt = nil
            }
        }
        try store.save(task)
        let updated = try store.load()
        return json(["geaendert": describe(task, in: updated, day: nil)])
    }

    private func startTimer(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        let task = try resolveTask(string(arguments, "id") ?? "", in: snapshot.tasks)
        guard !task.isDone else { throw ToolError("„\(task.title)“ ist schon erledigt.") }
        try persist(TimerLogic.start(taskID: task.id, entries: snapshot.entries, at: now()))
        let updated = try store.load()
        return json(["laeuft": runningInfo(updated) ?? [:]])
    }

    private func stopTimer() throws -> String {
        let snapshot = try store.load()
        guard let running = TimerLogic.running(in: snapshot.entries) else {
            return json(["meldung": "Es läuft kein Timer."])
        }
        let title = snapshot.tasks.first { $0.id == running.taskID }?.title ?? "Aufgabe"
        try persist(TimerLogic.stop(entries: snapshot.entries, at: now()))
        return json(["gestoppt": title, "minuten": minutes(running.duration(now: now()))])
    }

    private func timeReport(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        let first = try parseDay(string(arguments, "von")) ?? today.startOfWeek(calendar: calendar)
        let last = try parseDay(string(arguments, "bis")) ?? first.adding(days: 6, calendar: calendar)
        guard first <= last else { throw ToolError("„von“ liegt nach „bis“.") }
        let window = DateInterval(
            start: first.startDate(calendar: calendar),
            end: last.adding(days: 1, calendar: calendar).startDate(calendar: calendar)
        )
        let tasksByID = Dictionary(uniqueKeysWithValues: snapshot.tasks.map { ($0.id, $0) })
        let customersByID = Dictionary(uniqueKeysWithValues: snapshot.customers.map { ($0.id, $0) })

        var perDay: [[String: Any]] = []
        var cursor = first
        while cursor <= last {
            let seconds = TimeMath.tracked(on: cursor, entries: snapshot.entries, now: now(), calendar: calendar)
            perDay.append(["datum": cursor.string, "wochentag": weekdayName(cursor), "minuten": minutes(seconds)])
            cursor = cursor.adding(days: 1, calendar: calendar)
        }

        var perCustomer: [String: TimeInterval] = [:]
        var perPSP: [String: TimeInterval] = [:]
        var perWorkType: [String: TimeInterval] = [:]
        var details: [[String: Any]] = []
        var total: TimeInterval = 0
        for entry in snapshot.entries.sorted(by: { $0.start < $1.start }) {
            let seconds = TimeMath.overlap(of: entry, with: window, now: now())
            guard seconds > 0 else { continue }
            total += seconds
            let task = entry.taskID.flatMap { tasksByID[$0] }
            let customer = task?.customerID.flatMap { customersByID[$0] }?.name ?? "Ohne Kunde"
            perCustomer[customer, default: 0] += seconds
            perPSP[task?.pspElement ?? "ohne PSP", default: 0] += seconds
            perWorkType[task?.workType?.label ?? "ohne Arbeitsart", default: 0] += seconds
            if bool(arguments, "details") == true {
                details.append([
                    "datum": LocalDate(entry.start, calendar: calendar).string,
                    "beginn": clock(entry.start),
                    "ende": entry.end.map(clock) ?? "läuft",
                    "minuten": minutes(seconds),
                    "aufgabe": task?.title ?? "",
                    "kunde": customer,
                ])
            }
        }

        var result: [String: Any] = [
            "von": first.string,
            "bis": last.string,
            "summe_min": minutes(total),
            "summe": TimeMath.format(total) + " h",
            "je_tag": perDay,
            "je_kunde": ranked(perCustomer, key: "kunde"),
            "je_psp": ranked(perPSP, key: "psp"),
            "je_arbeitsart": ranked(perWorkType, key: "arbeitsart"),
        ]
        if bool(arguments, "details") == true {
            result["eintraege"] = details
        }
        return json(result)
    }

    private func dayClose(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        let day = try parseDay(string(arguments, "datum")) ?? today
        let rules = bookingRules
        let lines = DailyClose.lines(for: day, tasks: snapshot.tasks, entries: snapshot.entries, bookings: snapshot.bookings, rules: rules, now: now(), calendar: calendar)
        let described: [[String: Any]] = lines.map { line in
            var entry: [String: Any] = [
                "aufgabe": line.task.title,
                "id": line.task.id.uuidString,
                "minuten": line.minutes,
                "erfasst_min": minutes(line.trackedSeconds),
                "ziele": line.targets.map { target in
                    ["ziel": target.label, "status": line.status(for: target)?.label ?? "offen"]
                },
                "sap_kommentar": line.sapComment,
            ]
            if let psp = line.task.pspElement { entry["psp"] = psp }
            if let workType = line.task.workType { entry["arbeitsart"] = workType.label }
            if !line.openIssues.isEmpty { entry["fehlt"] = line.openIssues.map(\.message) }
            if line.changedAfterBooking { entry["hinweis"] = "Zeit nach dem Buchen geändert" }
            return entry
        }
        let openSAP = lines.filter { !($0.status(for: .sap)?.isDone ?? false) }.count
        let openME = lines.filter { $0.targets.contains(.manageEngine) && !($0.status(for: .manageEngine)?.isDone ?? false) }.count
        return json([
            "datum": day.string,
            "rundung_min": rules.roundingStep,
            "summe_min": lines.reduce(0) { $0 + $1.minutes },
            "zeilen": described,
            "offen_sap": openSAP,
            "offen_manageengine": openME,
        ])
    }

    private func customers() throws -> String {
        let snapshot = try store.load()
        let month = calendar.dateInterval(of: .month, for: now())
        let list: [[String: Any]] = snapshot.customers
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { customer in
                let taskIDs = Set(snapshot.tasks.filter { $0.customerID == customer.id }.map(\.id))
                let monthSeconds = month.map { interval in
                    snapshot.entries
                        .filter { entry in entry.taskID.map { taskIDs.contains($0) } ?? false }
                        .reduce(0) { $0 + TimeMath.overlap(of: $1, with: interval, now: now()) }
                } ?? 0
                var entry: [String: Any] = [
                    "id": customer.id.uuidString,
                    "name": customer.name,
                    "offene_aufgaben": snapshot.tasks.filter { $0.customerID == customer.id && !$0.isDone }.count,
                    "minuten_im_monat": minutes(monthSeconds),
                    "psp_elemente": snapshot.pspElements
                        .filter { $0.customerID == customer.id }
                        .map { psp -> [String: Any] in
                            var entry: [String: Any] = ["code": psp.code, "titel": psp.title, "aktiv": psp.isActive]
                            if let activity = psp.activity { entry["taetigkeit"] = activity }
                            return entry
                        },
                ]
                if let account = customer.manageEngineAccount { entry["manageengine_konto"] = account }
                return entry
            }
        return json(["kunden": list])
    }

    private func weeklyGoals(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        let week = (try parseDay(string(arguments, "woche")) ?? today).startOfWeek(calendar: calendar)
        let goals = snapshot.goals.filter { $0.weekStart == week }
        let customersByID = Dictionary(uniqueKeysWithValues: snapshot.customers.map { ($0.id, $0) })
        return json([
            "woche_ab": week.string,
            "ziele": goals.map { goal -> [String: Any] in
                var entry: [String: Any] = [
                    "id": goal.id.uuidString,
                    "titel": goal.title,
                    "erreicht": goal.isDone,
                    "erfasst_min": minutes(WeeklyReview.trackedSeconds(for: goal, tasks: snapshot.tasks, entries: snapshot.entries, now: now(), calendar: calendar)),
                ]
                if let customer = goal.customerID.flatMap({ customersByID[$0] }) { entry["kunde"] = customer.name }
                return entry
            },
        ])
    }

    private func addWeeklyGoal(_ arguments: [String: Any]) throws -> String {
        let snapshot = try store.load()
        guard let title = string(arguments, "titel") else { throw ToolError("Titel fehlt.") }
        let week = (try parseDay(string(arguments, "woche")) ?? today).startOfWeek(calendar: calendar)
        let customer = try string(arguments, "kunde").map { try resolveCustomer($0, in: snapshot.customers) }
        let goal = WeeklyGoal(weekStart: week, customerID: customer?.id, title: title, createdAt: now())
        try store.save(goal)
        return json(["angelegt": ["id": goal.id.uuidString, "titel": goal.title, "woche_ab": week.string]])
    }

    // MARK: Hilfen

    private var today: LocalDate { LocalDate(now(), calendar: calendar) }

    /// Rundung wie in den Einstellungen der App.
    private var bookingRules: BookingRules {
        let step = defaults?.integer(forKey: "roundingStepMinutes") ?? 0
        let mode = defaults?.string(forKey: "roundingMode").flatMap(RoundingMode.init(rawValue:)) ?? .nearest
        return BookingRules(roundingStep: step > 0 ? step : 15, roundingMode: mode)
    }

    private func persist(_ change: TimerLogic.Change) throws {
        for entry in change.discarded { try store.deleteEntry(id: entry.id) }
        for entry in change.stopped { try store.save(entry) }
        if let started = change.started { try store.save(started) }
    }

    private func runningInfo(_ snapshot: Snapshot) -> [String: Any]? {
        guard let running = TimerLogic.running(in: snapshot.entries) else { return nil }
        let task = snapshot.tasks.first { $0.id == running.taskID }
        return [
            "aufgabe": task?.title ?? "",
            "id": running.taskID?.uuidString ?? "",
            "seit": clock(running.start),
            "minuten_dieser_lauf": minutes(running.duration(now: now())),
        ]
    }

    private func sapActivityArgument(_ arguments: [String: Any]) -> String? {
        string(arguments, "taetigkeit")
    }

    /// Ordnet ein Ticket über seine Nummer zu. Die interne ID kommt von einem Ticket, das schon in Tagwerk liegt.
    private func assignTicket(_ rawNumber: String, to task: inout TaskItem, in snapshot: Snapshot) {
        guard task.source != .ticket else { return }
        let number = rawNumber.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let known = snapshot.tasks.first { $0.source == .ticket && $0.linkedTicketNumber == number }
        task.ticketNumber = number
        task.ticketKey = known?.linkedTicketKey
    }

    private func describe(_ task: TaskItem, in snapshot: Snapshot, day: LocalDate?) -> [String: Any] {
        let parent = task.parentID.flatMap { id in snapshot.tasks.first { $0.id == id } }
        let effective = task.resolved(parent: parent)
        var entry: [String: Any] = [
            "id": task.id.uuidString,
            "titel": task.title,
            "status": task.isDone ? "erledigt" : "offen",
            "quelle": task.source.label,
            "geplant_fuer": task.plannedDate?.string ?? "Eingang",
            "erfasst_min": minutes(TimeMath.tracked(taskID: task.id, entries: snapshot.entries, now: now())),
        ]
        if let customer = snapshot.customers.first(where: { $0.id == task.customerID }) { entry["kunde"] = customer.name }
        if let number = effective.linkedTicketNumber { entry["ticket"] = number }
        if let parent {
            entry["unteraufgabe_von"] = ["id": parent.id.uuidString, "titel": parent.title]
        }
        let subtasks = DayPlan.subtasks(of: task.id, in: snapshot.tasks)
        if !subtasks.isEmpty {
            entry["unteraufgaben"] = subtasks.map { ["id": $0.id.uuidString, "titel": $0.title, "erledigt": $0.isDone] as [String: Any] }
        }
        if let start = task.scheduledStart { entry["zeitblock"] = clock(start) }
        if let estimate = task.estimateMinutes { entry["schaetzung_min"] = estimate }
        if let workType = task.workType { entry["arbeitsart"] = workType.label }
        if let psp = effective.pspElement { entry["psp"] = psp }
        if let activity = effective.sapActivity { entry["taetigkeit"] = activity }
        if !task.workDescription.isEmpty { entry["beschreibung"] = task.workDescription }
        if !task.notes.isEmpty { entry["notizen"] = task.notes }
        if let goal = snapshot.goals.first(where: { $0.id == task.goalID }) { entry["wochenziel"] = goal.title }
        if let day {
            entry["erfasst_an_dem_tag_min"] = minutes(TimeMath.tracked(taskID: task.id, on: day, entries: snapshot.entries, now: now(), calendar: calendar))
        }
        if TimerLogic.running(in: snapshot.entries)?.taskID == task.id { entry["timer_laeuft"] = true }
        return entry
    }

    func resolveTask(_ reference: String, in tasks: [TaskItem]) throws -> TaskItem {
        let key = reference.trimmingCharacters(in: .whitespaces).lowercased()
        guard key.count >= 4 else { throw ToolError("Bitte die ID der Aufgabe angeben (mindestens 4 Zeichen).") }
        let matches = tasks.filter { $0.id.uuidString.lowercased().hasPrefix(key) }
        guard let first = matches.first else { throw ToolError("Keine Aufgabe mit der ID „\(reference)“.") }
        guard matches.count == 1 else { throw ToolError("Die ID „\(reference)“ ist nicht eindeutig.") }
        return first
    }

    func resolveCustomer(_ name: String, in customers: [Customer]) throws -> Customer {
        if let id = UUID(uuidString: name), let match = customers.first(where: { $0.id == id }) { return match }
        let active = customers.filter { !$0.isArchived }
        if let exact = active.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return exact
        }
        let matches = active.filter { $0.name.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty {
            let known = active.map(\.name).joined(separator: ", ")
            throw ToolError("Kein Kunde „\(name)“. Vorhanden: \(known.isEmpty ? "keine" : known).")
        }
        throw ToolError("„\(name)“ passt auf mehrere Kunden: \(matches.map(\.name).joined(separator: ", ")).")
    }

    func workType(_ value: String) throws -> WorkType {
        let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if let match = WorkType.allCases.first(where: {
            $0.rawValue == key || $0.label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) == key
        }) {
            return match
        }
        throw ToolError("Unbekannte Arbeitsart „\(value)“. Erlaubt: \(WorkType.allCases.map(\.label).joined(separator: ", ")).")
    }

    /// `nil` = kein Datum angegeben.
    func parseDay(_ text: String?) throws -> LocalDate? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        switch text.lowercased() {
        case "heute", "today": return today
        case "morgen", "tomorrow": return today.adding(days: 1, calendar: calendar)
        case "übermorgen": return today.adding(days: 2, calendar: calendar)
        case "gestern", "yesterday": return today.adding(days: -1, calendar: calendar)
        default: break
        }
        if let iso = LocalDate(string: text) { return iso }
        let parts = text.split(separator: ".").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[0]) {
            return LocalDate(year: parts[2] < 100 ? 2000 + parts[2] : parts[2], month: parts[1], day: parts[0])
        }
        if parts.count == 2, (1...12).contains(parts[1]), (1...31).contains(parts[0]) {
            return LocalDate(year: today.year, month: parts[1], day: parts[0])
        }
        throw ToolError("Unbekanntes Datum „\(text)“. Erlaubt: heute, morgen, gestern, JJJJ-MM-TT oder TT.MM.JJJJ.")
    }

    /// Wie `parseDay(_:)`, aber „eingang“ oder leer heißt: kein geplanter Tag.
    private func plannedDay(from text: String?) throws -> LocalDate? {
        guard let text, text.lowercased() != "eingang" else { return nil }
        return try parseDay(text)
    }

    private func weekdayName(_ day: LocalDate) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: day.startDate(calendar: calendar))
    }

    private func clock(_ date: Date) -> String {
        let minutes = FreeTime.minutesSinceMidnight(date, calendar: calendar)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func minutes(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded())
    }

    private func ranked(_ totals: [String: TimeInterval], key: String) -> [[String: Any]] {
        totals
            .sorted { $0.value > $1.value }
            .map { [key: $0.key, "minuten": minutes($0.value)] }
    }

    private func json(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return String(describing: object)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func tool(_ name: String, _ description: String, properties: [String: [String: Any]] = [:], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    private func text(_ description: String) -> [String: Any] { ["type": "string", "description": description] }

    private func number(_ description: String) -> [String: Any] { ["type": "integer", "description": description] }

    private func flag(_ description: String) -> [String: Any] { ["type": "boolean", "description": description] }

    private func choice(_ values: [String], _ description: String) -> [String: Any] {
        ["type": "string", "enum": values, "description": description]
    }

    /// Getrimmter Text, leer = `nil`.
    private func string(_ arguments: [String: Any], _ key: String) -> String? {
        guard let value = rawString(arguments, key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func rawString(_ arguments: [String: Any], _ key: String) -> String? {
        switch arguments[key] {
        case let text as String: return text
        case let number as Int: return String(number)
        default: return nil
        }
    }

    private func int(_ arguments: [String: Any], _ key: String) -> Int? {
        switch arguments[key] {
        case let number as Int: return number
        case let number as Double: return Int(number)
        case let text as String: return Int(text)
        default: return nil
        }
    }

    private func bool(_ arguments: [String: Any], _ key: String) -> Bool? {
        switch arguments[key] {
        case let flag as Bool: return flag
        case let text as String: return ["true", "ja", "1", "yes"].contains(text.lowercased())
        default: return nil
        }
    }
}
