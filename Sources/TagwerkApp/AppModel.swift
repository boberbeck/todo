import AppKit
import CoreGraphics
import Foundation
import Observation
import TagwerkCore

/// Seiten der App. Oben in der Leiste: Start, Plan, Kalender, Fokus, Kunden, Rückblick.
/// „Tag planen“ und „Tag abschließen“ sind Rituale, die man von Start aus öffnet.
enum SidebarItem: Hashable {
    case today
    case week
    case calendar
    case focus
    case customers
    case goals
    case review
    case planning
    case close
    case customer(UUID)
}

/// Zentraler Zustand der App. Hält alle Daten im Speicher und schreibt jede Änderung sofort in die Datenbank.
@MainActor
@Observable
final class AppModel {
    private(set) var customers: [Customer] = []
    private(set) var tasks: [TaskItem] = []
    private(set) var entries: [TimeEntry] = []
    private(set) var bookings: [Booking] = []
    private(set) var goals: [WeeklyGoal] = []
    /// Lange Ziele über Wochen (z. B. „AZ-305 bestehen“)
    private(set) var longGoals: [LongGoal] = []
    /// Krank- und Urlaubstage
    private(set) var absences: [Absence] = []
    /// Pausen (zählen nicht als Arbeitszeit)
    private(set) var breaks: [WorkBreak] = []
    /// Meetings mit Transkript
    private(set) var meetings: [Meeting] = []
    /// Offenes Meeting-Fenster (Doppelklick auf einen Termin)
    var meetingContext: MeetingContext?
    /// Befehlszeile (⌘K) offen, mit ihrer Eingabe
    var showsCommandBar = false
    var commandQuery = ""
    /// Kurze Rückmeldung unten im Fenster, z. B. nach einem Befehl
    private(set) var toast: Toast?
    /// Offenes Fenster „Mittagspause nachtragen“ oder „Mittagspause bearbeiten“
    var breakDraft: BreakDraft?
    /// Offenes Fenster „Abwesenheit eintragen“
    var absenceDraft: AbsenceDraft?
    /// Erkannte Pause während eines laufenden Timers, wartet auf eine Entscheidung.
    var idlePrompt: IdlePrompt?
    private(set) var inboxMessage: String?
    private(set) var lastTicketSync: Date?
    private(set) var ticketSyncMessage: String?
    /// Genaues Ergebnis des letzten Abrufs, für die Einstellungen (Fehlersuche).
    private(set) var ticketSyncDetail: String?
    private(set) var isSyncingTickets = false
    private(set) var isSendingBookings = false

    var selection: SidebarItem? = .today
    /// Wohin der Pfeil im Fokus zurückführt. Setzt die Hauptansicht beim Wechsel in den Fokus.
    @ObservationIgnored var focusReturn: SidebarItem?
    /// Musik im Fokus (Apple Music).
    let music = FocusMusic()
    /// Fernzugriff für Claude im Browser und auf dem Handy
    let remote = RemoteAccess()
    /// Updates aus dem Release „aktuell“
    let updater = Updater()
    /// Aufgabe, die im Fokus-Modus gezeigt wird. Ohne Auswahl: die laufende oder die nächste offene.
    var focusedTaskID: UUID?
    /// Wird hochgezählt, wenn per ⌘N eine neue Aufgabe angelegt werden soll.
    private(set) var newTaskRequest = 0
    /// Aufgaben, deren Unteraufgaben aufgeklappt sind.
    var expandedTaskIDs: Set<UUID> = []
    /// Aufgabe, in der das Feld „Unteraufgabe hinzufügen“ den Fokus bekommen soll.
    var subtaskEntryTaskID: UUID?
    /// Aufgabe, für die gerade ein Ticket gesucht wird (öffnet die Ticketsuche).
    var ticketPickerTaskID: UUID?
    /// Offenes Fenster „Zeit nachtragen“ (von überall aus der App).
    var timeEntryDraft: TimeEntryDraft?
    /// Erfasster Eintrag, der gerade im Fenster „Zeit bearbeiten“ offen ist (Doppelklick im Kalender).
    var editingEntry: TimeEntry?
    /// Neue Aufgabe, die gerade im Kalender beschriftet wird (Doppelklick in eine freie Stelle).
    var calendarNewSlot: DateInterval?
    /// Fenster „Fehler melden“
    var showsBugReport = false
    /// Aufgabe, die im Aufgabenfenster offen ist (Doppelklick)
    var detailTaskID: UUID?
    /// Absturzbericht von macOS seit dem letzten Start, noch nicht gemeldet
    var pendingCrash: URL?
    var lastError: String?

    /// Aktuelle Uhrzeit, jede Sekunde aktualisiert. Nur lesen, wo ein Timer sichtbar läuft.
    private(set) var now = Date()
    private(set) var today = LocalDate.today()

    /// Termine des heutigen Tages aus den sichtbaren Kalendern.
    private(set) var events: [CalendarEvent] = []
    private(set) var calendarAccess: CalendarAccess = .notDetermined
    /// Aufgaben, die heute früh von gestern übernommen wurden (für die Tagesplanung).
    private(set) var rolledOverIDs: Set<UUID> = []
    private(set) var lastPlannedDay: LocalDate?
    /// Wird bei Änderungen in den Einstellungen hochgezählt, damit abhängige Ansichten neu rechnen.
    private(set) var settingsVersion = 0

    private let store: Store
    private let calendarProvider: CalendarProviding
    private let manageEngine = ManageEngineClient()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var tickCount = 0
    /// Letzter Stand der Datenbank, um Änderungen von außen (Claude über MCP) zu bemerken.
    @ObservationIgnored private var lastChangeToken: Int?
    @ObservationIgnored private var idleSince: Date?
    /// Tickets, deren Betreff ManageEngine in dieser Sitzung nicht liefern konnte (nicht ständig neu fragen)
    @ObservationIgnored private var ticketTitleMisses: Set<String> = []
    @ObservationIgnored private var quickCaptureController: QuickCaptureController?

    private var quickCapture: QuickCaptureController {
        if let existing = quickCaptureController { return existing }
        let created = QuickCaptureController(model: self)
        quickCaptureController = created
        return created
    }

