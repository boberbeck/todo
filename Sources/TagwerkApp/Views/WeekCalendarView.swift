import AppKit
import SwiftUI
import TagwerkCore

/// Kalender: die Woche mit Terminen, Zeitblöcken und erfasster Zeit. Doppelklick in eine freie Stelle trägt Zeit nach,
/// erfasste Einträge lassen sich ziehen und per Doppelklick bearbeiten.
struct WeekCalendarView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.calendarHourHeightKey) private var zoom = Preferences.defaultHourHeight
    @State private var weekStart: LocalDate?
    @State private var draft: TimeEntryDraft?

    private let labelWidth: CGFloat = 56

    private var hourHeight: CGFloat {
        CGFloat(min(Preferences.hourHeightRange.upperBound, max(Preferences.hourHeightRange.lowerBound, zoom)))
    }

    var body: some View {
        let monday = weekStart ?? model.currentWeekStart
        let days = (0..<7).map { monday.adding(days: $0) }
        let tracked = model.trackedInWeek(starting: monday)
        let goal = Double(max(model.weeklyGoalMinutes, 1) * 60)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 18) {
                    Text("Kalender")
                        .font(Theme.pageTitle)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 16)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(TimeMath.format(tracked))
                            .font(Theme.bigNumber)
                        Text("/ \(TimeMath.format(minutes: model.weeklyGoalMinutes)) h diese Woche")
                            .foregroundStyle(Theme.secondary)
                    }
                    .fixedSize()
                    ProgressLine(value: tracked / goal)
                        .frame(minWidth: 60, maxWidth: 160)
                }
                HStack(alignment: .center, spacing: 14) {
                    WeekSwitcher(weekStart: Binding(get: { monday }, set: { weekStart = $0 }), currentWeek: model.currentWeekStart)
                    Button {
                        draft = TimeEntryDraft(start: defaultStart(in: days), minutes: 60)
                    } label: {
                        Label("Zeit nachtragen", systemImage: "plus")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .help("Arbeit nachträglich erfassen (oder Doppelklick in eine freie Stelle im Kalender und gleich beschriften)")
                    Spacer(minLength: 16)
                    HStack(spacing: 6) {
                        Button {
                            zoom = max(Preferences.hourHeightRange.lowerBound, zoom - 16)
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        .help("Stunden niedriger")
                        Button {
                            zoom = min(Preferences.hourHeightRange.upperBound, zoom + 16)
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        .help("Stunden höher")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 24)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: labelWidth)
                    ForEach(days, id: \.self) { day in
                        dayHeader(day)
                    }
                }
                .frame(height: 64)
                Rectangle().fill(Theme.border).frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView {
                        HStack(alignment: .top, spacing: 0) {
                            hourLabels
                            ForEach(days, id: \.self) { day in
                                DayTimeline(day: day, hourHeight: hourHeight) { newDraft in
                                    draft = newDraft
                                }
                            }
                        }
                        .frame(height: 24 * hourHeight)
                        .padding(.vertical, 10)
                    }
                    .onAppear {
                        proxy.scrollTo(max(0, model.workday.startMinutes / 60 - 1), anchor: .top)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .sheet(item: $draft) { draft in
            AddTimeSheet(draft: draft)
                .tagwerkSheet()
        }
    }

    private func dayHeader(_ day: LocalDate) -> some View {
        let isToday = day == model.today
        return VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(day.startDate().formatted(.dateTime.weekday(.abbreviated)))
                    .foregroundStyle(isToday ? Theme.text : Theme.secondary)
                Text("\(day.day)")
                    .foregroundStyle(isToday ? Theme.accent : Theme.tertiary)
            }
            .font(.system(size: 15, weight: .medium))
            Text("\(TimeMath.format(model.tracked(on: day))) h")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isToday ? Theme.todayTint : Color.clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.border).frame(width: 1)
        }
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%d:00", hour))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .frame(width: labelWidth - 10, alignment: .trailing)
                    .frame(height: hourHeight, alignment: .top)
                    .offset(y: -7)
                    .id(hour)
            }
        }
        .frame(width: labelWidth, alignment: .leading)
    }

    private func defaultStart(in days: [LocalDate]) -> Date {
        if days.contains(model.today) {
            let minutes = FreeTime.minutesSinceMidnight(Date()) - 60
            return FreeTime.snapNearest(FreeTime.date(on: model.today, minutes: max(0, minutes)), stepMinutes: 15)
        }
        return FreeTime.date(on: days[0], minutes: model.workday.startMinutes)
    }
}

