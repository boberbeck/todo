import AppKit
import SwiftUI
import TagwerkCore

/// Zeitleiste des Tages: Termine, Zeitblöcke der Aufgaben, erfasste Zeit und die aktuelle Uhrzeit.
struct CalendarColumn: View {
    @Environment(AppModel.self) private var model

    @AppStorage(Preferences.calendarHourHeightKey) private var zoom = Preferences.defaultHourHeight
    private let labelWidth: CGFloat = 40

    /// Höhe einer Stunde; über die Lupen im Kopf einstellbar.
    private var hourHeight: CGFloat {
        CGFloat(min(Preferences.hourHeightRange.upperBound, max(Preferences.hourHeightRange.lowerBound, zoom)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kalender")
                        .font(.system(size: 14, weight: .medium))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    Button {
                        zoom = max(Preferences.hourHeightRange.lowerBound, zoom - 16)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(zoom <= Preferences.hourHeightRange.lowerBound)
                    .help("Stunden niedriger")
                    Button {
                        zoom = min(Preferences.hourHeightRange.upperBound, zoom + 16)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(zoom >= Preferences.hourHeightRange.upperBound)
                    .help("Stunden höher")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            accessHint

            if !model.allDayEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.allDayEvents) { event in
                        Text(event.displayTitle)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    timeline
                }
                .onAppear {
                    proxy.scrollTo(scrollAnchorHour, anchor: .top)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var subtitle: String {
        switch model.calendarAccess {
        case .granted: return ""
        case .notDetermined: return "Noch nicht verbunden"
        case .denied: return "Kein Zugriff"
        case .unavailable: return "Nur in Tagwerk.app"
        }
    }

    @ViewBuilder
    private var accessHint: some View {
        switch model.calendarAccess {
        case .granted:
            EmptyView()
        case .notDetermined:
            Button("Kalender verbinden") {
                Task { await model.requestCalendarAccess() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Erlaube den Zugriff in den Systemeinstellungen unter Datenschutz & Sicherheit › Kalender.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Systemeinstellungen öffnen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        case .unavailable:
            Text("Starte Tagwerk als App (scripts/make-app.sh), damit es nach dem Kalender fragen darf.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private var firstHour: Int { max(0, model.workday.startMinutes / 60 - 1) }

    private var lastHour: Int { max(firstHour + 1, min(24, (model.workday.endMinutes + 59) / 60 + 1)) }

    private var scrollAnchorHour: Int {
        let current = FreeTime.minutesSinceMidnight(Date()) / 60 - 2
        return max(firstHour, min(lastHour - 1, current))
    }

    private var timeline: some View {
        let dayStart = model.today.startDate()
        let first = firstHour
        let total = CGFloat(lastHour - firstHour) * hourHeight
        let height = hourHeight
        func y(_ date: Date) -> CGFloat {
            CGFloat((date.timeIntervalSince(dayStart) / 60 - Double(first * 60)) / 60) * height
        }
        let nowY = y(model.now)
        let work = model.workdayInterval

        return ZStack(alignment: .topLeading) {
            // Stundenraster; jede Stunde ist eine eigene Zeile, damit das Scrollen zur Uhrzeit klappt.
            VStack(spacing: 0) {
                ForEach(firstHour..<lastHour, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(hour):00")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth - 6, alignment: .trailing)
                            .offset(y: -6)
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                    }
                    .frame(height: hourHeight, alignment: .top)
                    .id(hour)
                }
            }

            // Arbeitszeit leicht hinterlegt
            Rectangle()
                .fill(Theme.todayTint)
                .frame(height: max(0, y(work.end) - y(work.start)))
                .padding(.leading, labelWidth)
                .offset(y: y(work.start))
                .allowsHitTesting(false)

            ForEach(model.timedEvents) { event in
                let top = max(0, y(event.start))
                EventBlock(event: event, height: max(16, y(event.end) - top), logged: model.isLogged(event))
                    .padding(.leading, labelWidth + 2)
                    .padding(.trailing, 8)
                    .offset(y: top)
            }

            ForEach(model.breaks(on: model.today)) { item in
                let top = max(0, y(item.start))
                BreakBlock(item: item, height: y(item.end ?? model.now) - top)
                    .padding(.leading, labelWidth + 2)
                    .padding(.trailing, 8)
                    .offset(y: top)
            }

            ForEach(model.entriesToday) { entry in
                let top = max(0, y(entry.start))
                RoundedRectangle(cornerRadius: 2)
                    .fill(entryColor(entry))
                    .frame(width: 4, height: max(3, y(entry.end ?? model.now) - top))
                    // breiter treffbar als sichtbar
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .padding(.leading, labelWidth - 7)
                    .offset(y: top)
                    .onTapGesture(count: 2) { model.editingEntry = entry }
                    .contextMenu {
                        Button("Zeit bearbeiten …") { model.editingEntry = entry }
                        Button("Eintrag löschen", role: .destructive) { model.deleteEntry(entry.id) }
                            .disabled(entry.end == nil)
                    }
                    .help("Erfasst \(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end?.formatted(date: .omitted, time: .shortened) ?? "läuft") · Doppelklick bearbeitet")
            }

            ForEach(model.scheduledToday) { task in
                if let interval = task.scheduledInterval {
                    TaskBlock(
                        task: task,
                        top: y(interval.start),
                        height: max(18, y(interval.end) - y(interval.start)),
                        hourHeight: hourHeight
                    )
                    .padding(.leading, labelWidth + 16)
                    .padding(.trailing, 4)
                }
            }

            if nowY >= 0 && nowY <= total {
                // Sonnenstand auf der Jetzt-Linie
                HStack(alignment: .bottom, spacing: 0) {
                    SunMark(size: 10)
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(height: 1.5)
                }
                .padding(.leading, labelWidth - 5)
                .offset(y: nowY - 5)
                .allowsHitTesting(false)
            }

            if let slot = model.calendarNewSlot, LocalDate(slot.start) == model.today {
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
                        model.timeEntryDraft = TimeEntryDraft(start: slot.start, minutes: max(5, Int(slot.duration / 60)), title: title)
                    }
                )
                .id(slot.start)
                .padding(.leading, labelWidth + 2)
                .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: total, maxHeight: total, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, coordinateSpace: .local) { location in
            let minutes = Double(location.y / height) * 60 + Double(first * 60)
            model.calendarNewSlot = model.proposedSlot(near: dayStart.addingTimeInterval(max(0, minutes) * 60))
        }
        .dropDestination(for: String.self) { items, location in
            let minutes = Double(location.y / height) * 60 + Double(first * 60)
            let start = dayStart.addingTimeInterval(minutes * 60)
            let ids = items.compactMap { UUID(uuidString: $0) }
            for id in ids {
                model.schedule(id, at: start)
            }
            return !ids.isEmpty
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

extension CalendarColumn {
    /// Erfasste Zeit in der Farbe des Kunden (wie im Tagesband).
    func entryColor(_ entry: TimeEntry) -> Color {
        let customerID = model.task(entry.taskID).map { model.resolved($0) }?.customerID
        return model.customer(customerID).map { CustomerPalette.color($0.colorIndex) } ?? Theme.secondary
    }
}

struct EventBlock: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent
    let height: CGFloat
    let logged: Bool
    @State private var showsLogSheet = false

    var body: some View {
        // Als Aufgabe erfasst: statt des Termins steht die Aufgabe da (Titel und Kunde der Aufgabe)
        let task = logged ? model.loggedTask(for: event) : nil
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if let customer = model.customer(task?.customerID) {
                    CustomerDot(colorIndex: customer.colorIndex, size: 6)
                }
                Text(task?.title ?? event.displayTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if logged {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(Theme.done)
                }
            }
            if height > 30 {
                Text(timeRange)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(event.showsTitle ? 0.07 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(0.15))
        )
        .contextMenu {
            Button("Meeting & Transkript …") { model.openMeeting(event) }
            if let task {
                Button("Aufgabe öffnen …") { model.openDetail(task.id) }
            } else {
                Button(logged ? "Schon als Zeit erfasst" : "Als Zeit erfassen …") {
                    showsLogSheet = true
                }
                .disabled(logged)
            }
        }
        // Doppelklick: Meeting-Fenster (Transkript, Aufgaben daraus, Claude Code, Zeit erfassen)
        .onTapGesture(count: 2) {
            model.openMeeting(event)
        }
        .sheet(isPresented: $showsLogSheet) {
            LogEventSheet(event: event)
                .tagwerkSheet()
        }
        .help("\(event.displayTitle) · \(timeRange)\(model.meetings.contains { $0.eventID == event.id && $0.hasTranscript } ? " · Transkript abgelegt" : "")\nDoppelklick: Meeting mit Transkript")
    }

    private var timeRange: String {
        "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Zeitblock einer Aufgabe. Lässt sich mit der Maus verschieben.
struct TaskBlock: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    let top: CGFloat
    let height: CGFloat
    let hourHeight: CGFloat

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let running = model.isRunning(task.id)
        VStack(alignment: .leading, spacing: 1) {
            Text(task.title)
                .font(.caption.weight(.medium))
                .lineLimit(height > 34 ? 2 : 1)
            if height > 30, let start = task.scheduledStart {
                Text(start.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height, alignment: .topLeading)
        // Geplant: neutraler Umriss; läuft die Aufgabe, eine orangene Kante (wie auf der Karte)
        .background(
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.surfaceRaised.opacity(0.6))
                if running {
                    Rectangle().fill(Theme.accent).frame(width: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.borderStrong, style: StrokeStyle(lineWidth: 1, dash: task.isDone ? [] : [4, 3]))
        )
        .opacity(task.isDone ? 0.55 : 1)
        .offset(y: top + dragOffset)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let minutes = Double(value.translation.height / hourHeight) * 60
                    dragOffset = 0
                    model.moveBlock(task.id, byMinutes: minutes)
                }
        )
        .onTapGesture(count: 2) {
            model.openFocus(task.id)
        }
        .contextMenu {
            Button("Öffnen …") { model.openDetail(task.id) }
            Button("Im Fokus öffnen") { model.openFocus(task.id) }
            Button("Zeitblock entfernen") { model.schedule(task.id, at: nil) }
        }
        .help("Ziehen verschiebt den Block, Doppelklick öffnet den Fokus")
    }
}

/// Termin als Zeit erfassen: Titel und Kunde; Tagwerk merkt sich den Kunden je Termintitel.
struct LogEventSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEvent

    @State private var title = ""
    @State private var customerID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Termin als Zeit erfassen")
                    .font(.title2.weight(.medium))
                Text("\(event.start.formatted(date: .abbreviated, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened)) · \(TimeMath.format(minutes: event.minutes)) h")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Form {
                TextField("Titel", text: $title)
                Picker("Kunde", selection: $customerID) {
                    Text("Ohne Kunde").tag(UUID?.none)
                    ForEach(model.activeCustomers) { customer in
                        Text(customer.name).tag(UUID?.some(customer.id))
                    }
                }
            }
            .tagwerkForm()
            Text("Tagwerk merkt sich den Kunden für Termine mit demselben Titel.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Erfassen") {
                    model.logEvent(event, title: title, assignment: .init(customerID: customerID))
                    dismiss()
                }
                .buttonStyle(GhostButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            title = event.showsTitle ? event.displayTitle : "Termin"
            customerID = model.eventAssignment(for: event)?.customerID
        }
    }
}
