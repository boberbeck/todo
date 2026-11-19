import Foundation
import Observation
import TagwerkCore

enum SidebarItem: Hashable {
    case today
    case focus
    case customers
    case review
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

    private let store: Store
    @ObservationIgnored private var ticker: Timer?

    init(store: Store) {
        self.store = store
        reload()
        rollOverOpenTasks()
        startTicker()
    }

    static func live() -> AppModel {
        if SnapshotMode.usesDemoData {
            return AppModel(store: InMemoryStore(DemoData.snapshot()))
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tagwerk", isDirectory: true)
        let url = folder.appendingPathComponent("tagwerk.sqlite")
        do {
            return AppModel(store: try SQLiteStore(url: url))
        } catch {
            let model = AppModel(store: InMemoryStore())
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
        persist(task)
    }

    func moveTodayTasks(from source: IndexSet, to destination: Int) {
        for task in DayPlan.reorder(todayTasks, from: source, to: destination) {
            persist(task)
        }
    }

    func delete(_ id: UUID) {
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
        for task in DayPlan.rollOver(tasks, to: today) {
            persist(task)
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
            rollOverOpenTasks()
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