/// Ein Tag im Wochenkalender. Doppelklick in eine freie Stelle legt dort eine neue Aufgabe an.
struct DayTimeline: View {
    @Environment(AppModel.self) private var model
    let day: LocalDate
    let hourHeight: CGFloat
    /// „…“ im neuen Eintrag: öffnet „Zeit nachtragen“ mit allen Feldern
    let onMore: (TimeEntryDraft) -> Void

    var body: some View {
        let isToday = day == model.today
        let dayStart = day.startDate()
        let height = hourHeight
        let y: (Date) -> CGFloat = { date in
            CGFloat(date.timeIntervalSince(dayStart) / 3600) * height
        }
        let total = 24 * hourHeight

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(isToday ? Theme.todayTint : Color.clear)

            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                        .frame(height: hourHeight, alignment: .top)
                }
            }

            ForEach(model.calendarEvents(on: day).filter { !$0.isAllDay }) { event in
                let top = max(0, y(event.start))
                EventBlock(event: event, height: max(16, min(total, y(event.end)) - top), logged: model.isLogged(event))
                    .padding(.horizontal, 3)
                    .offset(y: top)
            }

            ForEach(model.scheduledTasks(on: day)) { task in
                if let interval = task.scheduledInterval {
                    TaskBlock(
                        task: task,
                        top: y(interval.start),
                        height: max(18, y(interval.end) - y(interval.start)),
                        hourHeight: hourHeight
                    )
                    .padding(.leading, 10)
                    .padding(.trailing, 3)
                }
            }

            ForEach(model.dayEntries(day)) { entry in
                EntryBlock(entry: entry, dayStart: dayStart, hourHeight: hourHeight, dayHeight: total)
                    .padding(.leading, 18)
                    .padding(.trailing, 3)
            }

            if isToday {
                let nowY = y(model.now)
                HStack(spacing: 0) {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    Rectangle().fill(Theme.accent).frame(height: 1.5)
                }
                .offset(x: -3.5, y: nowY - 3.5)
                .allowsHitTesting(false)
            }

            if let slot = model.calendarNewSlot, LocalDate(slot.start) == day {
                NewCalendarItem(
                    slot: slot,
                    top: max(0, y(slot.start)),
                    height: y(slot.end) - y(slot.start),
                    commit: { title in
                        model.addTaskFromCalendar(title: title, slot: slot)
                        model.closeCalendarSlot(slot)
                    },
                    cancel: { model.closeCalendarSlot(slot) },
                    more: { title in
                        model.closeCalendarSlot(slot)
                        onMore(TimeEntryDraft(start: slot.start, minutes: max(5, Int(slot.duration / 60)), title: title))
                    }
                )
                .id(slot.start)
                .padding(.leading, 4)
                .padding(.trailing, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: total, alignment: .top)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.border).frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, coordinateSpace: .local) { location in
            let click = dayStart.addingTimeInterval(max(0, Double(location.y / height)) * 3600)
            model.calendarNewSlot = model.proposedSlot(near: click)
        }
        .dropDestination(for: String.self) { items, location in
            let minutes = Double(location.y / height) * 60
            let start = dayStart.addingTimeInterval(minutes * 60)
            let ids = items.compactMap { UUID(uuidString: $0) }
            for id in ids { model.schedule(id, at: start) }
            return !ids.isEmpty
        }
    }
}

/// Erfasste Zeit als Block in der Farbe des Kunden. Ziehen verschiebt den Eintrag, die obere und untere Kante
/// ändern Beginn und Ende (auf fünf Minuten gerastet, ohne andere Einträge zu überlappen), Doppelklick öffnet „Zeit bearbeiten“.
struct EntryBlock: View {
    @Environment(AppModel.self) private var model
    let entry: TimeEntry
    let dayStart: Date
    let hourHeight: CGFloat
    let dayHeight: CGFloat

    @State private var drag: EntryDrag?
    @State private var delta: TimeInterval = 0
    @State private var neighbours: [TimeEntry] = []
    @State private var cursorPushed = false

    private var isRunning: Bool { entry.end == nil }

    /// Zeiten, wie sie gerade aussehen (während des Ziehens die neuen).
    private var shown: (start: Date, end: Date?) {
        guard let drag else { return (entry.start, entry.end) }
        return EntryEditing.dragged(entry, drag, by: delta, others: neighbours, now: model.now)
    }

