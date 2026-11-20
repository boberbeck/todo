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
    private(set) var pspElements: [PSPElement] = []
    private(set) var bookings: [Booking] = []
    private(set) var goals: [WeeklyGoal] = []
    /// Erkannte Pause während eines laufenden Timers, wartet auf eine Entscheidung.
    var idlePrompt: IdlePrompt?
    /// Zeigt den Abgleich mit SAP ByDesign. `sapSyncRows` füllt ihn vorab (Vorschau, Bildschirmfotos).
    var showsSAPSync = false
    var sapSyncRows: [SAPTaskRow]?
    private(set) var inboxMessage: String?
    private(set) var lastTicketSync: Date?
    private(set) var ticketSyncMessage: String?
    private(set) var isSyncingTickets = false
    private(set) var isSendingBookings = false

    var selection: SidebarItem? = .today
    /// Wohin der Pfeil im Fokus zurückführt. Setzt die Hauptansicht beim Wechsel in den Fokus.
    @ObservationIgnored var focusReturn: SidebarItem?
    /// Musik im Fokus (Apple Music).
    let music = FocusMusic()
    /// Aufgabe, die im Fokus-Modus gezeigt wird. Ohne Auswahl: die laufende oder die nächste offene.
    var focusedTaskID: UUID?
    /// Wird hochgezählt, wenn per ⌘N eine neue Aufgabe angelegt werden soll.
    private(set) var newTaskRequest = 0
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
        calendarAccess = calendar.access
        calendar.onChange = { [weak self] in
            self?.refreshEvents()
        }
        refreshEvents()
        startTicker()
        if SnapshotMode.directory == nil {
            showPlanningIfDue()
            backupIfDue()
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
                guard task.isDone, let completed = task.completedAt else { return false }
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
        let matching = tasks.filter { $0.customerID == customerID && $0.isDone == done }
        if done {
            return matching.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
        return matching.sorted { $0.createdAt > $1.createdAt }
    }

    func openTaskCount(for customerID: UUID) -> Int {
        tasks.filter { $0.customerID == customerID && !$0.isDone }.count
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
            guard task.isDone, let completed = task.completedAt else { return false }
            return LocalDate(completed) == day
        }.count
    }

    /// "0:23 / 0:30" – erfasst / geplant.
    func timeLabel(for task: TaskItem, now: Date) -> String {
        let tracked = TimeMath.format(self.tracked(taskID: task.id, now: now))
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
        guard var task = self.task(id), !task.isDone else { return }
        if isRunning(id) { stopTimer() }
        let next = DayPlan.nextOpenTask(after: id, in: todayTasks)
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
    func plan(_ id: UUID, for day: LocalDate?) {
        guard var task = self.task(id), task.plannedDate != day else { return }
        task.plannedDate = day
        task.sortIndex = DayPlan.nextSortIndex(in: tasks.filter { $0.plannedDate == day })
        if task.scheduledStart != nil {
            task.scheduledStart = nil
            syncBlock(&task)
        }
        persist(task)
    }

    func moveTodayTasks(from source: IndexSet, to destination: Int) {
        for task in DayPlan.reorder(todayTasks, from: source, to: destination) {
            persist(task)
        }
    }

    func delete(_ id: UUID) {
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

    func setWorkType(_ workType: WorkType?, for id: UUID) {
        guard var task = self.task(id), task.workType != workType else { return }
        task.workType = workType
        persist(task)
    }

    func setPSPElement(_ value: String, for id: UUID) {
        let cleaned = value.trimmingCharacters(in: .whitespaces)
        let newValue: String? = cleaned.isEmpty ? nil : cleaned
        guard var task = self.task(id), task.pspElement != newValue else { return }
        task.pspElement = newValue
        persist(task)
        if let code = newValue,
           var psp = pspElements.first(where: { $0.code == code && $0.customerID == task.customerID }) {
            psp.lastUsedAt = Date()
            save(psp)
        }
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

    func setCustomer(_ customerID: UUID?, for id: UUID) {
        guard var task = self.task(id), task.customerID != customerID else { return }
        task.customerID = customerID
        persist(task)
    }

    func openFocus(_ id: UUID) {
        focusedTaskID = id
        selection = .focus
    }

    func requestNewTask() {
        selection = .today
        newTaskRequest += 1
    }

    // MARK: Timer

    func startTimer(_ taskID: UUID) {
        apply(TimerLogic.start(taskID: taskID, entries: entries, at: Date()))
        focusedTaskID = taskID
    }

    func stopTimer() {
        apply(TimerLogic.stop(entries: entries, at: Date()))
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
        if runningEntry != nil {
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

    var isPlanningDue: Bool {
        DailyPlanning.isDue(lastPlanned: lastPlannedDay, today: today)
    }

    func isLogged(_ event: CalendarEvent) -> Bool {
        tasks.contains { $0.source == .calendar && $0.externalID == event.id }
    }

    func requestCalendarAccess() async {
        calendarAccess = await calendarProvider.requestAccess()
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
                task.sortIndex = DayPlan.nextSortIndex(in: tasks.filter { $0.plannedDate == day })
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
    func logEvent(_ event: CalendarEvent) {
        guard !isLogged(event) else { return }
        let task = TaskItem(
            title: event.showsTitle ? event.displayTitle : "Termin",
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

    /// Wochenziel für die erfasste Zeit: Tagesziel Fokuszeit mal fünf Arbeitstage.
    var weeklyGoalMinutes: Int {
        _ = settingsVersion
        let daily = UserDefaults.standard.integer(forKey: Preferences.focusGoalMinutesKey)
        return (daily > 0 ? daily : Preferences.defaultFocusGoalMinutes) * 5
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
    func move(_ id: UUID, to day: LocalDate?, before targetID: UUID?) {
        guard targetID != id, var task = self.task(id) else { return }
        guard let day else {
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
            if item.id == id || item.sortIndex != newIndex {
                item.sortIndex = newIndex
                persist(item)
            }
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
                    existingID: task.calendarEventID
                )
            } else if task.scheduledStart == nil, let eventID = task.calendarEventID {
                try calendarProvider.removeBlock(id: eventID)
                task.calendarEventID = nil
            }
        } catch {
            report(error)
        }
    }

    // MARK: PSP-Elemente

    /// Aktive PSP-Elemente eines Kunden, zuletzt genutzte zuerst.
    func psps(for customerID: UUID?, includeInactive: Bool = false) -> [PSPElement] {
        guard let customerID else { return [] }
        return pspElements
            .filter { $0.customerID == customerID && (includeInactive || $0.isActive) }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                let left = lhs.lastUsedAt ?? .distantPast
                let right = rhs.lastUsedAt ?? .distantPast
                if left != right { return left > right }
                return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending
            }
    }

    @discardableResult
    func addPSP(customerID: UUID, code rawCode: String, title: String) -> PSPElement? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        let psp = PSPElement(customerID: customerID, code: code, title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        save(psp)
        return psp
    }

    func update(_ psp: PSPElement) {
        save(psp)
    }

    func deletePSP(_ id: UUID) {
        do {
            try store.deletePSP(id: id)
            pspElements.removeAll { $0.id == id }
        } catch {
            report(error)
        }
    }

    // MARK: Abgleich mit SAP

    func sapImportPlan(_ rows: [SAPTaskRow]) -> SAPImport.Plan {
        SAPImport.plan(rows: rows, existing: pspElements, customers: customers)
    }

    /// Übernimmt den Abgleich und gibt eine kurze Zusammenfassung zurück.
    func applySAPImport(_ plan: SAPImport.Plan, choices: [String: SAPCustomerChoice], deactivateMissing: Bool) -> String {
        var created: [String: UUID] = [:]
        let knownIDs = Set(pspElements.map(\.id))
        let elements = SAPImport.apply(plan, customerFor: { group in
            switch choices[group.project] ?? .skip {
            case .skip:
                return nil
            case .existing(let id):
                return id
            case .new(let name):
                if let id = created[name] { return id }
                let customer = addCustomer(name: name)
                created[name] = customer?.id
                return customer?.id
            }
        }, deactivateMissing: deactivateMissing)
        for psp in elements {
            save(psp)
        }
        let new = elements.filter { !knownIDs.contains($0.id) }.count
        let deactivated = deactivateMissing ? plan.missing.count : 0
        let updated = elements.count - new - deactivated
        var parts: [String] = []
        if new > 0 { parts.append(new == 1 ? "1 PSP-Element neu" : "\(new) PSP-Elemente neu") }
        if updated > 0 { parts.append("\(updated) aktualisiert") }
        if deactivated > 0 { parts.append("\(deactivated) deaktiviert") }
        if !created.isEmpty { parts.append(created.count == 1 ? "1 Kunde angelegt" : "\(created.count) Kunden angelegt") }
        return parts.isEmpty ? "Alles war schon auf dem Stand." : parts.joined(separator: ", ") + "."
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

    /// Leistung in SAP zur Arbeitsart, wie in den Einstellungen hinterlegt.
    func serviceProduct(for workType: WorkType?) -> String {
        _ = settingsVersion
        guard let workType else { return "" }
        return UserDefaults.standard.string(forKey: Preferences.serviceKey(for: workType)) ?? ""
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

    /// Bucht den Tag: bereitet vor und sendet die Worklogs an ManageEngine. SAP bleibt für die Übertragung offen.
    func bookDay(_ day: LocalDate, minutes overrides: [UUID: Int]) async -> String {
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
        let openSAP = bookings.filter { $0.day == day && $0.target == .sap && !$0.status.isDone }.count
        if openSAP > 0 {
            parts.append("\(openSAP) Zeile(n) noch in SAP eintragen und abhaken.")
        }
        return parts.isEmpty ? "Alles gebucht." : parts.joined(separator: " ")
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
        for booking in due {
            guard let key = booking.ticketKey else { continue }
            let start = firstStart(of: booking.taskID, on: booking.day)
            do {
                let reference = try await manageEngine.addWorklog(
                    requestKey: key,
                    description: booking.description,
                    minutes: booking.minutes,
                    start: start
                )
                save(BookingQueue.confirmed(booking, reference: reference, now: Date()))
                sent += 1
            } catch {
                save(BookingQueue.failed(booking, error: String(describing: error), now: Date()))
                failed += 1
            }
        }
        if failed == 0 { return "\(sent) Worklog(s) an ManageEngine gesendet." }
        return "\(sent) gesendet, \(failed) fehlgeschlagen. Tagwerk versucht es später erneut."
    }

    /// Markiert die SAP-Zeile als von Hand eingetragen (legt die Buchung bei Bedarf an).
    func markEnteredInSAP(_ line: BookingLine, minutes: Int?) {
        if let existing = line.bookings[.sap] {
            save(BookingQueue.entered(existing, now: Date()))
            return
        }
        guard let prepared = DailyClose.prepare(line, minutes: minutes, now: Date()).first(where: { $0.target == .sap }) else {
            lastError = "Für SAP fehlt noch etwas: \(line.issues(for: .sap).map(\.message).joined(separator: ", "))."
            return
        }
        save(BookingQueue.entered(prepared, now: Date()))
    }

    func undoEnteredInSAP(_ line: BookingLine) {
        guard var booking = line.bookings[.sap], booking.status == .entered else { return }
        booking.status = .pending
        booking.updatedAt = Date()
        save(booking)
    }

    /// Übertragungsliste für SAP als Text (für Excel) und als Datei im Export-Ordner.
    func sapTransferList(for day: LocalDate, minutes overrides: [UUID: Int]) -> (text: String, file: URL?) {
        prepareBookings(for: day, minutes: overrides)
        let sapBookings = bookings.filter { $0.day == day && $0.target == .sap }
        let text = SAPTransfer.csv(sapBookings) { [weak self] workType in
            self?.serviceProduct(for: workType) ?? ""
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tagwerk/Exporte", isDirectory: true)
        let file = folder.appendingPathComponent("SAP-\(day.string).csv")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try text.data(using: .utf8)?.write(to: file)
            return (text, file)
        } catch {
            return (text, nil)
        }
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
            for ticket in tickets where ticket.isOpen {
                let known = tasks.contains { $0.source == .ticket && ($0.externalKey == ticket.key || $0.externalID == ticket.number) }
                guard !known else { continue }
                let task = TaskItem(
                    title: ticket.subject,
                    customerID: customerID(forAccount: ticket.accountName),
                    source: .ticket,
                    externalID: ticket.number,
                    externalURL: ticket.webURL,
                    externalKey: ticket.key
                )
                persist(task)
                added += 1
            }
            lastTicketSync = Date()
            ticketSyncMessage = added == 0 ? "Keine neuen Tickets." : "\(added) neue(s) Ticket(s) im Eingang."
        } catch {
            ticketSyncMessage = String(describing: error)
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

    func resolveIdle(_ decision: IdleDecision) {
        guard let prompt = idlePrompt else { return }
        idlePrompt = nil
        apply(TimerLogic.resolveIdle(entries: entries, idleStart: prompt.start, now: Date(), decision: decision))
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
    func addMailTask(subject: String?, from: String?, link: String?) {
        let title = (subject?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Mail ohne Betreff"
        let task = TaskItem(
            title: title,
            notes: from.map { "Von: \($0)" } ?? "",
            source: .mail,
            externalURL: link
        )
        persist(task)
        inboxMessage = "„\(title)“ liegt im Eingang."
    }

    func addLinkTask(_ url: URL) {
        let title = url.host.map { "Link: \($0)" } ?? url.absoluteString
        persist(TaskItem(title: title, externalURL: url.absoluteString))
        inboxMessage = "Link liegt im Eingang."
    }

    func addTextTask(_ text: String) {
        let firstLine = text.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return }
        addTask(title: String(firstLine.prefix(200)), customerID: nil, plannedDate: nil)
        inboxMessage = "Text liegt im Eingang."
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
            pspElements = snapshot.pspElements
            bookings = snapshot.bookings
            goals = snapshot.goals
        } catch {
            report(error)
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
        tickCount += 1
        if tickCount % 5 == 0 {
            checkIdle()
        }
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

    private func save(_ psp: PSPElement) {
        do {
            try store.save(psp)
            if let index = pspElements.firstIndex(where: { $0.id == psp.id }) {
                pspElements[index] = psp
            } else {
                pspElements.append(psp)
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
    }
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
