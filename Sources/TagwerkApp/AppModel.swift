import Foundation
import Observation
import TagwerkCore

enum SidebarItem: Hashable {
    case today
    case focus
    case customers
    case review
    case planning
    case customer(UUID)
}

/// Zentraler Zustand der App. Hält alle Daten im Speicher und schreibt jede Änderung sofort in die Datenbank.
@MainActor
@Observable
final class AppModel {
    private(set) var customers: [Customer] = []
    private(set) var tasks: [TaskItem] = []
    private(set) var entries: [TimeEntry] = []

    var selection: SidebarItem? = .today
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
    @ObservationIgnored private var ticker: Timer?

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
        events = calendarProvider.events(on: today, modes: calendarModes)
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
        } catch {
            report(error)
        }
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