    private func y(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 3600) * hourHeight
    }

    var body: some View {
        let times = shown
        let top = max(0, y(times.start))
        let bottom = min(dayHeight, y(times.end ?? model.now))
        let height = max(4, bottom - top)
        let task = model.task(entry.taskID)
        let color = model.customer(task?.customerID).map { CustomerPalette.color($0.colorIndex) } ?? Theme.accent
        let handleHeight = min(7, height / 4)

        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            if height > 18 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task?.title ?? "Ohne Aufgabe")
                        .font(.caption.weight(.semibold))
                        .lineLimit(height > 40 ? 2 : 1)
                    if height > 34 {
                        Text(timeRange(times))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(drag == nil ? 0.22 : 0.4)))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color, lineWidth: drag == nil ? 0 : 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        // Kanten zum Ziehen: oben der Beginn, unten das Ende (beim laufenden Timer nur der Beginn)
        .overlay(alignment: .top) {
            edgeHandle(.start, height: handleHeight)
        }
        .overlay(alignment: .bottom) {
            if !isRunning {
                edgeHandle(.end, height: handleHeight)
            }
        }
        .overlay(alignment: .topLeading) {
            if drag != nil {
                Text(badge(times))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(color))
                    .fixedSize()
                    .offset(y: -20)
                    .allowsHitTesting(false)
            }
        }
        .offset(y: top)
        .gesture(dragGesture(.move), including: isRunning ? .subviews : .all)
        .onTapGesture(count: 2) {
            model.editingEntry = entry
        }
        .help("\(task?.title ?? "Erfasst") · \(timeRange(times))\nZiehen verschiebt, die Kanten ändern Beginn und Ende, Doppelklick bearbeitet")
        .contextMenu {
            Button("Zeit bearbeiten …") { model.editingEntry = entry }
            if let task {
                Button("Aufgabe öffnen …") { model.openDetail(task.id) }
                Button("Im Fokus öffnen") { model.openFocus(task.id) }
            }
            Divider()
            Button("Eintrag löschen", role: .destructive) { model.deleteEntry(entry.id) }
                .disabled(isRunning)
        }
    }

    private func edgeHandle(_ kind: EntryDrag, height: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside, !cursorPushed {
                    NSCursor.resizeUpDown.push()
                    cursorPushed = true
                } else if !inside, cursorPushed, drag == nil {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .gesture(dragGesture(kind))
    }

    /// Fenster-Koordinaten, damit das Mitwandern des Blocks die Bewegung nicht verfälscht.
    private func dragGesture(_ kind: EntryDrag) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if drag == nil {
                    neighbours = model.entriesAround(entry)
                    drag = kind
                }
                delta = Double(value.translation.height / hourHeight) * 3600
            }
            .onEnded { value in
                let moved = Double(value.translation.height / hourHeight) * 3600
                let result = EntryEditing.dragged(entry, kind, by: moved, others: neighbours, now: model.now)
                drag = nil
                delta = 0
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
                model.updateEntry(entry.id, start: result.start, end: result.end)
            }
    }

    private func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func timeRange(_ times: (start: Date, end: Date?)) -> String {
        "\(clock(times.start))–\(times.end.map { clock($0) } ?? "läuft")"
    }

    private func badge(_ times: (start: Date, end: Date?)) -> String {
        let minutes = Int(((times.end ?? model.now).timeIntervalSince(times.start) / 60).rounded())
        return "\(timeRange(times)) · \(TimeMath.format(minutes: minutes)) h"
    }
}

struct TimeEntryDraft: Identifiable {
    let id = UUID()
    var start: Date
    var minutes: Int
    /// Aufgabe, für die nachgetragen wird; sonst wählt man im Fenster.
    var taskID: UUID? = nil
    /// Titel einer neuen Aufgabe (z. B. schon im Kalender eingetippt)
    var title: String = ""
}