    init(store: Store, calendar: CalendarProviding) {
        self.store = store
        self.calendarProvider = calendar
        Preferences.registerDefaults()
        lastPlannedDay = UserDefaults.standard.string(forKey: Preferences.lastPlannedDayKey).flatMap { LocalDate(string: $0) }
        reload()
        rollOverOpenTasks()
        if !SnapshotMode.usesDemoData {
            seedStandingTasksIfNeeded()
            SAPCleanup.runOnce()
        }
        calendarAccess = calendar.access
        calendar.onChange = { [weak self] in
            self?.refreshEvents()
        }
        refreshEvents()
        startTicker()
        if SnapshotMode.directory == nil {
            showPlanningIfDue()
            backupIfDue()
            AppLog.info("Start", "Tagwerk \(AppVersion.description), \(SigningSetup.currentSignature), Kalender: \(calendarAccess)")
            if let crash = BugReport.unreportedCrash() {
                AppLog.warning("Start", "Absturzbericht gefunden: \(crash.lastPathComponent)")
                pendingCrash = crash
                showsBugReport = true
            }
            remote.startIfEnabled()
            if isPomodoroEnabled { PomodoroNotifier.requestPermission() }
            if let commit = Updater.takeJustInstalled() {
                AppLog.info("Update", "Neu gestartet mit Stand \(commit)")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    self?.showToast("Tagwerk wurde aktualisiert (Stand \(commit))", symbol: "arrow.down.circle")
                }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.updater.checkIfDue()
            }
        }
    }

    static func live() -> AppModel {
        if SnapshotMode.usesDemoData {
            return AppModel(store: InMemoryStore(DemoData.snapshot()), calendar: DemoCalendar())
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tagwerk", isDirectory: true)
        let url = folder.appendingPathComponent("tagwerk.sqlite")
        do {
            return AppModel(store: try SQLiteStore(url: url), calendar: EventKitCalendar())
        } catch {
            let model = AppModel(store: InMemoryStore(), calendar: EventKitCalendar())
            model.lastError = "Die Datenbank konnte nicht geöffnet werden. Änderungen werden nicht gespeichert.\n\(error)"
            return model
        }
    }

    // MARK: Lesen

    var activeCustomers: [Customer] {
        customers
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var todayTasks: [TaskItem] { DayPlan.tasks(for: today, in: tasks) }

    var inboxTasks: [TaskItem] { DayPlan.inbox(tasks) }

    var doneToday: [TaskItem] {
        tasks
            .filter { task in
                guard task.isDone, task.parentID == nil, let completed = task.completedAt else { return false }
                return LocalDate(completed) == today
            }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
    }

    var runningEntry: TimeEntry? { TimerLogic.running(in: entries) }

    var runningTask: TaskItem? { task(runningEntry?.taskID) }

    /// Die Aufgabe für den Fokus-Modus.
    var focusTask: TaskItem? {
        if let focused = task(focusedTaskID), !focused.isDone { return focused }
        if let running = runningTask { return running }
        return todayTasks.first { !$0.isDone }
    }

    func task(_ id: UUID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    func customer(_ id: UUID?) -> Customer? {
        guard let id else { return nil }
        return customers.first { $0.id == id }
    }

    func isRunning(_ taskID: UUID) -> Bool {
        runningEntry?.taskID == taskID
    }

    func tracked(taskID: UUID, now: Date) -> TimeInterval {
        TimeMath.tracked(taskID: taskID, entries: entries, now: now)
    }

    func trackedToday(now: Date) -> TimeInterval {
        TimeMath.tracked(on: today, entries: entries, now: now)
    }

    func tracked(on day: LocalDate) -> TimeInterval {
        TimeMath.tracked(on: day, entries: entries, now: now)
    }

    /// Erfasste Zeit je Kunde in einem Zeitraum, absteigend sortiert. Aufgaben ohne Kunde unter `nil`.
    func trackedByCustomer(from firstDay: LocalDate, through lastDay: LocalDate) -> [(customerID: UUID?, seconds: TimeInterval)] {
        let interval = DateInterval(
            start: firstDay.startDate(),
            end: lastDay.adding(days: 1).startDate()
        )
        var totals: [UUID?: TimeInterval] = [:]
        for entry in entries {
            let seconds = TimeMath.overlap(of: entry, with: interval, now: now)
            guard seconds > 0 else { continue }
            let customerID = task(entry.taskID)?.customerID
            totals[customerID, default: 0] += seconds
        }
        return totals
            .map { (customerID: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// Aufgaben eines Kunden: offene neueste zuerst, erledigte zuletzt erledigt zuerst.
    func customerTasks(_ customerID: UUID, done: Bool) -> [TaskItem] {
        let matching = tasks.filter { $0.customerID == customerID && $0.isDone == done && $0.parentID == nil && !$0.isStanding }
        if done {
            return matching.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
        return matching.sorted { $0.createdAt > $1.createdAt }
    }

    func openTaskCount(for customerID: UUID) -> Int {
        tasks.filter { $0.customerID == customerID && !$0.isDone && $0.parentID == nil && !$0.isStanding }.count
    }

    func trackedThisMonth(customerID: UUID) -> TimeInterval {
        guard let month = Calendar.current.dateInterval(of: .month, for: today.startDate()) else { return 0 }
        let taskIDs = Set(tasks.filter { $0.customerID == customerID }.map(\.id))
        return entries
            .filter { entry in entry.taskID.map { taskIDs.contains($0) } ?? false }
            .reduce(0) { $0 + TimeMath.overlap(of: $1, with: month, now: Date()) }
    }

    func doneCount(on day: LocalDate) -> Int {
        tasks.filter { task in
            guard task.isDone, task.parentID == nil, let completed = task.completedAt else { return false }
            return LocalDate(completed) == day
        }.count
    }

    /// Erfasste Zeit einer Aufgabe samt ihrer Unteraufgaben.
    func trackedIncludingSubtasks(taskID: UUID, now: Date) -> TimeInterval {
        subtasks(of: taskID).reduce(tracked(taskID: taskID, now: now)) { $0 + tracked(taskID: $1.id, now: now) }
    }

    /// "0:23 / 0:30" – erfasst (mit Unteraufgaben) / geplant.
    func timeLabel(for task: TaskItem, now: Date) -> String {
        let tracked = TimeMath.format(trackedIncludingSubtasks(taskID: task.id, now: now))
        guard let estimate = task.estimateMinutes else { return tracked }
        return "\(tracked) / \(TimeMath.format(minutes: estimate))"
    }

    // MARK: Aufgaben

    @discardableResult
    func addTask(title rawTitle: String, customerID: UUID?, plannedDate: LocalDate?) -> TaskItem? {
        let parsed = DurationParser.split(title: rawTitle)
        guard !parsed.title.isEmpty else { return nil }
        let siblings = tasks.filter { $0.plannedDate == plannedDate }
        let task = TaskItem(
            title: parsed.title,
            customerID: customerID,
            plannedDate: plannedDate,
            estimateMinutes: parsed.minutes,
            sortIndex: DayPlan.nextSortIndex(in: siblings)
        )
        persist(task)
        return task
    }

    func update(_ task: TaskItem) {
        persist(task)
    }

    func toggleDone(_ id: UUID) {
        guard let task = self.task(id) else { return }
        if task.isDone {
            reopen(id)
        } else {
            complete(id)
        }
    }

    /// Erledigt die Aufgabe, stoppt ihren Timer und holt im Fokus die nächste.
    func complete(_ id: UUID) {
        // Standardaufgaben wie „Organisatorisches“ werden nie erledigt
        guard var task = self.task(id), !task.isDone, !task.isStanding else { return }
        if isRunning(id) { stopTracking() }
        let parent = task.parentID.flatMap { self.task($0) }
        let next = parent.flatMap { $0.isDone ? nil : $0 } ?? DayPlan.nextOpenTask(after: id, in: todayTasks)
        task.status = .done
        task.completedAt = Date()
        persist(task)
        if focusedTaskID == id || focusedTaskID == nil {
            focusedTaskID = next?.id
        }
    }

    func reopen(_ id: UUID) {
        guard var task = self.task(id) else { return }
        task.status = .open
        task.completedAt = nil
        persist(task)
    }

    /// Plant eine Aufgabe für einen Tag ein (`nil` = zurück in den Eingang).
    func plan(_ id: UUID, for requestedDay: LocalDate?) {
        guard var task = self.task(id), !task.isStanding else { return }
        let day = normalizedDay(requestedDay, for: task)
        guard task.plannedDate != day else { return }
        task.plannedDate = day
        if task.isSubtask {
            // Die Reihenfolge unter der Aufgabe bleibt; am Tag kommt sie ans Ende.
            task.daySortIndex = day.map { DayPlan.nextDayIndex(in: dayTasks($0)) }
        } else {
            task.sortIndex = DayPlan.nextSortIndex(in: tasks.filter { $0.plannedDate == day })
        }
        if task.scheduledStart != nil {
            task.scheduledStart = nil
            syncBlock(&task)
        }
        persist(task)
    }

    /// Eine Unteraufgabe am Tag ihrer Aufgabe braucht keinen eigenen: sie steht dort darunter und zieht mit ihr um.
    private func normalizedDay(_ day: LocalDate?, for task: TaskItem) -> LocalDate? {
        guard task.isSubtask, let day, day == parent(of: task)?.plannedDate else { return day }
        return nil
    }

    /// Tag, an dem eine Aufgabe dran ist: ihr eigener, bei Unteraufgaben sonst der ihrer Aufgabe.
    func effectiveDay(of task: TaskItem) -> LocalDate? {
        task.plannedDate ?? (task.isSubtask ? parent(of: task)?.plannedDate : nil)
    }

    /// Unteraufgabe mit eigenem Tag (anders als ihre Aufgabe)?
    func isPlannedOnItsOwn(_ task: TaskItem) -> Bool {
        guard task.isSubtask, let day = task.plannedDate else { return false }
        return parent(of: task)?.plannedDate != day
    }

    func moveTodayTasks(from source: IndexSet, to destination: Int) {
        for task in DayPlan.reorder(todayTasks, from: source, to: destination) {
            persist(task)
        }
    }

    func delete(_ id: UUID) {
        for subtask in subtasks(of: id) {
            delete(subtask.id)
        }
        if var task = self.task(id), task.calendarEventID != nil {
            task.scheduledStart = nil
            syncBlock(&task)
        }
        do {
            try store.deleteTask(id: id)
            tasks.removeAll { $0.id == id }
            entries.removeAll { $0.taskID == id }
            bookings.removeAll { $0.taskID == id }
            if focusedTaskID == id { focusedTaskID = nil }
        } catch {
            report(error)
        }
    }

    /// Öffnet das Aufgabenfenster mit allen Angaben (Doppelklick auf eine Aufgabe).
    func openDetail(_ id: UUID) {
        detailTaskID = id
    }

    func setTitle(_ text: String, for id: UUID) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, var task = self.task(id), task.title != clean else { return }
        task.title = clean
        persist(task)
    }

    func setNotes(_ text: String, for id: UUID) {
        guard var task = self.task(id), task.notes != text else { return }
        task.notes = text
        persist(task)
    }

    /// Zeiteinträge einer Aufgabe, neueste zuerst.
    func entries(forTask id: UUID) -> [TimeEntry] {
        entries.filter { $0.taskID == id }.sorted { $0.start > $1.start }
    }

    func setDescription(_ text: String, for id: UUID) {
        guard var task = self.task(id), task.workDescription != text else { return }
        task.workDescription = text
        persist(task)
    }

    func setEstimate(_ minutes: Int?, for id: UUID) {
        guard var task = self.task(id), task.estimateMinutes != minutes else { return }
        task.estimateMinutes = minutes
        persist(task)
    }

    /// Kunde setzen. Unteraufgaben mit dem bisherigen Kunden ziehen mit.
    func setCustomer(_ customerID: UUID?, for id: UUID) {
        guard var task = self.task(id), task.customerID != customerID else { return }
        let previous = task.customerID
        task.customerID = customerID
        persist(task)
        for var subtask in subtasks(of: id) where subtask.customerID == previous {
            subtask.customerID = customerID
            persist(subtask)
        }
    }

    // MARK: Unteraufgaben

    func subtasks(of id: UUID) -> [TaskItem] { DayPlan.subtasks(of: id, in: tasks) }

    func parent(of task: TaskItem) -> TaskItem? { task.parentID.flatMap { self.task($0) } }

    /// Aufgabe mit allem, was sie von der übergeordneten erbt (Kunde, Ticket …).
    func resolved(_ task: TaskItem) -> TaskItem { task.resolved(parent: parent(of: task)) }

    /// Legt eine Unteraufgabe an. Eine Ebene reicht: Unteraufgaben einer Unteraufgabe hängen an der obersten Aufgabe.
    @discardableResult
    func addSubtask(title rawTitle: String, to parentID: UUID) -> TaskItem? {
        guard let direct = task(parentID) else { return nil }
        let parent = self.parent(of: direct) ?? direct
        let parsed = DurationParser.split(title: rawTitle)
        guard !parsed.title.isEmpty else { return nil }
        let subtask = TaskItem(
            title: parsed.title,
            customerID: parent.customerID,
            estimateMinutes: parsed.minutes,
            sortIndex: DayPlan.nextSortIndex(in: subtasks(of: parent.id)),
            parentID: parent.id
        )
        persist(subtask)
        expandedTaskIDs.insert(parent.id)
        return subtask
    }

    /// Klappt die Unteraufgaben auf und setzt den Cursor in „Unteraufgabe hinzufügen“.
    func beginSubtaskEntry(for id: UUID) {
        guard let task = self.task(id) else { return }
        let parentID = task.parentID ?? task.id
        expandedTaskIDs.insert(parentID)
        subtaskEntryTaskID = parentID
    }

    func toggleSubtasks(_ id: UUID) {
        if expandedTaskIDs.contains(id) {
            expandedTaskIDs.remove(id)
        } else {
            expandedTaskIDs.insert(id)
        }
    }

    /// Macht aus einer Unteraufgabe wieder eine eigene Aufgabe (im Eingang).
    func promoteSubtask(_ id: UUID) {
        guard var task = self.task(id), task.parentID != nil else { return }
        let effective = resolved(task)
        task.parentID = nil
        task.ticketNumber = effective.ticketNumber
        task.ticketKey = effective.ticketKey
        task.ticketTitle = effective.ticketTitle
        task.worklogType = effective.worklogType
        let day = task.plannedDate
        let position = task.daySortIndex ?? DayPlan.nextSortIndex(in: tasks.filter { $0.plannedDate == day })
        task.sortIndex = position
        task.daySortIndex = nil
        persist(task)
    }

    // MARK: Ticket zuordnen

    /// Tickets aus ManageEngine, die in Tagwerk liegen: offene zuerst, dann zuletzt angelegte.
    var ticketTasks: [TaskItem] {
        tasks
            .filter { $0.source == .ticket }
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// Das Ticket einer Aufgabe: eigenes, zugeordnetes oder von der übergeordneten Aufgabe geerbtes.
    func ticketNumber(for task: TaskItem) -> String? {
        resolved(task).linkedTicketNumber
    }

    /// Ordnet der Aufgabe ein Ticket zu, das schon in Tagwerk liegt. Die Zeit geht dann auch als Worklog an dieses Ticket.
    func linkTicket(_ ticket: TaskItem, to id: UUID) {
        guard ticket.id != id else { return }
        setTicket(number: ticket.linkedTicketNumber, key: ticket.linkedTicketKey, title: ticket.source == .ticket ? ticket.title : ticket.ticketTitle, for: id)
        if let task = self.task(id), task.customerID == nil, let customerID = ticket.customerID {
            setCustomer(customerID, for: id)
        }
    }

    /// Ordnet ein Ticket über seine Nummer zu. Fragt ManageEngine nach der internen ID, wenn es eingerichtet ist.
    func linkTicket(number rawNumber: String, to id: UUID) async -> String? {
        let number = rawNumber.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !number.isEmpty else { return nil }
        if let known = ticketTasks.first(where: { $0.linkedTicketNumber == number }) {
            linkTicket(known, to: id)
            return nil
        }
        guard manageEngine.isReady else {
            setTicket(number: number, key: nil, for: id)
            return "Ticket #\(number) zugeordnet. Für den Worklog muss ManageEngine eingerichtet sein."
        }
        let search = await manageEngine.findTickets(number)
        if let ticket = search.tickets.first(where: { $0.number == number }) ?? search.tickets.first {
            linkTicket(ticket, to: id)
            return nil
        }
        setTicket(number: number, key: nil, for: id)
        return "Ticket #\(number) ohne Verbindung zugeordnet: ManageEngine fand es nicht (\(search.attempts.joined(separator: "; "))). Ohne Verbindung geht kein Worklog."
    }

    /// Sucht in ManageEngine nach Tickets, auch von anderen Technikern: Nummer oder Text im Betreff.
    func searchManageEngineTickets(_ query: String) async -> ManageEngineClient.TicketSearch {
        guard manageEngine.isReady else {
            return ManageEngineClient.TicketSearch(attempts: ["ManageEngine ist noch nicht eingerichtet (Einstellungen › ManageEngine)."])
        }
        return await manageEngine.findTickets(query)
    }

    /// Ordnet ein Ticket aus der Suche in ManageEngine zu (muss nicht das eigene sein).
    func linkTicket(_ ticket: ManageEngineTicket, to id: UUID) {
        setTicket(number: ticket.number, key: ticket.key, title: ticket.subject, for: id)
        if let task = self.task(id), task.customerID == nil, let customerID = customerID(forAccount: ticket.accountName) {
            setCustomer(customerID, for: id)
        }
    }

    /// Nur die Nummer zuordnen, ohne Verbindung zu ManageEngine (dann ohne Worklog).
    func linkTicketNumberOnly(_ number: String, to id: UUID) {
        setTicket(number: number, key: nil, for: id)
    }

    func unlinkTicket(from id: UUID) {
        setTicket(number: nil, key: nil, for: id)
    }

    private func setTicket(number: String?, key: String?, title: String? = nil, for id: UUID) {
        guard var task = self.task(id), task.source != .ticket else { return }
        guard task.ticketNumber != number || task.ticketKey != key || task.ticketTitle != title else { return }
        task.ticketNumber = number
        task.ticketKey = key
        task.ticketTitle = title
        persist(task)
    }

    /// Betreff des Tickets einer Aufgabe: beim Ticket selbst sein Titel, sonst der gemerkte oder der eines Tickets in Tagwerk.
    func ticketTitle(for task: TaskItem) -> String? {
        let effective = resolved(task)
        if task.source == .ticket { return (task.ticketTitle ?? "").isEmpty ? task.title : task.ticketTitle }
        if let title = effective.ticketTitle, !title.isEmpty { return title }
        guard let number = effective.linkedTicketNumber else { return nil }
        return ticketTasks.first { $0.linkedTicketNumber == number }?.title
    }

    func openFocus(_ id: UUID) {
        focusedTaskID = id
        selection = .focus
    }

    /// Andere Aufgabe in den Fokus. Läuft ein Timer (falsche Aufgabe gestartet), wandert die Zeit seit seinem Start mit;
    /// Timer und Pomodoro-Runde laufen einfach weiter.
    func switchTask(to taskID: UUID) {
        guard let target = task(taskID), !target.isDone else { return }
        if let moved = TimerLogic.reassignRunning(to: taskID, entries: entries) {
            do {
                try store.save(moved)
                replace(moved)
            } catch {
                report(error)
                return
            }
            if var current = pomodoro, current.phase == .work {
                current.taskID = taskID
                pomodoro = current
            }
            now = Date()
            AppLog.info("Timer", "Laufende Zeit auf eine andere Aufgabe umgehängt")
            showToast("Läuft jetzt für „\(target.title)“, samt der Zeit seit dem Start", symbol: "arrow.left.arrow.right")
        }
        focusedTaskID = taskID
    }

    func requestNewTask() {
        selection = .today
        newTaskRequest += 1
    }

    // MARK: Timer

    func startTimer(_ taskID: UUID) {
        endBreakForWork()
        apply(TimerLogic.start(taskID: taskID, entries: entries, at: Date()))
        focusedTaskID = taskID
        pomodoroTimerStarted(taskID)
    }

    /// Stoppen durch dich: beendet auch eine laufende Pomodoro-Runde.
    func stopTimer() {
        stopTracking()
        if pomodoro?.phase == .work { pomodoro = nil }
    }

    /// Zeit anhalten, ohne die Pomodoro-Runde zu beenden (z. B. beim Erledigen oder zur Pause).
    private func stopTracking() {
        apply(TimerLogic.stop(entries: entries, at: Date()))
    }

    // MARK: Pomodoro

    /// Laufender Pomodoro (Arbeit, Pause oder „bereit“); `nil` = keiner.
    var pomodoro: PomodoroState?
    /// Abgeschlossene Pomodoros heute
    private(set) var pomodorosToday = 0
    @ObservationIgnored private var pomodoroCountDay: LocalDate?

    var isPomodoroEnabled: Bool {
        _ = settingsVersion
        return UserDefaults.standard.bool(forKey: Preferences.pomodoroEnabledKey)
    }

    func setPomodoroEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Preferences.pomodoroEnabledKey)
        settingsVersion += 1
        if enabled {
            PomodoroNotifier.requestPermission()
            if let running = runningEntry, let taskID = running.taskID, pomodoro == nil {
                pomodoro = Pomodoro.startWork(previous: nil, taskID: taskID, now: Date())
            }
        } else {
            pomodoro = nil
        }
    }

    var pomodoroSettings: PomodoroSettings {
        _ = settingsVersion
        let defaults = UserDefaults.standard
        return PomodoroSettings(
            workMinutes: defaults.integer(forKey: Preferences.pomodoroWorkKey),
            shortBreakMinutes: defaults.integer(forKey: Preferences.pomodoroShortBreakKey),
            longBreakMinutes: defaults.integer(forKey: Preferences.pomodoroLongBreakKey),
            roundsUntilLongBreak: defaults.integer(forKey: Preferences.pomodoroRoundsKey)
        )
    }

    var pomodoroRemaining: TimeInterval {
        guard let pomodoro else { return 0 }
        return Pomodoro.remaining(pomodoro, settings: pomodoroSettings, now: now)
    }

    private func pomodoroTimerStarted(_ taskID: UUID) {
        guard isPomodoroEnabled else { return }
        if var current = pomodoro, current.phase == .work {
            current.taskID = taskID
            pomodoro = current
        } else if pomodoro != nil || selection == .focus {
            // Neu im Fokus gestartet oder nach (oder statt) der Pause weiter
            pomodoro = Pomodoro.startWork(previous: pomodoro, taskID: taskID, now: Date())
        }
    }

    /// Pause vorzeitig beenden; danach „Weiter“.
    func skipPomodoroBreak() {
        guard let current = pomodoro else { return }
        pomodoro = Pomodoro.skipBreak(current, now: Date())
    }

    /// Nach der Pause mit derselben Aufgabe weiter (oder der Fokus-Aufgabe).
    func continuePomodoro() {
        let taskID = pomodoro?.taskID.flatMap { task($0)?.isDone == false ? $0 : nil } ?? focusTask?.id
        guard let taskID else { return }
        if pomodoro?.phase.isBreak == true { skipPomodoroBreak() }
        startTimer(taskID)
    }

    func endPomodoro() {
        pomodoro = nil
    }

    /// Jede Sekunde: Ist die Phase um, geht es weiter (Arbeit → Pause → bereit) mit Ton und Mitteilung.
    private func checkPomodoro() {
        guard let current = pomodoro,
              let next = Pomodoro.advance(current, settings: pomodoroSettings, now: Date()) else { return }
        let settings = pomodoroSettings
        switch next.phase {
        case .shortBreak, .longBreak:
            if runningEntry != nil { stopTracking() }
            music.pauseForBreak()
            if pomodoroCountDay != today { pomodorosToday = 0; pomodoroCountDay = today }
            pomodorosToday += 1
            pomodoro = next
            AppLog.info("Pomodoro", "Runde \(next.completedInSet) geschafft, \(next.phase == .longBreak ? "lange" : "kurze") Pause")
            let minutes = next.phase == .longBreak ? settings.longBreakMinutes : settings.shortBreakMinutes
            PomodoroNotifier.signal(
                title: next.phase == .longBreak ? "Lange Pause" : "Pause",
                body: "\(next.completedInSet). Pomodoro geschafft. \(minutes) Minuten Pause, die Zeit läuft nicht mit.",
                event: next.phase == .longBreak ? .longBreak : .shortBreak
            )
        case .ready:
            pomodoro = next
            let title = task(next.taskID)?.title
            PomodoroNotifier.signal(
                title: "Pause vorbei",
                body: title.map { "Weiter mit „\($0)“." } ?? "Weiter geht's.",
                event: .resume
            )
            if UserDefaults.standard.bool(forKey: Preferences.pomodoroAutoContinueKey) {
                continuePomodoro()
            }
        case .work:
            break
        }
    }

    /// Vergessen zu starten: Timer läuft rückwirkend seit `since` (frühestens ab dem Ende des letzten Eintrags).
    func startTimer(_ taskID: UUID, since: Date) {
        endBreakForWork()
        apply(TimerLogic.start(taskID: taskID, entries: entries, since: since, now: Date()))
        focusedTaskID = taskID
    }

    /// Ende des letzten abgeschlossenen Eintrags heute, z. B. für „seit dem letzten Eintrag“.
    var lastEntryEndToday: Date? {
        let start = today.startDate()
        return entries.compactMap { entry -> Date? in
            guard let end = entry.end, end >= start, end <= Date() else { return nil }
            return end
        }.max()
    }

    /// Öffnet „Zeit nachtragen“, für eine Aufgabe oder frei. Vorschlag: vom Ende des letzten Eintrags
    /// (wenn es heute und nicht länger als vier Stunden her ist) bis jetzt, sonst die letzte halbe Stunde.
    func beginTimeEntry(for taskID: UUID? = nil) {
        let end = Date()
        var start = end.addingTimeInterval(-30 * 60)
        if let last = lastEntryEndToday, end.timeIntervalSince(last) <= 4 * 3600, end.timeIntervalSince(last) >= 5 * 60 {
            start = last
        }
        let minutes = max(5, Int(end.timeIntervalSince(start) / 60))
        timeEntryDraft = TimeEntryDraft(start: start, minutes: minutes, taskID: taskID)
    }

    func toggleTimer(for taskID: UUID) {
        if isRunning(taskID) {
            stopTimer()
        } else {
            startTimer(taskID)
        }
    }

    /// Für Tastenkürzel und Menüleiste: startet oder stoppt die Fokus-Aufgabe.
    func toggleTimerForFocus() {
        if runningBreak != nil {
            endBreak(resume: true)
        } else if runningEntry != nil {
            stopTimer()
        } else if let task = focusTask {
            startTimer(task.id)
        }
    }

    func completeFocused() {
        if let task = focusTask { complete(task.id) }
    }

    private func apply(_ change: TimerLogic.Change) {
        defer {
            if change.started != nil {
                music.timerStarted(inFocus: selection == .focus)
            } else if !change.stopped.isEmpty || !change.discarded.isEmpty {
                music.timerStopped()
            }
        }
        do {
            if let restarted = change.restarted {
                try store.save(restarted)
                replace(restarted)
            }
            for entry in change.discarded {
                try store.deleteEntry(id: entry.id)
                entries.removeAll { $0.id == entry.id }
            }
            for entry in change.stopped {
                try store.save(entry)
                replace(entry)
            }
            if let started = change.started {
                try store.save(started)
                entries.append(started)
            }
        } catch {
            report(error)
        }
        now = Date()
    }

    // MARK: Kalender und Zeitblöcke

    var workday: Workday {
        _ = settingsVersion
        let defaults = UserDefaults.standard
        return Workday(
            startMinutes: defaults.integer(forKey: Preferences.workdayStartKey),
            endMinutes: defaults.integer(forKey: Preferences.workdayEndKey)
        )
    }

    var workdayInterval: DateInterval { workday.interval(on: today) }

    /// Freie Minuten der Arbeitszeit neben den Terminen.
    var freeMinutesToday: Int {
        FreeTime.freeMinutes(window: workdayInterval, events: events)
    }

    var timedEvents: [CalendarEvent] { events.filter { !$0.isAllDay } }

    var allDayEvents: [CalendarEvent] { events.filter(\.isAllDay) }

    /// Heutige Aufgaben mit Zeitblock.
    var scheduledToday: [TaskItem] {
        todayTasks.filter { $0.scheduledStart != nil }
    }

    /// Zeiteinträge, die heute stattfinden.
    var entriesToday: [TimeEntry] {
        let interval = today.interval()
        return entries.filter { TimeMath.overlap(of: $0, with: interval, now: now) > 0 }
    }

    var calendarModes: [String: CalendarDisplayMode] {
        _ = settingsVersion
        let raw = UserDefaults.standard.dictionary(forKey: Preferences.calendarModesKey) as? [String: String] ?? [:]
        return raw.compactMapValues { CalendarDisplayMode(rawValue: $0) }
    }

    var calendarList: [CalendarInfo] {
        _ = calendarAccess
        return calendarProvider.calendars(modes: calendarModes)
    }

    var writesBlocksToCalendar: Bool {
        _ = settingsVersion
        return UserDefaults.standard.bool(forKey: Preferences.writeBlocksKey)
    }

    /// Kalender für die Zeitblöcke (z. B. Outlook); `nil` = eigener Kalender „Tagwerk“.
    var blockCalendarID: String? {
        _ = settingsVersion
        let value = UserDefaults.standard.string(forKey: Preferences.blockCalendarIDKey) ?? ""
        return value.isEmpty ? nil : value
    }

    /// Kalender, in die Zeitblöcke geschrieben werden können.
    var blockTargets: [CalendarInfo] {
        _ = calendarAccess
        return calendarProvider.blockTargets()
    }

    /// Anderen Kalender für die Zeitblöcke wählen: Blöcke ab heute ziehen gleich mit um.
    func setBlockCalendar(_ id: String?) {
        UserDefaults.standard.set(id ?? "", forKey: Preferences.blockCalendarIDKey)
        settingsVersion += 1
        resyncBlocks()
    }

    /// Schreibt alle Zeitblöcke ab heute neu (z. B. nach dem Wechsel des Kalenders oder dem Einschalten).
    func resyncBlocks() {
        guard writesBlocksToCalendar else { return }
        let start = today.startDate()
        var moved = 0
        for var task in tasks where !task.isDone && (task.scheduledStart.map { $0 >= start } ?? false) {
            let before = task.calendarEventID
            syncBlock(&task)
            if task.calendarEventID != before {
                persist(task)
            }
            moved += 1
        }
        AppLog.info("Kalender", "Zeitblöcke neu geschrieben: \(moved)")
    }

    var isPlanningDue: Bool {
        DailyPlanning.isDue(lastPlanned: lastPlannedDay, today: today)
    }

    func isLogged(_ event: CalendarEvent) -> Bool {
        tasks.contains { $0.source == .calendar && $0.externalID == event.id }
    }

    /// Aufgabe, die aus diesem Termin erfasst wurde.
    func loggedTask(for event: CalendarEvent) -> TaskItem? {
        tasks.first { $0.source == .calendar && $0.externalID == event.id }
    }

    /// Termin, der als Aufgabe mit erfasster Zeit in Tagwerk steht: dort zeigt Tagwerk nur noch die Aufgabe.
    /// Im Kalender selbst bleibt der Termin.
    func isShownAsTask(_ event: CalendarEvent) -> Bool {
        guard let task = loggedTask(for: event) else { return false }
        return entries.contains { $0.taskID == task.id }
    }

    func requestCalendarAccess() async {
        calendarAccess = await calendarProvider.requestAccess()
        AppLog.info("Kalender", "Zugriff angefragt: \(calendarAccess)")
        refreshEvents()
    }

    func refreshEvents() {
        calendarAccess = calendarProvider.access
        eventCache = [:]
        events = calendarProvider.events(on: today, modes: calendarModes)
    }

    @ObservationIgnored private var eventCache: [LocalDate: [CalendarEvent]] = [:]

    /// Termine eines beliebigen Tages (für Woche und Wochenkalender), zwischengespeichert.
    func calendarEvents(on day: LocalDate) -> [CalendarEvent] {
        if day == today { return events }
        if let cached = eventCache[day] { return cached }
        let loaded = calendarProvider.events(on: day, modes: calendarModes)
        eventCache[day] = loaded
        return loaded
    }

    func setCalendarMode(_ mode: CalendarDisplayMode, for calendarID: String) {
        var raw = UserDefaults.standard.dictionary(forKey: Preferences.calendarModesKey) as? [String: String] ?? [:]
        raw[calendarID] = mode.rawValue
        UserDefaults.standard.set(raw, forKey: Preferences.calendarModesKey)
        settingsChanged()
    }

    func settingsChanged() {
        settingsVersion += 1
        refreshEvents()
    }

    /// Legt den Zeitblock einer Aufgabe auf eine Uhrzeit (`nil` = Block entfernen).
    func schedule(_ id: UUID, at start: Date?) {
        guard var task = self.task(id) else { return }
        if let start {
            let snapped = FreeTime.snapNearest(start, stepMinutes: 15)
            let day = LocalDate(snapped)
            if task.plannedDate != day {
                task.plannedDate = day
                if task.isSubtask {
                    task.daySortIndex = DayPlan.nextDayIndex(in: dayTasks(day))
                } else {
                    task.sortIndex = DayPlan.nextSortIndex(in: tasks.filter { $0.plannedDate == day })
                }
            }
            task.scheduledStart = snapped
        } else {
            task.scheduledStart = nil
        }
        syncBlock(&task)
        persist(task)
    }

    func moveBlock(_ id: UUID, byMinutes minutes: Double) {
        guard let start = task(id)?.scheduledStart else { return }
        schedule(id, at: start.addingTimeInterval(minutes * 60))
    }

    /// Legt die Aufgabe in die nächste freie Lücke ab jetzt.
    func scheduleInNextGap(_ id: UUID) {
        guard let task = self.task(id) else { return }
        let placed = FreeTime.autoSchedule(
            [(id: task.id, minutes: task.blockMinutes)],
            gaps: freeGaps(excluding: id),
            notBefore: max(Date(), workdayInterval.start)
        )
        if let start = placed[id] {
            schedule(id, at: start)
        } else {
            lastError = "Heute ist keine Lücke mehr frei, in die „\(task.title)“ passt."
        }
    }

    /// Legt alle offenen Aufgaben ohne Zeitblock der Reihe nach in freie Lücken.
    @discardableResult
    func autoScheduleToday() -> Int {
        let open = todayTasks.filter { !$0.isDone && $0.scheduledStart == nil }
        let placed = FreeTime.autoSchedule(
            open.map { (id: $0.id, minutes: $0.blockMinutes) },
            gaps: freeGaps(excluding: nil),
            notBefore: max(Date(), workdayInterval.start)
        )
        for task in open {
            if let start = placed[task.id] {
                schedule(task.id, at: start)
            }
        }
        return open.count - placed.count
    }

    /// Macht aus einem Termin einen erledigten Zeiteintrag (z. B. den Jour fixe).
    /// Was beim letzten Erfassen eines Termins mit diesem Titel gewählt wurde.
    struct EventAssignment: Codable, Equatable {
        var customerID: UUID?
    }

    private static let eventAssignmentsKey = "eventAssignments"

    func eventAssignment(for event: CalendarEvent) -> EventAssignment? {
        guard let data = UserDefaults.standard.data(forKey: Self.eventAssignmentsKey),
              let all = try? JSONDecoder().decode([String: EventAssignment].self, from: data) else { return nil }
        return all[Self.assignmentKey(event)]
    }

    private func remember(_ assignment: EventAssignment, for event: CalendarEvent) {
        var all = (UserDefaults.standard.data(forKey: Self.eventAssignmentsKey))
            .flatMap { try? JSONDecoder().decode([String: EventAssignment].self, from: $0) } ?? [:]
        all[Self.assignmentKey(event)] = assignment
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.eventAssignmentsKey)
        }
    }

    private static func assignmentKey(_ event: CalendarEvent) -> String {
        event.displayTitle.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Termin als erfasste Zeit übernehmen, mit Kunde.
    /// Ohne Angaben gilt, was beim letzten Termin mit gleichem Titel gewählt wurde.
    func logEvent(_ event: CalendarEvent, title: String? = nil, assignment: EventAssignment? = nil) {
        guard !isLogged(event) else { return }
        let chosen = assignment ?? eventAssignment(for: event)
        if let assignment { remember(assignment, for: event) }
        let name = title?.trimmingCharacters(in: .whitespaces)
        let task = TaskItem(
            title: (name?.isEmpty == false ? name : nil) ?? (event.showsTitle ? event.displayTitle : "Termin"),
            customerID: chosen?.customerID,
            source: .calendar,
            externalID: event.id,
            plannedDate: LocalDate(event.start),
            estimateMinutes: event.minutes,
            status: .done,
            completedAt: event.end,
            sortIndex: DayPlan.nextSortIndex(in: todayTasks)
        )
        persist(task)
        let entry = TimeEntry(taskID: task.id, start: event.start, end: event.end)
        do {
            try store.save(entry)
            entries.append(entry)
        } catch {
            report(error)
        }
    }

    // MARK: Meetings und Kundenordner

    func meeting(_ id: UUID?) -> Meeting? {
        id.flatMap { id in meetings.first { $0.id == id } }
    }

    func meeting(for context: MeetingContext) -> Meeting? {
        if let id = context.meetingID, let found = meeting(id) { return found }
        guard let eventID = context.eventID else { return nil }
        return meetings.first { $0.eventID == eventID }
    }

    func tasks(fromMeeting id: UUID) -> [TaskItem] {
        tasks.filter { $0.meetingID == id }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Meeting-Fenster für einen Termin.
    func openMeeting(_ event: CalendarEvent) {
        meetingContext = MeetingContext(event: event)
    }

    /// Meeting-Fenster für eine Aufgabe: das Meeting, aus dem sie stammt, oder den Termin, aus dem sie erfasst wurde.
    func openMeeting(for task: TaskItem) {
        if let meeting = meeting(task.meetingID) {
            meetingContext = MeetingContext(meeting: meeting)
            return
        }
        guard task.source == .calendar, let eventID = task.externalID else { return }
        if let event = events.first(where: { $0.id == eventID }) {
            meetingContext = MeetingContext(event: event)
        } else if let meeting = meetings.first(where: { $0.eventID == eventID }) {
            meetingContext = MeetingContext(meeting: meeting)
        } else {
            let own = entries.filter { $0.taskID == task.id }.sorted { $0.start < $1.start }
            let start = own.first?.start ?? task.completedAt ?? Date()
            let end = own.last?.end ?? start.addingTimeInterval(TimeInterval((task.estimateMinutes ?? 30) * 60))
            meetingContext = MeetingContext(meetingID: nil, eventID: eventID, title: task.title, start: start, end: end, event: nil)
        }
    }

    /// Kunde, der für ein Meeting naheliegt: der gespeicherte, der der erfassten Aufgabe, sonst der zuletzt für diesen Titel gewählte.
    func suggestedCustomer(for context: MeetingContext) -> UUID? {
        if let meeting = meeting(for: context) { return meeting.customerID }
        if let eventID = context.eventID,
           let logged = tasks.first(where: { $0.source == .calendar && $0.externalID == eventID }),
           logged.customerID != nil {
            return logged.customerID
        }
        return storedAssignments()[Self.assignmentKey(title: context.title)]?.customerID
    }

    /// Legt das Meeting an oder ändert seinen Kunden; merkt sich den Kunden für diesen Termintitel.
    @discardableResult
    func saveMeeting(_ context: MeetingContext, customerID: UUID?) -> Meeting {
        var meeting = meeting(for: context)
            ?? Meeting(eventID: context.eventID, title: context.title, start: context.start, end: context.end)
        meeting.customerID = customerID
        persistMeeting(meeting)
        var all = storedAssignments()
        all[Self.assignmentKey(title: context.title)] = EventAssignment(customerID: customerID)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.eventAssignmentsKey)
        }
        return meeting
    }

    /// Legt das Transkript als Datei im Ordner des Kunden ab (unter „Meetings“; der Ordner entsteht bei Bedarf)
    /// und merkt sie am Meeting. Ohne Kunde landet es im Tagwerk-Ordner.
    @discardableResult
    func storeTranscript(_ text: String, for context: MeetingContext, customerID: UUID?) throws -> URL {
        let cleaned = MeetingFiles.isVTT(text) ? MeetingFiles.plainTranscript(fromVTT: text) : text
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeetingError.emptyTranscript
        }
        let customer = self.customer(customerID)
        let folder: URL
        if let customer {
            folder = try ensureFolder(for: customer.id).appendingPathComponent(MeetingFiles.meetingsFolder, isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tagwerk", isDirectory: true)
                .appendingPathComponent(MeetingFiles.meetingsFolder, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var meeting = saveMeeting(context, customerID: customerID)
        let url = folder.appendingPathComponent(MeetingFiles.fileName(title: context.title, start: context.start))
        let document = MeetingFiles.document(
            title: context.title, start: context.start, end: context.end, customerName: customer?.name, transcript: cleaned
        )
        try document.write(to: url, atomically: true, encoding: .utf8)
        meeting.transcriptPath = url.path
        persistMeeting(meeting)
        AppLog.info("Meeting", "Transkript abgelegt (\(cleaned.count) Zeichen)")
        return url
    }

    /// Meeting ohne (weitere) Aufgaben abschließen.
    func markMeetingProcessed(_ context: MeetingContext) {
        guard var meeting = meeting(for: context), meeting.processedAt == nil else { return }
        meeting.processedAt = Date()
        persistMeeting(meeting)
    }

    /// Basisordner für neue Kundenordner (Einstellungen › Claude), Standard „Kunden“ im Benutzerordner.
    var customerFoldersBase: URL {
        _ = settingsVersion
        let raw = UserDefaults.standard.string(forKey: Preferences.customerFoldersBaseKey) ?? ""
        if raw.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Kunden", isDirectory: true)
        }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    func setCustomerFoldersBase(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Preferences.customerFoldersBaseKey)
        settingsVersion += 1
    }

    /// Ordner des Kunden; fehlt er, wird er im Basisordner angelegt (mit „Meetings“ und einer ersten CLAUDE.md).
    @discardableResult
    func ensureFolder(for customerID: UUID) throws -> URL {
        guard var customer = customer(customerID) else { throw MeetingError.noCustomer }
        let url: URL
        if let path = customer.folderPath, !path.isEmpty {
            url = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            url = customerFoldersBase.appendingPathComponent(MeetingFiles.folderName(for: customer.name), isDirectory: true)
        }
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(MeetingFiles.meetingsFolder, isDirectory: true),
            withIntermediateDirectories: true
        )
        try writeInstructionsIfMissing(customerName: customer.name, in: url)
        if customer.folderPath != url.path {
            customer.folderPath = url.path
            save(customer)
            AppLog.info("Kundenordner", "Angelegt bzw. verknüpft")
        }
        return url
    }

    /// Vorhandenen Ordner für den Kunden nehmen (oder die Verknüpfung lösen).
    func setFolder(_ url: URL?, for customerID: UUID) {
        guard var customer = customer(customerID) else { return }
        customer.folderPath = url?.path
        save(customer)
    }

    func hasInstructions(customerID: UUID) -> Bool {
        guard let path = customer(customerID)?.folderPath else { return false }
        return FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(MeetingFiles.instructionsFile))
    }

    /// CLAUDE.md im Kundenordner anlegen, wenn noch keine da ist (eine vorhandene bleibt unangetastet).
    func writeInstructionsIfMissing(customerName: String, in folder: URL) throws {
        let file = folder.appendingPathComponent(MeetingFiles.instructionsFile)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try MeetingFiles.claudeInstructions(customerName: customerName).write(to: file, atomically: true, encoding: .utf8)
    }

    /// Startet Claude Code im Ordner des Kunden (legt ihn bei Bedarf an), auf Wunsch gleich mit der Bitte zum Meeting.
    func openClaudeCode(customerID: UUID?, meeting: Meeting? = nil) {
        do {
            let folder = try customerID.map { try ensureFolder(for: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser
            let prompt = meeting.map { ClaudeCodeLauncher.prompt(for: $0, calendar: .current) }
            try ClaudeCodeLauncher.open(in: folder, prompt: prompt)
            AppLog.info("Claude Code", meeting == nil ? "Im Kundenordner geöffnet" : "Für ein Meeting geöffnet")
        } catch {
            report(error)
        }
    }

    private func persistMeeting(_ meeting: Meeting) {
        do {
            try store.save(meeting)
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index] = meeting
            } else {
                meetings.append(meeting)
            }
        } catch {
            report(error)
        }
    }

    private func storedAssignments() -> [String: EventAssignment] {
        UserDefaults.standard.data(forKey: Self.eventAssignmentsKey)
            .flatMap { try? JSONDecoder().decode([String: EventAssignment].self, from: $0) } ?? [:]
    }

    private static func assignmentKey(title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: Pausen

    var runningBreak: WorkBreak? { Breaks.running(in: breaks) }

    /// Pausen, die einen Tag berühren.
    func breaks(on day: LocalDate) -> [WorkBreak] {
        Breaks.on(day, breaks, now: now)
    }

    func breakTotal(on day: LocalDate) -> TimeInterval {
        Breaks.total(on: day, breaks: breaks, now: now)
    }

    /// Fehlende Pause nach dem Arbeitszeitgesetz an einem Tag (0 = passt).
    func missingBreakMinutes(on day: LocalDate) -> Int {
        Breaks.missingMinutes(worked: tracked(on: day), countedMinutes: Breaks.countedMinutes(on: day, breaks: breaks, now: now))
    }

    /// Mittagspause jetzt: hält den Timer an und merkt sich die Aufgabe; „Weiter“ startet sie danach wieder.
    /// (Pomodoro-Pausen laufen getrennt davon und werden nicht eingetragen.)
    func startBreak() {
        guard runningBreak == nil else { return }
        pomodoro = nil
        apply(Breaks.start(entries: entries, breaks: breaks, at: Date()))
        AppLog.info("Pause", "Mittagspause begonnen")
    }

    /// Pause beenden; mit `resume` geht es mit der Aufgabe von vorher weiter.
    func endBreak(resume: Bool) {
        guard let current = runningBreak else { return }
        apply(Breaks.end(breaks: breaks, at: Date()))
        AppLog.info("Pause", "Mittagspause beendet nach \(Int(current.duration() / 60)) Min")
        if resume, let id = current.resumeTaskID, let task = self.task(id), !task.isDone {
            startTimer(id)
        }
    }

    /// Wer eine Aufgabe startet, ist aus der Pause zurück.
    private func endBreakForWork() {
        if runningBreak != nil { apply(Breaks.end(breaks: breaks, at: Date())) }
    }

    /// Aufgabe, mit der es nach der laufenden Pause weitergeht.
    var taskAfterBreak: TaskItem? {
        guard let id = runningBreak?.resumeTaskID, let task = self.task(id), !task.isDone else { return nil }
        return task
    }

    /// Pause nachtragen oder ändern. Erfasste Arbeit in diesem Zeitraum wird herausgeschnitten.
    @discardableResult
    func addBreak(start: Date, end: Date, note: String = "", replacing id: UUID? = nil) -> Bool {
        let change = Breaks.add(start: start, end: end, note: note, replacing: id, entries: entries, breaks: breaks, now: Date())
        guard !change.isEmpty else { return false }
        apply(change)
        let cut = change.savedEntries.count + change.deletedEntries.count
        AppLog.info("Pause", "Pause eingetragen (\(Int(end.timeIntervalSince(start) / 60)) Min\(cut > 0 ? ", \(cut) Eintrag/Einträge angepasst" : ""))")
        return true
    }

    func deleteBreak(_ id: UUID) {
        do {
            try store.deleteBreak(id: id)
            breaks.removeAll { $0.id == id }
        } catch {
            report(error)
        }
    }

    /// Erfasste Arbeit in einem Zeitraum (zeigt, was eine nachgetragene Pause herausschneidet).
    func workInside(start: Date, end: Date) -> TimeInterval {
        let now = Date()
        guard end > start else { return 0 }
        let interval = DateInterval(start: start, end: max(start, min(end, now)))
        return entries.reduce(0) { $0 + TimeMath.overlap(of: $1, with: interval, now: now) }
    }

    /// Öffnet „Mittagspause nachtragen“. Vorschlag: 12:00–12:30, wenn das vorbei ist und heute noch keine eingetragen ist,
    /// sonst die letzte halbe Stunde; mit `start` (Kalender, Tagesabschluss) ab dort.
    func beginBreakEntry(start: Date? = nil, minutes: Int = 30) {
        let now = Date()
        let noon = FreeTime.date(on: today, minutes: 12 * 60)
        let begin: Date
        if let start {
            begin = start
        } else if breaks(on: today).isEmpty, noon.addingTimeInterval(TimeInterval(minutes * 60)) <= now {
            begin = noon
        } else {
            begin = FreeTime.snapNearest(now, stepMinutes: 5).addingTimeInterval(TimeInterval(-minutes * 60))
        }
        breakDraft = BreakDraft(start: begin, end: begin.addingTimeInterval(TimeInterval(minutes * 60)), note: "Mittag")
    }

    func editBreak(_ item: WorkBreak) {
        breakDraft = BreakDraft(start: item.start, end: item.end ?? Date(), note: item.note, breakID: item.id, isRunning: item.isRunning)
    }

    private func apply(_ change: BreakChange) {
        let wasRunning = runningEntry != nil
        do {
            for entry in change.deletedEntries {
                try store.deleteEntry(id: entry.id)
                entries.removeAll { $0.id == entry.id }
            }
            for entry in change.savedEntries {
                try store.save(entry)
                replace(entry)
            }
            for item in change.deletedBreaks {
                try store.deleteBreak(id: item.id)
                breaks.removeAll { $0.id == item.id }
            }
            for item in change.savedBreaks {
                try store.save(item)
                if let index = breaks.firstIndex(where: { $0.id == item.id }) {
                    breaks[index] = item
                } else {
                    breaks.append(item)
                }
            }
        } catch {
            report(error)
        }
        if wasRunning, runningEntry == nil { music.timerStopped() }
        now = Date()
    }

    // MARK: Standardaufgaben

    /// Aufgaben wie „Organisatorisches“: immer da, nie erledigt, mit einem Klick gestartet.
    var standingTasks: [TaskItem] { DayPlan.standing(tasks) }

    @discardableResult
    func addStandingTask(title rawTitle: String) -> TaskItem? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              !standingTasks.contains(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else { return nil }
        let task = TaskItem(title: title, sortIndex: DayPlan.nextSortIndex(in: standingTasks), isStanding: true)
        persist(task)
        return task
    }

    /// Entfernt eine Standardaufgabe. Hat sie schon Zeiten, bleibt sie als erledigte Aufgabe erhalten (die Zeiten auch).
    func removeStandingTask(_ id: UUID) {
        guard var task = self.task(id), task.isStanding else { return }
        if isRunning(id) { stopTimer() }
        let ends = entries.filter { $0.taskID == id }.compactMap(\.end)
        if ends.isEmpty {
            delete(id)
        } else {
            task.isStanding = false
            task.status = .done
            task.completedAt = ends.max()
            persist(task)
        }
    }

    /// Heute erfasste Zeit einer Aufgabe (für die Standardaufgaben auf Start).
    func trackedToday(taskID: UUID) -> TimeInterval {
        TimeMath.tracked(taskID: taskID, on: today, entries: entries, now: now)
    }

    /// Beim ersten Start mit dieser Fassung ein paar Vorschläge anlegen.
    private func seedStandingTasksIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Preferences.standingSeededKey) else { return }
        defaults.set(true, forKey: Preferences.standingSeededKey)
        guard standingTasks.isEmpty else { return }
        for title in DayPlan.defaultStandingTitles {
            addStandingTask(title: title)
        }
    }

    // MARK: Befehlszeile

    /// Vorschläge für die Eingabe in der Befehlszeile.
    func commandSuggestions(for query: String) -> [CommandSuggestion] {
        QuickCommand.suggestions(for: query, in: CommandContext(
            tasks: tasks,
            customers: activeCustomers,
            today: today,
            runningTaskID: runningEntry?.taskID,
            lunchRunning: runningBreak != nil,
            now: Date(),
            absentToday: absence(on: today) != nil,
            trackedTodaySeconds: trackedToday(now: Date())
        ))
    }

    func openCommandBar(with query: String = "") {
        commandQuery = query
        showsCommandBar = true
    }

    /// Führt einen Befehl aus und sagt kurz, was passiert ist.
    func perform(_ action: CommandAction) {
        showsCommandBar = false
        switch action {
        case .start(let id):
            startTimer(id)
            showToast("Läuft: \(task(id)?.title ?? "Aufgabe")", symbol: "play.fill")
        case .startNew(let title, let customerID):
            guard let created = addTask(title: title, customerID: customerID, plannedDate: today) else { return }
            startTimer(created.id)
            showToast("Neu und läuft: \(created.title)", symbol: "play.fill")
        case .startSince(let taskID, let title, let customerID, let since):
            guard let id = taskID ?? addTask(title: title, customerID: customerID, plannedDate: today)?.id else { return }
            startTimer(id, since: since)
            let start = runningEntry?.start ?? since
            showToast("„\(task(id)?.title ?? title)“ läuft seit \(start.formatted(date: .omitted, time: .shortened))", symbol: "play.circle")
        case .log(let taskID, let title, let customerID, let minutes):
            logUntilNow(taskID: taskID, title: title, customerID: customerID, minutes: minutes)
        case .add(let title, let customerID, let day, let estimate):
            guard let created = addTask(title: title, customerID: customerID, plannedDate: day) else { return }
            if let estimate { setEstimate(estimate, for: created.id) }
            let when = QuickCommand.dayLabel(day, today: today, calendar: .current)
            showToast(day == nil ? "Im Eingang: \(created.title)" : "Für \(when): \(created.title)", symbol: day == nil ? "tray.and.arrow.down" : "plus.circle")
        case .stop:
            let title = runningTask?.title
            stopTimer()
            showToast(title.map { "Gestoppt: \($0)" } ?? "Timer gestoppt", symbol: "stop.fill")
        case .complete(let id):
            let title = task(id)?.title ?? "Aufgabe"
            complete(id)
            showToast("Erledigt: \(title)", symbol: "checkmark.circle.fill")
        case .focus(let id):
            openFocus(id)
        case .switchRunning(let id):
            switchTask(to: id)
        case .startLunch:
            startBreak()
            showToast("Mittagspause. Guten Appetit!", symbol: "fork.knife")
        case .endLunch:
            endBreak(resume: true)
            showToast(runningTask.map { "Weiter mit „\($0.title)“" } ?? "Mittagspause beendet", symbol: "play.fill")
        case .absent(let kind, let from, let through, let halfDay):
            let message = markAbsent(kind, from: from, through: through, halfDay: halfDay)
            showToast(message, symbol: kind.symbol)
        case .absenceForm(let kind):
            beginAbsence(kind)
        case .open(let destination):
            switch destination {
            case .start: selection = .today
            case .plan: selection = .week
            case .calendar: selection = .calendar
            case .focus: selection = .focus
            case .customers: selection = .customers
            case .goals: selection = .goals
            case .review: selection = .review
            case .planning: selection = .planning
            case .close: selection = .close
            }
        }
    }

    /// Zeit, die gerade zu Ende gegangen ist, nachtragen. Überlagerte Zeit anderer Einträge wird dort herausgeschnitten
    /// (sonst zählte sie doppelt); lief ein Timer, läuft er ab jetzt weiter.
    private func logUntilNow(taskID: UUID?, title: String, customerID: UUID?, minutes: Int) {
        let end = Date()
        let start = end.addingTimeInterval(TimeInterval(-minutes * 60))
        let resumeID = runningEntry?.taskID
        var target = taskID.flatMap { task($0) }
        if target == nil {
            target = addTask(title: title, customerID: customerID, plannedDate: today)
        }
        guard let target else { return }

        let carved = TimeCarving.carve(entries, from: start, to: end, now: end)
        do {
            for entry in carved.deleted {
                try store.deleteEntry(id: entry.id)
                entries.removeAll { $0.id == entry.id }
            }
            for entry in carved.saved {
                try store.save(entry)
                replace(entry)
            }
        } catch {
            report(error)
        }
        addEntry(taskID: target.id, start: start, end: end)
        if taskID == nil, var done = task(target.id) {
            done.status = .done
            done.completedAt = end
            persist(done)
        }
        // Lief vorher ein Timer (für eine andere Aufgabe), läuft er ab jetzt weiter
        if let resumeID, resumeID != target.id, runningEntry == nil {
            apply(TimerLogic.start(taskID: resumeID, entries: entries, at: Date()))
        }
        AppLog.info("Befehl", "\(minutes) Min nachgetragen\(carved.saved.count + carved.deleted.count > 0 ? ", überlagerte Zeit herausgeschnitten" : "")")
        showToast("\(TimeMath.format(minutes: minutes)) h auf „\(target.title)“ nachgetragen", symbol: "clock.badge.checkmark")
    }

    func showToast(_ text: String, symbol: String) {
        let next = Toast(text: text, symbol: symbol)
        toast = next
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            if self?.toast?.id == next.id { self?.toast = nil }
        }
    }

    func dismissToast() {
        toast = nil
    }

    // MARK: Woche und Kalender

    func dayTasks(_ day: LocalDate) -> [TaskItem] { DayPlan.tasks(for: day, in: tasks) }

    /// Zeiteinträge, die einen Tag berühren.
    func dayEntries(_ day: LocalDate) -> [TimeEntry] {
        let interval = day.interval()
        return entries.filter { TimeMath.overlap(of: $0, with: interval, now: now) > 0 }
    }

    /// Aufgaben mit Zeitblock an diesem Tag.
    func scheduledTasks(on day: LocalDate) -> [TaskItem] {
        tasks.filter { task in task.scheduledStart.map { LocalDate($0) == day } ?? false }
    }

    /// Freie Zeit eines Arbeitstags in Minuten (Arbeitszeit minus Termine).
    func freeMinutes(on day: LocalDate) -> Int {
        FreeTime.freeMinutes(window: workday.interval(on: day), events: calendarEvents(on: day))
    }

    func trackedInWeek(starting monday: LocalDate) -> TimeInterval {
        (0..<7).reduce(0) { $0 + tracked(on: monday.adding(days: $1)) }
    }

    /// Wochenziel dieser Woche: Tagesziel Fokuszeit mal Arbeitstage, ohne Krank- und Urlaubstage.
    var weeklyGoalMinutes: Int {
        weeklyGoalMinutes(forWeekStarting: currentWeekStart)
    }

    var dailyGoalMinutes: Int {
        _ = settingsVersion
        let daily = UserDefaults.standard.integer(forKey: Preferences.focusGoalMinutesKey)
        return daily > 0 ? daily : Preferences.defaultFocusGoalMinutes
    }

    func weeklyGoalMinutes(forWeekStarting monday: LocalDate) -> Int {
        Absences.weeklyGoalMinutes(dailyMinutes: dailyGoalMinutes, weekStart: monday, absences: absences)
    }

    // MARK: Abwesenheit

    func absence(on day: LocalDate) -> Absence? {
        Absences.absence(on: day, in: absences)
    }

    func absences(inWeekStarting monday: LocalDate) -> [Absence] {
        Absences.inWeek(starting: monday, absences)
    }

    /// Krank oder Urlaub eintragen (nur Arbeitstage). Vorhandene Einträge derselben Tage werden ersetzt;
    /// offene Aufgaben ganzer Abwesenheitstage rücken auf Wunsch auf den nächsten Arbeitstag.
    @discardableResult
    func markAbsent(_ kind: AbsenceKind, from start: LocalDate, through end: LocalDate, halfDay: Bool = false, note: String = "", moveTasks: Bool = true) -> String {
        let new = Absences.make(kind: kind, from: start, through: end, halfDay: halfDay, note: note, now: Date())
        guard !new.isEmpty else { return "Im Zeitraum liegt kein Arbeitstag." }
        do {
            for old in absences where new.contains(where: { $0.day == old.day }) {
                try store.deleteAbsence(id: old.id)
            }
            absences.removeAll { old in new.contains { $0.day == old.day } }
            for absence in new {
                try store.save(absence)
                absences.append(absence)
            }
        } catch {
            report(error)
            return "Konnte nicht eingetragen werden."
        }
        var moved = 0
        if moveTasks {
            for absence in new where !absence.halfDay {
                let target = Absences.nextWorkingDay(after: absence.day, absences: absences)
                for task in tasks where task.plannedDate == absence.day && !task.isDone && task.parentID == nil {
                    plan(task.id, for: target)
                    moved += 1
                }
            }
        }
        AppLog.info("Abwesenheit", "\(kind.label): \(new.count) Tag(e)\(moved > 0 ? ", \(moved) Aufgabe(n) verschoben" : "")")
        let days = new.count == 1 ? (new[0].halfDay ? "halber Tag" : "1 Tag") : "\(new.count) Tage"
        return moved > 0 ? "\(kind.label) eingetragen (\(days)), \(moved) Aufgabe(n) verschoben." : "\(kind.label) eingetragen (\(days))."
    }

    func removeAbsence(on day: LocalDate) {
        guard let absence = absence(on: day) else { return }
        do {
            try store.deleteAbsence(id: absence.id)
            absences.removeAll { $0.id == absence.id }
        } catch {
            report(error)
        }
    }

    /// Offene Aufgaben eines Tages auf den nächsten Arbeitstag schieben (z. B. heute krank).
    func moveOpenTasks(from day: LocalDate) {
        let target = Absences.nextWorkingDay(after: day, absences: absences)
        for task in dayTasks(day) where !task.isDone {
            plan(task.id, for: target)
        }
    }

    func beginAbsence(_ kind: AbsenceKind = .sick, from day: LocalDate? = nil) {
        let start = day ?? today
        absenceDraft = AbsenceDraft(kind: kind, from: start, through: start)
    }

    /// Legt eine Aufgabe oben oder unten in einem Tag (oder im Eingang) an.
    @discardableResult
    func addTask(title: String, customerID: UUID?, plannedDate: LocalDate?, atTop: Bool) -> TaskItem? {
        guard var task = addTask(title: title, customerID: customerID, plannedDate: plannedDate) else { return nil }
        if atTop {
            let siblings = tasks.filter { $0.plannedDate == plannedDate && $0.id != task.id }
            task.sortIndex = (siblings.map(\.sortIndex).min() ?? 1) - 1
            persist(task)
        }
        return task
    }

    /// Verschiebt eine Aufgabe in einen Tag (oder den Eingang), vor eine andere Aufgabe oder ans Ende.
    func move(_ id: UUID, to requestedDay: LocalDate?, before targetID: UUID?) {
        guard targetID != id, var task = self.task(id), !task.isStanding else { return }
        // Unteraufgabe auf den Tag ihrer Aufgabe (oder in den Eingang): wieder einfach unter der Aufgabe
        guard let day = normalizedDay(requestedDay, for: task) else {
            plan(id, for: nil)
            return
        }
        if task.plannedDate != day, task.scheduledStart != nil {
            task.scheduledStart = nil
            syncBlock(&task)
        }
        task.plannedDate = day
        var list = DayPlan.tasks(for: day, in: tasks).filter { $0.id != id }
        let position = targetID.flatMap { target in list.firstIndex { $0.id == target } } ?? list.count
        list.insert(task, at: position)
        for (index, var item) in list.enumerated() {
            let newIndex = Double(index + 1)
            guard item.id == id || item.dayOrder != newIndex else { continue }
            // Unteraufgaben behalten ihre Reihenfolge unter der Aufgabe
            if item.isSubtask {
                item.daySortIndex = newIndex
            } else {
                item.sortIndex = newIndex
            }
            persist(item)
        }
    }

    /// Nachträglich erfasste Zeit, z. B. aus dem Wochenkalender.
    func addEntry(taskID: UUID, start: Date, end: Date) {
        guard end > start else { return }
        let entry = TimeEntry(taskID: taskID, start: start, end: end)
        do {
            try store.save(entry)
            entries.append(entry)
        } catch {
            report(error)
        }
    }

    /// Ändert Beginn, Ende oder Aufgabe eines erfassten Eintrags (Kalender: ziehen oder „Zeit bearbeiten“).
    /// Ein laufender Eintrag bleibt laufend; nur sein Beginn ändert sich.
    func updateEntry(_ id: UUID, start: Date, end: Date?, taskID: UUID? = nil) {
        guard var entry = entries.first(where: { $0.id == id }) else { return }
        if let end, entry.end != nil, end <= start { return }
        let before = entry
        entry.start = start
        if entry.end != nil, let end { entry.end = end }
        if let taskID { entry.taskID = taskID }
        guard entry != before else { return }
        do {
            try store.save(entry)
            replace(entry)
            let clock = { (date: Date?) in date?.formatted(date: .omitted, time: .shortened) ?? "läuft" }
            AppLog.info("Zeit", "Eintrag geändert: \(clock(before.start))–\(clock(before.end)) → \(clock(entry.start))–\(clock(entry.end))")
        } catch {
            report(error)
        }
    }

    /// Zeitraum für eine neue Aufgabe nach Doppelklick in den Kalender (Viertelstunde, ohne andere Einträge zu überdecken).
    func proposedSlot(near click: Date) -> DateInterval {
        EntryEditing.newSlot(near: click, entries: dayEntries(LocalDate(click)), now: Date())
    }

    /// Schließt das Eingabefeld im Kalender, aber nur, wenn inzwischen kein anderes geöffnet wurde.
    func closeCalendarSlot(_ slot: DateInterval) {
        if calendarNewSlot == slot { calendarNewSlot = nil }
    }

    /// Neue Aufgabe direkt aus dem Kalender, für Arbeit, die weder als Aufgabe noch als Ticket da war.
    /// Was schon vorbei ist, wird als erfasste Zeit eingetragen und die Aufgabe gilt als erledigt
    /// (noch laufend bis jetzt: bleibt offen); was noch kommt, wird als Zeitblock geplant.
    @discardableResult
    func addTaskFromCalendar(title: String, slot: DateInterval) -> TaskItem? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, slot.duration > 0 else { return nil }
        let now = Date()
        guard var task = addTask(title: clean, customerID: nil, plannedDate: LocalDate(slot.start)) else { return nil }
        if slot.start < now {
            addEntry(taskID: task.id, start: slot.start, end: min(slot.end, now))
            if slot.end < now.addingTimeInterval(-60) {
                task.status = .done
                task.completedAt = slot.end
                persist(task)
            }
            AppLog.info("Kalender", "Aufgabe mit erfasster Zeit angelegt (\(Int(min(slot.end, now).timeIntervalSince(slot.start) / 60)) Min)")
        } else {
            task.estimateMinutes = Int(slot.duration / 60)
            persist(task)
            schedule(task.id, at: slot.start)
        }
        return self.task(task.id)
    }

    /// Andere erfasste Einträge rund um den Tag eines Eintrags (für Überschneidungen beim Ziehen).
    func entriesAround(_ entry: TimeEntry) -> [TimeEntry] {
        dayEntries(LocalDate(entry.start))
    }

    func deleteEntry(_ id: UUID) {
        do {
            try store.deleteEntry(id: id)
            entries.removeAll { $0.id == id }
        } catch {
            report(error)
        }
    }

    func leaveFocus() {
        let target = focusReturn ?? .today
        selection = target == .focus ? .today : target
    }

    /// Nächste offene Aufgabe von heute in den Fokus holen.
    func focusNextTask() {
        let next = DayPlan.nextOpenTask(after: focusTask?.id, in: todayTasks)
        focusedTaskID = next?.id
    }

    // MARK: Tagesplanung

    func showPlanningIfDue() {
        guard isPlanningDue, UserDefaults.standard.bool(forKey: Preferences.planningOnLaunchKey) else { return }
        selection = .planning
    }

    func finishPlanning() {
        lastPlannedDay = today
        UserDefaults.standard.set(today.string, forKey: Preferences.lastPlannedDayKey)
        rolledOverIDs = []
        selection = .today
    }

    /// Von gestern übernommene, noch offene Aufgaben.
    var rolledOverTasks: [TaskItem] {
        todayTasks.filter { rolledOverIDs.contains($0.id) && !$0.isDone }
    }

    func acknowledgeRolledOver(_ id: UUID) {
        rolledOverIDs.remove(id)
    }

    private func freeGaps(excluding taskID: UUID?) -> [DateInterval] {
        let window = workdayInterval
        var busy = FreeTime.busy(events: events, within: window)
        busy += scheduledToday
            .filter { $0.id != taskID }
            .compactMap(\.scheduledInterval)
        return FreeTime.gaps(in: window, busy: busy)
    }

    /// Schreibt den Zeitblock in den Kalender „Tagwerk“, wenn das eingeschaltet ist.
    private func syncBlock(_ task: inout TaskItem) {
        do {
            if let interval = task.scheduledInterval, writesBlocksToCalendar {
                task.calendarEventID = try calendarProvider.saveBlock(
                    title: task.title,
                    start: interval.start,
                    end: interval.end,
                    existingID: task.calendarEventID,
                    calendarID: blockCalendarID
                )
            } else if task.scheduledStart == nil, let eventID = task.calendarEventID {
                try calendarProvider.removeBlock(id: eventID)
                task.calendarEventID = nil
            }
        } catch {
            report(error)
        }
    }

    // MARK: Tagesabschluss und Buchung

    var bookingRules: BookingRules {
        _ = settingsVersion
        let defaults = UserDefaults.standard
        return BookingRules(
            roundingStep: max(1, defaults.integer(forKey: Preferences.roundingStepKey)),
            roundingMode: RoundingMode(rawValue: defaults.string(forKey: Preferences.roundingModeKey) ?? "") ?? .nearest
        )
    }

    /// Standard für Tickets ohne eigenen Work Log Type.
    var defaultWorklogType: String {
        _ = settingsVersion
        let stored = UserDefaults.standard.string(forKey: Preferences.defaultWorklogTypeKey) ?? ""
        return stored.isEmpty ? "Ticketbearbeitung" : stored
    }

    /// Work Log Type eines Tickets: selbst gewählt oder der Standard.
    func worklogType(for task: TaskItem?) -> String {
        if let chosen = task?.worklogType, !chosen.isEmpty { return chosen }
        if let task, let inherited = parent(of: task)?.worklogType, !inherited.isEmpty { return inherited }
        return defaultWorklogType
    }

    func setWorklogType(_ value: String?, for id: UUID) {
        guard var task = self.task(id), task.worklogType != value else { return }
        task.worklogType = value
        persist(task)
    }

    func closeLines(for day: LocalDate) -> [BookingLine] {
        DailyClose.lines(for: day, tasks: tasks, entries: entries, bookings: bookings, rules: bookingRules, now: now)
    }

    var canUseManageEngine: Bool {
        _ = settingsVersion
        return manageEngine.isReady
    }

    func reflection(for day: LocalDate) -> String {
        UserDefaults.standard.string(forKey: Preferences.reflectionKey(for: day)) ?? ""
    }

    func setReflection(_ text: String, for day: LocalDate) {
        UserDefaults.standard.set(text, forKey: Preferences.reflectionKey(for: day))
    }

    /// Bereitet alle vollständigen Zeilen des Tages als Buchungen vor. `minutes` überschreibt die gerundete Zeit.
    func prepareBookings(for day: LocalDate, minutes overrides: [UUID: Int]) {
        for line in closeLines(for: day) {
            for booking in DailyClose.prepare(line, minutes: overrides[line.id], now: Date()) {
                save(booking)
            }
        }
    }

    /// Bucht den Tag: bereitet vor und sendet die Worklogs an ManageEngine.
    func bookDay(_ day: LocalDate, minutes overrides: [UUID: Int]) async -> String {
        await connectMissingTickets(for: day)
        prepareBookings(for: day, minutes: overrides)
        let pendingME = BookingQueue.due(bookings.filter { $0.day == day }, target: .manageEngine, now: Date())
        var parts: [String] = []
        if !pendingME.isEmpty {
            if manageEngine.isReady {
                let result = await sendManageEngine(pendingME)
                parts.append(result)
            } else {
                parts.append("\(pendingME.count) Worklog(s) warten, bis ManageEngine in den Einstellungen eingerichtet ist.")
            }
        }
        return parts.isEmpty ? "Alle Worklogs sind gesendet." : parts.joined(separator: " ")
    }

    /// Sendet fällige Worklogs, auch Wiederholungen nach Fehlern.
    func retryManageEngine() async -> String {
        let due = BookingQueue.due(bookings, target: .manageEngine, now: Date())
        guard !due.isEmpty else { return "Nichts zu senden." }
        return await sendManageEngine(due)
    }

    private func sendManageEngine(_ due: [Booking]) async -> String {
        isSendingBookings = true
        defer { isSendingBookings = false }
        var sent = 0
        var failed = 0
        for var booking in due {
            // Ohne interne ID (nur Nummer zugeordnet) erst bei ManageEngine nachschlagen, statt still zu überspringen
            guard let key = await ticketKey(for: booking) else {
                let number = task(booking.taskID).map { resolved($0) }?.linkedTicketNumber
                let error = number.map { "Ticket #\($0) wurde in ManageEngine nicht gefunden. Nummer prüfen oder das Ticket neu zuordnen." }
                    ?? "Der Aufgabe ist kein Ticket zugeordnet."
                save(BookingQueue.failed(booking, error: error, now: Date()))
                AppLog.error("Worklog", error)
                failed += 1
                continue
            }
            if booking.ticketKey != key {
                booking.ticketKey = key
            }
            let start = worklogStart(for: booking)
            do {
                let reference = try await manageEngine.addWorklog(
                    requestKey: key,
                    description: booking.description,
                    minutes: booking.minutes,
                    start: start,
                    worklogType: worklogType(for: task(booking.taskID))
                )
                save(BookingQueue.confirmed(booking, reference: reference, now: Date()))
                AppLog.info("Worklog", "Ticket \(key): \(booking.minutes) Minuten gebucht")
                sent += 1
            } catch {
                save(BookingQueue.failed(booking, error: String(describing: error), now: Date()))
                AppLog.error("Worklog", "Ticket \(key): \(error)")
                failed += 1
            }
        }
        if failed == 0 { return "\(sent) Worklog(s) an ManageEngine gesendet." }
        return "\(sent) gesendet, \(failed) fehlgeschlagen. Tagwerk versucht es später erneut."
    }

    /// Interne ManageEngine-ID für den Worklog: aus der Buchung, sonst aus der Aufgabe, sonst über die Ticketnummer gesucht
    /// (und dann an der Aufgabe gemerkt).
    private func ticketKey(for booking: Booking) async -> String? {
        if let key = booking.ticketKey, !key.isEmpty { return key }
        guard let current = task(booking.taskID) else { return nil }
        let effective = resolved(current)
        if let key = effective.linkedTicketKey, !key.isEmpty { return key }
        guard let number = effective.linkedTicketNumber else { return nil }
        return await lookUpTicketKey(number: number)
    }

    /// Sucht das Ticket zur Nummer bei ManageEngine und merkt sich die interne ID an den Aufgaben.
    @discardableResult
    private func lookUpTicketKey(number: String) async -> String? {
        let search = await manageEngine.findTickets(number)
        guard let ticket = search.tickets.first(where: { $0.number == number }) ?? (search.tickets.count == 1 ? search.tickets.first : nil) else {
            AppLog.warning("Worklog", "Ticket #\(number) nicht gefunden: \(search.attempts.joined(separator: "; "))")
            return nil
        }
        rememberTicketKey(ticket, number: number)
        AppLog.info("Worklog", "Ticket #\(number) hat die interne ID \(ticket.key)")
        return ticket.key
    }

    /// Für Zeilen des Tages, deren Ticket nur als Nummer zugeordnet ist (z. B. über Claude oder ein Ticket von Kollegen),
    /// die Verbindung zu ManageEngine herstellen. Sonst bleibt der Worklog mit „nicht verbunden“ hängen.
    func connectMissingTickets(for day: LocalDate) async {
        guard manageEngine.isReady else { return }
        let numbers = Set(closeLines(for: day)
            .filter { $0.issues.contains(.missingTicketKey) }
            .compactMap(\.task.linkedTicketNumber))
        for number in numbers.sorted() {
            await lookUpTicketKey(number: number)
        }
    }

    /// Trägt die interne ID bei allen Aufgaben mit dieser Ticketnummer nach, denen sie noch fehlt.
    private func rememberTicketKey(_ ticket: ManageEngineTicket, number: String) {
        for var item in tasks where item.source != .ticket && item.ticketNumber == number && (item.ticketKey ?? "").isEmpty {
            item.ticketKey = ticket.key
            if (item.ticketTitle ?? "").isEmpty { item.ticketTitle = ticket.subject }
            persist(item)
        }
    }

    /// Kein Worklog im Ticket für diese Zeile (dort freiwillig).
    func skipManageEngine(_ line: BookingLine, minutes: Int) {
        save(BookingQueue.skipped(line, target: .manageEngine, minutes: minutes, now: Date()))
    }

    func unskipManageEngine(_ line: BookingLine) {
        guard var booking = line.bookings[.manageEngine], booking.status == .skipped else { return }
        booking.status = .pending
        booking.updatedAt = Date()
        save(booking)
    }

    /// Liste des Tages zum Kopieren (Aufgabe, Kunde, Ticket, Stunden, Beschreibung), z. B. zum Abtippen in ein anderes System.
    func dayListText(for day: LocalDate, minutes overrides: [UUID: Int]) -> String {
        DayList.text(closeLines(for: day), minutes: overrides) { [weak self] id in
            self?.customer(id)?.name
        }
    }

    /// Beginn des Worklogs: der früheste Eintrag aller Teile der Zeile (bei zusammengefassten Unteraufgaben).
    private func worklogStart(for booking: Booking) -> Date {
        let ids = closeLines(for: booking.day).first { $0.id == booking.taskID }?.parts.map(\.task.id) ?? []
        return (ids.isEmpty ? [booking.taskID] : ids).map { firstStart(of: $0, on: booking.day) }.min()
            ?? firstStart(of: booking.taskID, on: booking.day)
    }

    private func firstStart(of taskID: UUID, on day: LocalDate) -> Date {
        let interval = day.interval()
        return entries
            .filter { $0.taskID == taskID && TimeMath.overlap(of: $0, with: interval, now: now) > 0 }
            .map(\.start)
            .min() ?? FreeTime.date(on: day, minutes: 9 * 60)
    }

    // MARK: Tickets aus ManageEngine

    /// Holt die eigenen offenen Tickets in den Eingang. Bekannte Tickets werden nicht doppelt angelegt.
    func importTickets() async {
        guard manageEngine.isReady else {
            ticketSyncMessage = "ManageEngine ist noch nicht eingerichtet (Einstellungen › ManageEngine)."
            return
        }
        isSyncingTickets = true
        defer { isSyncingTickets = false }
        do {
            let tickets = try await manageEngine.fetchTickets()
            var added = 0
            var known = 0
            for ticket in tickets {
                // Betreff aktuell halten, auch bei Aufgaben, denen das Ticket nur zugeordnet ist
                updateTicketTitle(ticket)
                guard ticket.isOpen else { continue }
                let isKnown = tasks.contains { $0.linkedTicketKey == ticket.key || $0.linkedTicketNumber == ticket.number }
                guard !isKnown else {
                    known += 1
                    continue
                }
                let task = TaskItem(
                    title: ticket.subject,
                    customerID: customerID(forAccount: ticket.accountName),
                    source: .ticket,
                    externalID: ticket.number,
                    externalURL: ticket.webURL,
                    externalKey: ticket.key,
                    ticketTitle: ticket.subject
                )
                persist(task)
                added += 1
            }
            await fillMissingTicketTitles()
            lastTicketSync = Date()
            ticketSyncMessage = added == 0 ? "Keine neuen Tickets." : "\(added) neue(s) Ticket(s) im Eingang."
            AppLog.info("Tickets", "Abruf: \(tickets.count) geliefert, \(tickets.filter(\.isOpen).count) offen, \(known) bekannt, \(added) neu")
            let open = tickets.filter(\.isOpen).count
            let statuses = Set(tickets.filter { !$0.isOpen }.map(\.statusName)).sorted().joined(separator: ", ")
            ticketSyncDetail = """
            \(Date().formatted(date: .omitted, time: .standard)): ManageEngine lieferte \(tickets.count) Tickets für Techniker-ID \(manageEngine.config.technicianID). \
            Offen: \(open), davon schon in Tagwerk: \(known), neu: \(added).\(statuses.isEmpty ? "" : " Nicht übernommen (gilt als geschlossen): \(statuses).")
            """
        } catch {
            ticketSyncMessage = String(describing: error)
            ticketSyncDetail = "\(Date().formatted(date: .omitted, time: .standard)): \(String(describing: error))"
            AppLog.error("Tickets", "Abruf fehlgeschlagen: \(error)")
        }
    }

    /// Merkt sich den Betreff eines Tickets bei allen Aufgaben, die zu diesem Ticket gehören.
    private func updateTicketTitle(_ ticket: ManageEngineTicket) {
        guard !ticket.subject.isEmpty else { return }
        for var task in tasks where task.linkedTicketKey == ticket.key || task.linkedTicketNumber == ticket.number {
            guard task.ticketTitle != ticket.subject else { continue }
            task.ticketTitle = ticket.subject
            persist(task)
        }
    }

    /// Holt den Betreff für offene Aufgaben mit Ticket, bei denen er noch fehlt (z. B. Tickets von Kollegen).
    func fillMissingTicketTitles() async {
        guard manageEngine.isReady else { return }
        // Fehlt der Betreff oder die interne ID (für den Worklog), bei ManageEngine nachschlagen
        let missing = tasks.filter { task in
            !task.isDone && task.source != .ticket && task.ticketNumber != nil
                && ((task.ticketTitle ?? "").isEmpty || (task.ticketKey ?? "").isEmpty)
                && !ticketTitleMisses.contains(task.ticketNumber ?? "")
        }
        var looked = Set<String>()
        for task in missing.prefix(15) {
            guard let number = task.linkedTicketNumber, looked.insert(number).inserted else { continue }
            let search = await manageEngine.findTickets(number)
            if search.tickets.isEmpty { ticketTitleMisses.insert(number) }
            if let ticket = search.tickets.first(where: { $0.number == number }) ?? search.tickets.first {
                updateTicketTitle(ticket)
                // Fehlte die Verbindung (nur Nummer), jetzt nachtragen
                rememberTicketKey(ticket, number: number)
            }
        }
    }

    /// Ergebnis von „Verbindung testen“: Meldung und passende Techniker, falls die ID noch nicht stimmt.
    struct ManageEngineCheck {
        var ok: Bool
        var message: String
        var suggestions: [ManageEngineTechnician] = []
    }

    func testManageEngine() async -> ManageEngineCheck {
        let config = manageEngine.config
        do {
            let technicians = try await manageEngine.testConnection()
            let entered = config.technicianID.trimmingCharacters(in: .whitespaces)
            if let own = technicians.first(where: { $0.id == entered }) {
                return ManageEngineCheck(ok: true, message: "Verbindung klappt. Die Techniker-ID gehört zu \(own.name).")
            }
            let matches = ManageEngineAPI.technicians(matching: entered, in: technicians)
            if !matches.isEmpty {
                return ManageEngineCheck(ok: true, message: "Verbindung klappt. Wähle deinen Eintrag, dann stimmt die Techniker-ID:", suggestions: matches)
            }
            if config.technicianIDIsNumeric {
                return ManageEngineCheck(ok: true, message: "Verbindung klappt. Die Techniker-ID kam in den letzten Tickets nicht vor; das ist in Ordnung, wenn dir gerade nichts zugewiesen ist.")
            }
            // In den Tickets nicht dabei: in der Technikerliste nach dem eingetragenen Namen suchen
            if !entered.isEmpty, let found = try? await manageEngine.searchTechnicians(entered), !found.isEmpty {
                return ManageEngineCheck(ok: true, message: "Verbindung klappt. Zu „\(entered)“ gefunden, wähle deinen Eintrag:", suggestions: found)
            }
            return ManageEngineCheck(
                ok: true,
                message: technicians.isEmpty
                    ? "Verbindung klappt, aber in den letzten Tickets steht kein Techniker. Die Techniker-ID (eine Zahl) findest du in ServiceDesk Plus unter Admin › Techniker."
                    : "Verbindung klappt. Wer bist du? Wähle deinen Namen, dann ist die Techniker-ID eingetragen:",
                suggestions: technicians
            )
        } catch {
            return ManageEngineCheck(ok: false, message: String(describing: error))
        }
    }

    /// Sucht die eigene Techniker-ID nach Name, Mail-Adresse oder Benutzername.
    func searchTechnicians(_ query: String) async -> ManageEngineCheck {
        do {
            let found = try await manageEngine.searchTechnicians(query)
            if found.isEmpty {
                return ManageEngineCheck(ok: false, message: "Niemand zu „\(query)“ gefunden. Versuch den Nachnamen oder die Mail-Adresse.")
            }
            return ManageEngineCheck(ok: true, message: found.count == 1 ? "Gefunden:" : "\(found.count) Techniker gefunden, wähle deinen Eintrag:", suggestions: found)
        } catch {
            return ManageEngineCheck(ok: false, message: String(describing: error))
        }
    }

    func setManageEngineToken(_ token: String) {
        manageEngine.setToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
        settingsChanged()
    }

    var hasManageEngineToken: Bool {
        _ = settingsVersion
        return manageEngine.hasToken
    }

    private func customerID(forAccount account: String?) -> UUID? {
        guard let account = account?.trimmingCharacters(in: .whitespaces), !account.isEmpty else { return nil }
        let match = customers.first { customer in
            let names = [customer.manageEngineAccount, customer.name].compactMap { $0 }
            return names.contains { $0.compare(account, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
        return match?.id
    }

    private func autoSyncTicketsIfDue() {
        guard SnapshotMode.directory == nil,
              !isSyncingTickets,
              UserDefaults.standard.bool(forKey: Preferences.meAutoFetchKey),
              manageEngine.isReady else { return }
        let due = lastTicketSync.map { now.timeIntervalSince($0) > 5 * 60 } ?? true
        guard due else { return }
        lastTicketSync = now
        Task { await importTickets() }
    }

    // MARK: Wochenziele

    var currentWeekStart: LocalDate { today.startOfWeek() }

    func goals(forWeekStarting week: LocalDate) -> [WeeklyGoal] {
        goals
            .filter { $0.weekStart == week }
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func goal(_ id: UUID?) -> WeeklyGoal? {
        guard let id else { return nil }
        return goals.first { $0.id == id }
    }

    @discardableResult
    func addGoal(title rawTitle: String, customerID: UUID?, weekStart: LocalDate) -> WeeklyGoal? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let goal = WeeklyGoal(weekStart: weekStart, customerID: customerID, title: title)
        save(goal)
        return goal
    }

    func toggleGoal(_ id: UUID) {
        guard var goal = goal(id) else { return }
        goal.isDone.toggle()
        save(goal)
    }

    // MARK: Lange Ziele

    /// Aktive Ziele nach Zieldatum, danach erledigte.
    var sortedLongGoals: [LongGoal] { Goals.sorted(longGoals) }

    var activeLongGoals: [LongGoal] { sortedLongGoals.filter { !$0.isDone } }

    func longGoal(_ id: UUID?) -> LongGoal? {
        guard let id else { return nil }
        return longGoals.first { $0.id == id }
    }

    func progress(of goal: LongGoal) -> GoalProgress {
        Goals.progress(of: goal, tasks: tasks, entries: entries, today: today, now: runningEntry == nil ? Date() : now)
    }

    /// Aufgaben des Ziels (ohne Unteraufgaben): offene zuerst.
    func goalTasks(_ goal: LongGoal) -> [TaskItem] {
        Goals.tasks(of: goal, in: tasks)
            .filter { $0.parentID == nil }
            .sorted { lhs, rhs in
                if lhs.isDone != rhs.isDone { return !lhs.isDone }
                if lhs.isDone { return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast) }
                return lhs.createdAt < rhs.createdAt
            }
    }

    @discardableResult
    func addLongGoal(title rawTitle: String, dueDate: LocalDate?, targetMinutes: Int?, customerID: UUID?) -> LongGoal? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let goal = LongGoal(title: title, customerID: customerID, dueDate: dueDate, targetMinutes: targetMinutes.flatMap { $0 > 0 ? $0 : nil })
        save(goal)
        return goal
    }

    func update(_ goal: LongGoal) {
        save(goal)
    }

    func toggleLongGoal(_ id: UUID) {
        guard var goal = longGoal(id) else { return }
        goal.isDone.toggle()
        goal.completedAt = goal.isDone ? Date() : nil
        save(goal)
    }

    func deleteLongGoal(_ id: UUID) {
        do {
            try store.deleteLongGoal(id: id)
            longGoals.removeAll { $0.id == id }
            for index in tasks.indices where tasks[index].longGoalID == id {
                tasks[index].longGoalID = nil
            }
        } catch {
            report(error)
        }
    }

    /// Aufgabe einem langen Ziel zuordnen (`nil` = keinem). Ohne Kunden übernimmt sie den des Ziels.
    func setLongGoal(_ goalID: UUID?, for taskID: UUID) {
        guard var task = self.task(taskID), task.longGoalID != goalID else { return }
        task.longGoalID = goalID
        if task.customerID == nil, let customerID = longGoal(goalID)?.customerID {
            task.customerID = customerID
        }
        persist(task)
    }

    /// Neue Aufgabe für ein Ziel, im Eingang (oder für heute).
    @discardableResult
    func addTask(title: String, toGoal goalID: UUID, plannedDate: LocalDate? = nil) -> TaskItem? {
        guard var task = addTask(title: title, customerID: longGoal(goalID)?.customerID, plannedDate: plannedDate) else { return nil }
        task.longGoalID = goalID
        persist(task)
        return task
    }

    private func save(_ goal: LongGoal) {
        do {
            try store.save(goal)
            if let index = longGoals.firstIndex(where: { $0.id == goal.id }) {
                longGoals[index] = goal
            } else {
                longGoals.append(goal)
            }
        } catch {
            report(error)
        }
    }

    func deleteGoal(_ id: UUID) {
        do {
            try store.deleteGoal(id: id)
            goals.removeAll { $0.id == id }
            for index in tasks.indices where tasks[index].goalID == id {
                tasks[index].goalID = nil
            }
        } catch {
            report(error)
        }
    }

    func setGoal(_ goalID: UUID?, for taskID: UUID) {
        guard var task = self.task(taskID), task.goalID != goalID else { return }
        task.goalID = goalID
        persist(task)
    }

    func trackedSeconds(for goal: WeeklyGoal) -> TimeInterval {
        WeeklyReview.trackedSeconds(for: goal, tasks: tasks, entries: entries, now: now)
    }

    // MARK: Leerlauf

    /// Prüft, ob während eines laufenden Timers länger keine Eingabe kam, und fragt nach der Rückkehr nach.
    private func checkIdle() {
        guard SnapshotMode.directory == nil, idlePrompt == nil, let running = runningEntry, let taskID = running.taskID else {
            idleSince = nil
            return
        }
        let thresholdMinutes = UserDefaults.standard.integer(forKey: Preferences.idleMinutesKey)
        guard thresholdMinutes > 0 else { return }
        let idle = IdleMonitor.secondsSinceLastInput()
        if idle >= TimeInterval(thresholdMinutes * 60) {
            if idleSince == nil {
                idleSince = max(running.start, now.addingTimeInterval(-idle))
            }
        } else if let since = idleSince, idle < 10 {
            idleSince = nil
            idlePrompt = IdlePrompt(start: since, end: now, taskID: taskID)
            NSApp.activate()
        }
    }

    /// `asLunchBreak`: die abgezogene Zeit war die Mittagspause und steht dann als Pause im Kalender.
    /// Sonst wird sie nur abgezogen (kurze Unterbrechungen werden nicht eingetragen).
    func resolveIdle(_ decision: IdleDecision, asLunchBreak: Bool = false) {
        guard let prompt = idlePrompt else { return }
        idlePrompt = nil
        let now = Date()
        apply(TimerLogic.resolveIdle(entries: entries, idleStart: prompt.start, now: now, decision: decision))
        if asLunchBreak, decision == .discard {
            addBreak(start: prompt.start, end: now, note: "Mittag")
        }
    }

    // MARK: Schnell erfassen und Drag-and-drop

    func installQuickCapture() {
        guard SnapshotMode.directory == nil else { return }
        quickCapture.installHotKey()
    }

    @discardableResult
    func showQuickCapture() -> NSWindow? {
        quickCapture.show()
    }

    func hideQuickCapture() {
        quickCapture.hide()
    }

    /// Mail als Aufgabe im Eingang (z. B. aus Outlook hineingezogen).
    /// Mit `plannedDate` (z. B. auf „Heute“ gezogen) steht sie gleich an dem Tag statt im Eingang.
    func addMailTask(subject: String?, from: String?, link: String?, plannedDate: LocalDate? = nil) {
        let title = (subject?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Mail ohne Betreff"
        let task = TaskItem(
            title: title,
            notes: from.map { "Von: \($0)" } ?? "",
            source: .mail,
            externalURL: link,
            plannedDate: plannedDate
        )
        persist(task)
        inboxMessage = "„\(title)“ \(dropPlace(plannedDate))."
    }

    func addLinkTask(_ url: URL, plannedDate: LocalDate? = nil) {
        let title = url.host.map { "Link: \($0)" } ?? url.absoluteString
        persist(TaskItem(title: title, externalURL: url.absoluteString, plannedDate: plannedDate))
        inboxMessage = "Link \(dropPlace(plannedDate))."
    }

    func addTextTask(_ text: String, plannedDate: LocalDate? = nil) {
        let firstLine = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return }
        addTask(title: String(firstLine.prefix(200)), customerID: nil, plannedDate: plannedDate)
        inboxMessage = "Text \(dropPlace(plannedDate))."
    }

    /// Hineingezogen, aber nicht lesbar: kurzer Hinweis statt Stille.
    func reportUnreadableDrop() {
        inboxMessage = "Format nicht erkannt; Details stehen im Protokoll."
    }

    private func dropPlace(_ day: LocalDate?) -> String {
        guard let day else { return "liegt im Eingang" }
        return day == today ? "steht auf Heute" : "ist eingeplant"
    }

    // MARK: Sicherung und Export

    var dataFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tagwerk", isDirectory: true)
    }

    var backupFolder: URL { dataFolder.appendingPathComponent("Backups", isDirectory: true) }

    /// Eine Sicherung pro Tag, die letzten 14 bleiben.
    func backupIfDue() {
        let target = backupFolder.appendingPathComponent(BackupPolicy.fileName(for: today))
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try store.backup(to: target)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: backupFolder.path)) ?? []
            for name in BackupPolicy.filesToDelete(names, keep: 14) {
                try? FileManager.default.removeItem(at: backupFolder.appendingPathComponent(name))
            }
        } catch {
            report(error)
        }
    }

    var backupCount: Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backupFolder.path)) ?? []
        return names.filter { $0.hasPrefix(BackupPolicy.filePrefix) }.count
    }

    /// Alle Zeiten als CSV im Export-Ordner. Gibt die Datei zurück.
    func exportAllTimes() -> URL? {
        let text = TimeExport.csv(entries: entries, tasks: tasks, customers: customers, now: now)
        let folder = dataFolder.appendingPathComponent("Exporte", isDirectory: true)
        let file = folder.appendingPathComponent("Zeiten-\(today.string).csv")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.data(using: .utf8)?.write(to: file)
            return file
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: Kunden

    @discardableResult
    func addCustomer(name rawName: String) -> Customer? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let customer = Customer(name: name, colorIndex: customers.count % CustomerPalette.count)
        save(customer)
        return customer
    }

    func update(_ customer: Customer) {
        save(customer)
    }

    // MARK: Intern

    private func reload() {
        do {
            let snapshot = try store.load()
            customers = snapshot.customers
            tasks = snapshot.tasks
            entries = snapshot.entries
            bookings = snapshot.bookings
            goals = snapshot.goals
            longGoals = snapshot.longGoals
            absences = snapshot.absences
            breaks = snapshot.breaks
            meetings = snapshot.meetings
            cleanUpHTMLEntities()
        } catch {
            report(error)
        }
    }

    /// Titel mit „&lt;“ und Co. (von früheren Claude-Anfragen) einmal in normale Zeichen umwandeln.
    private func cleanUpHTMLEntities() {
        // Mail-Betreffe, deren Umlaute noch verpackt sind („=?iso-8859-2?Q?…?=“), einmal lesbar machen
        for task in tasks where task.title.contains("=?") && task.title.contains("?=") {
            var fixed = task
            fixed.title = EmailHeaderParser.decodeHeaderValue(task.title)
            if fixed != task {
                try? store.save(fixed)
                if let index = tasks.firstIndex(where: { $0.id == fixed.id }) { tasks[index] = fixed }
            }
        }
        for task in tasks where task.title.contains("&") || task.workDescription.contains("&") || task.notes.contains("&") {
            var fixed = task
            fixed.title = HTMLText.decodeEntities(task.title)
            fixed.workDescription = HTMLText.decodeEntities(task.workDescription)
            fixed.notes = HTMLText.decodeEntities(task.notes)
            if fixed != task {
                try? store.save(fixed)
                if let index = tasks.firstIndex(where: { $0.id == fixed.id }) { tasks[index] = fixed }
            }
        }
    }

    /// Hat ein anderes Programm (z. B. Claude über den MCP-Server) etwas geändert, neu laden.
    private func reloadIfChangedElsewhere() {
        guard let token = store.changeToken() else { return }
        defer { lastChangeToken = token }
        guard let last = lastChangeToken, last != token else { return }
        reload()
    }

    private func rollOverOpenTasks() {
        for var task in DayPlan.rollOver(tasks, to: today) {
            task.scheduledStart = nil
            persist(task)
            rolledOverIDs.insert(task.id)
        }
    }

    private func startTicker() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        now = Date()
        let current = LocalDate(now)
        if current != today {
            today = current
            rolledOverIDs = []
            rollOverOpenTasks()
            refreshEvents()
            showPlanningIfDue()
            backupIfDue()
        }
        autoSyncTicketsIfDue()
        reloadIfChangedElsewhere()
        checkPomodoro()
        if tickCount % 600 == 0 { updater.checkIfDue() }
        if tickCount % 30 == 0, updater.pendingAutoInstall {
            updater.installIfPending(goodMoment: isGoodMomentForUpdate)
        }
        tickCount += 1
        if tickCount % 5 == 0 {
            checkIdle()
        }
    }

    /// Passt ein Neustart für ein Update gerade? Nur, wenn seit ein paar Minuten keine Eingabe kam, nichts zum
    /// Bearbeiten offen ist und weder Pomodoro noch Musik laufen. Ein laufender Timer zählt nach dem Neustart weiter.
    var isGoodMomentForUpdate: Bool {
        guard IdleMonitor.secondsSinceLastInput() >= 180 else { return false }
        let editing = timeEntryDraft != nil || breakDraft != nil || absenceDraft != nil || editingEntry != nil
            || meetingContext != nil || showsCommandBar || detailTaskID != nil || idlePrompt != nil
        let pomodoroActive = pomodoro.map { $0.phase != .ready } ?? false
        return !editing && !pomodoroActive && music.state != .playing
    }

    private func persist(_ task: TaskItem) {
        do {
            try store.save(task)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
            } else {
                tasks.append(task)
            }
        } catch {
            report(error)
        }
    }

    private func save(_ customer: Customer) {
        do {
            try store.save(customer)
            if let index = customers.firstIndex(where: { $0.id == customer.id }) {
                customers[index] = customer
            } else {
                customers.append(customer)
            }
        } catch {
            report(error)
        }
    }

    private func save(_ goal: WeeklyGoal) {
        do {
            try store.save(goal)
            if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[index] = goal
            } else {
                goals.append(goal)
            }
        } catch {
            report(error)
        }
    }

    private func save(_ booking: Booking) {
        do {
            try store.save(booking)
            if let index = bookings.firstIndex(where: { $0.id == booking.id }) {
                bookings[index] = booking
            } else {
                bookings.append(booking)
            }
        } catch {
            report(error)
        }
    }

    private func replace(_ entry: TimeEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    private func report(_ error: Error) {
        lastError = String(describing: error)
        AppLog.error("App", String(describing: error))
    }
}

/// Kurze Rückmeldung unten im Fenster.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
}

/// Fenster „Mittagspause nachtragen“ oder „Mittagspause bearbeiten“.
struct BreakDraft: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
    var note: String = ""
    /// gesetzt beim Bearbeiten einer eingetragenen Pause
    var breakID: UUID? = nil
    /// laufende Pause: nur der Beginn lässt sich ändern
    var isRunning = false
}

struct IdlePrompt: Identifiable, Equatable {
    let id = UUID()
    let start: Date
    let end: Date
    let taskID: UUID

    var minutes: Int { max(1, Int(end.timeIntervalSince(start) / 60)) }
}

enum IdleMonitor {
    /// Sekunden seit der letzten Maus- oder Tastatureingabe.
    static func secondsSinceLastInput() -> TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
