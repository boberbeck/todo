import SwiftUI
import TagwerkCore

/// Kalender: die Woche mit Terminen, Zeitblöcken und erfasster Zeit. Doppelklick trägt Zeit nach.
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
            HStack(alignment: .center, spacing: 18) {
                Text("Kalender")
                    .font(Theme.pageTitle)
                WeekSwitcher(weekStart: Binding(get: { monday }, set: { weekStart = $0 }), currentWeek: model.currentWeekStart)
                Button {
                    draft = TimeEntryDraft(start: defaultStart(in: days), minutes: 60)
                } label: {
                    Label("Zeit nachtragen", systemImage: "plus")
                }
                .buttonStyle(GhostButtonStyle())
                .help("Arbeit nachträglich erfassen (oder Doppelklick in den Kalender)")
                Spacer(minLength: 16)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(TimeMath.format(tracked))
                        .font(Theme.bigNumber)
                    Text("/ \(TimeMath.format(minutes: model.weeklyGoalMinutes)) h")
                        .foregroundStyle(Theme.secondary)
                }
                ProgressLine(value: tracked / goal)
                    .frame(width: 160)
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
                                DayTimeline(day: day, hourHeight: hourHeight) { start in
                                    draft = TimeEntryDraft(start: start, minutes: 60)
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

/// Ein Tag im Wochenkalender.
struct DayTimeline: View {
    @Environment(AppModel.self) private var model
    let day: LocalDate
    let hourHeight: CGFloat
    let onCreate: (Date) -> Void

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
                let top = max(0, y(entry.start))
                let bottom = min(total, y(entry.end ?? model.now))
                EntryBlock(entry: entry, height: max(4, bottom - top))
                    .padding(.leading, 18)
                    .padding(.trailing, 3)
                    .offset(y: top)
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: total, alignment: .top)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.border).frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, coordinateSpace: .local) { location in
            let minutes = Double(location.y / height) * 60
            let start = FreeTime.snapNearest(dayStart.addingTimeInterval(max(0, minutes - 30) * 60), stepMinutes: 15)
            onCreate(start)
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

/// Erfasste Zeit als Block in der Farbe des Kunden.
struct EntryBlock: View {
    @Environment(AppModel.self) private var model
    let entry: TimeEntry
    let height: CGFloat

    var body: some View {
        let task = model.task(entry.taskID)
        let color = model.customer(task?.customerID).map { CustomerPalette.color($0.colorIndex) } ?? Theme.accent
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            if height > 18 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task?.title ?? "Ohne Aufgabe")
                        .font(.caption.weight(.semibold))
                        .lineLimit(height > 40 ? 2 : 1)
                    if height > 34 {
                        Text(timeRange)
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
        .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.22)))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help("\(task?.title ?? "Erfasst") · \(timeRange)")
        .contextMenu {
            if let task {
                Button("Im Fokus öffnen") { model.openFocus(task.id) }
            }
            Button("Eintrag löschen", role: .destructive) { model.deleteEntry(entry.id) }
                .disabled(entry.end == nil)
        }
    }

    private var timeRange: String {
        let end = entry.end.map { $0.formatted(date: .omitted, time: .shortened) } ?? "läuft"
        return "\(entry.start.formatted(date: .omitted, time: .shortened))–\(end)"
    }
}

struct TimeEntryDraft: Identifiable {
    let id = UUID()
    var start: Date
    var minutes: Int
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
            Text("Zeit nachtragen")
                .font(.title2.weight(.semibold))

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
                LabeledContent("Dauer") {
                    Text(minutes > 0 ? "\(TimeMath.format(minutes: minutes)) h" : "Ende liegt vor dem Beginn")
                        .foregroundStyle(minutes > 0 ? Theme.text : Theme.accent)
                        .monospacedDigit()
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Erfassen") { save(start: start, end: end) }
                    .buttonStyle(.borderedProminent)
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
            taskID = model.dayTasks(sameDay).first { !$0.isDone }?.id ?? model.todayTasks.first?.id
        }
    }

    /// Aufgaben des Tages, von heute und offene, ohne Doppelte.
    private var candidates: [TaskItem] {
        let sameDay = model.dayTasks(LocalDate(day))
        let open = model.tasks.filter { !$0.isDone }.sorted { $0.createdAt > $1.createdAt }
        var seen = Set<UUID>()
        return (sameDay + model.todayTasks + open).filter { seen.insert($0.id).inserted }.prefix(60).map { $0 }
    }

    private func label(for task: TaskItem) -> String {
        if let customer = model.customer(task.customerID) {
            return "\(task.title) · \(customer.name)"
        }
        return task.title
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