/// Zeit nachträglich erfassen: Aufgabe wählen oder neu anlegen, Tag und Uhrzeit.
struct AddTimeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let draft: TimeEntryDraft

    @State private var taskID: UUID?
    @State private var newTitle = ""
    @State private var customerID: UUID?
    @State private var day = Date()
    @State private var from = Date()
    @State private var to = Date()

    var body: some View {
        let start = combined(day, from)
        let end = combined(day, to)
        let minutes = Int(end.timeIntervalSince(start) / 60)

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Zeit nachtragen")
                    .font(.title2.weight(.semibold))
                Text("Vergessen, den Timer zu starten? Hier die Zeit eintragen; sie zählt wie gestoppte Zeit.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("Aufgabe", selection: $taskID) {
                    Text("Neue Aufgabe …").tag(UUID?.none)
                    Divider()
                    ForEach(candidates) { task in
                        Text(label(for: task)).tag(UUID?.some(task.id))
                    }
                }
                if taskID == nil {
                    TextField("Titel", text: $newTitle, prompt: Text("Was hast du gemacht?"))
                    Picker("Kunde", selection: $customerID) {
                        Text("Ohne Kunde").tag(UUID?.none)
                        ForEach(model.activeCustomers) { customer in
                            Text(customer.name).tag(UUID?.some(customer.id))
                        }
                    }
                }
                DatePicker("Tag", selection: $day, displayedComponents: .date)
                DatePicker("Von", selection: $from, displayedComponents: .hourAndMinute)
                DatePicker("Bis", selection: $to, displayedComponents: .hourAndMinute)
                LabeledContent("Bis jetzt") {
                    HStack(spacing: 6) {
                        ForEach([15, 30, 60, 90], id: \.self) { minutes in
                            Button(minutes < 60 ? "\(minutes) Min" : "\(TimeMath.format(minutes: minutes)) h") {
                                untilNow(minutes: minutes)
                            }
                        }
                        if let last = model.lastEntryEndToday, Date().timeIntervalSince(last) >= 60 {
                            Button("seit \(last.formatted(date: .omitted, time: .shortened))") {
                                day = Date()
                                from = last
                                to = Date()
                            }
                            .help("Vom Ende des letzten Eintrags bis jetzt")
                        }
                    }
                    .controlSize(.small)
                }
                LabeledContent("Dauer") {
                    Text(minutes > 0 ? "\(TimeMath.format(minutes: minutes)) h" : "Ende liegt vor dem Beginn")
                        .foregroundStyle(minutes > 0 ? Theme.text : Theme.accent)
                        .monospacedDigit()
                }
            }
            .tagwerkForm()

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Erfassen") { save(start: start, end: end) }
                    .buttonStyle(GhostButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(minutes <= 0 || (taskID == nil && newTitle.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            day = draft.start
            from = draft.start
            to = draft.start.addingTimeInterval(TimeInterval(draft.minutes * 60))
            let sameDay = LocalDate(draft.start)
            if !draft.title.isEmpty, draft.taskID == nil {
                // Im Kalender schon beschriftet: neue Aufgabe mit diesem Titel
                taskID = nil
                newTitle = draft.title
            } else {
                taskID = draft.taskID ?? model.dayTasks(sameDay).first { !$0.isDone }?.id ?? model.todayTasks.first?.id
            }
        }
    }

    private func untilNow(minutes: Int) {
        let now = Date()
        day = now
        to = now
        from = now.addingTimeInterval(TimeInterval(-minutes * 60))
    }

    /// Aufgaben des Tages, von heute und offene, ohne Doppelte.
    private var candidates: [TaskItem] {
        let chosen = model.task(draft.taskID).map { [$0] } ?? []
        let sameDay = model.dayTasks(LocalDate(day))
        let open = model.tasks.filter { !$0.isDone }.sorted { $0.createdAt > $1.createdAt }
        var seen = Set<UUID>()
        return (chosen + sameDay + model.todayTasks + open).filter { seen.insert($0.id).inserted }.prefix(60).map { $0 }
    }

    private func label(for task: TaskItem) -> String {
        let title = model.parent(of: task).map { "\($0.title) › \(task.title)" } ?? task.title
        if let customer = model.customer(task.customerID) {
            return "\(title) · \(customer.name)"
        }
        return title
    }

    private func combined(_ day: Date, _ time: Date) -> Date {
        FreeTime.date(on: LocalDate(day), minutes: FreeTime.minutesSinceMidnight(time))
    }

    private func save(start: Date, end: Date) {
        var target = taskID
        if target == nil {
            target = model.addTask(title: newTitle, customerID: customerID, plannedDate: LocalDate(day))?.id
        }
        guard let target else { return }
        model.addEntry(taskID: target, start: start, end: end)
        dismiss()
    }
}
