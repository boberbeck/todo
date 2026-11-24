import AppKit
import SwiftUI
import TagwerkCore

/// Start: der heutige Tag. Links die Aufgaben, Erledigtes und der Eingang, rechts der Kalender.
struct StartView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.calendarWidthKey) private var calendarWidth = Preferences.defaultCalendarWidth
    @AppStorage(Preferences.focusGoalMinutesKey) private var focusGoalMinutes = Preferences.defaultFocusGoalMinutes

    private let taskColumnMinWidth: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let absence = model.absence(on: model.today) {
                    AbsenceBanner(absence: absence)
                }
                DayBand()
                StandingTaskStrip()
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 24)

            GeometryReader { geometry in
                let maxCalendar = max(Preferences.minCalendarWidth, Double(geometry.size.width - taskColumnMinWidth - 60))
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        StartTaskColumn()
                            .padding(.leading, 40)
                            .padding(.trailing, 24)
                            .padding(.bottom, 32)
                    }
                    .frame(minWidth: taskColumnMinWidth, maxWidth: .infinity)

                    ResizeHandle(
                        width: $calendarWidth,
                        range: Preferences.minCalendarWidth...max(Preferences.minCalendarWidth, min(Preferences.maxCalendarWidth, maxCalendar)),
                        defaultValue: Preferences.defaultCalendarWidth,
                        showsLine: false
                    )

                    CalendarColumn()
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .frame(width: CGFloat(min(calendarWidth, maxCalendar)))
                        .padding(.trailing, 32)
                        .padding(.bottom, 28)
                }
            }
        }
    }

    private var header: some View {
        let running = model.runningEntry != nil
        let tracked = model.trackedToday(now: running ? model.now : Date())
        let week = model.trackedInWeek(starting: model.currentWeekStart)
        let goal = Double(max(focusGoalMinutes, 1) * 60)
        return HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.today.startDate().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Theme.pageTitle)
                    .lineLimit(1)
                Text(daySummary)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(TimeMath.format(tracked))
                    .font(Theme.bigNumber)
                Text("h heute")
                    .foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                ProgressLine(value: tracked / goal)
                    .frame(width: 180)
                Text("\(TimeMath.format(week)) h diese Woche · Ziel \(TimeMath.format(minutes: focusGoalMinutes)) h am Tag")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var daySummary: String {
        let open = model.todayTasks.filter { !$0.isDone }.count
        let events = model.timedEvents.count
        var parts = [open == 1 ? "1 Aufgabe offen" : "\(open) Aufgaben offen"]
        if events > 0 { parts.append(events == 1 ? "1 Termin" : "\(events) Termine") }
        if let running = model.runningTask { parts.append("läuft: \(running.title)") }
        if let pause = model.runningBreak {
            parts.append("Pause seit \(pause.start.formatted(date: .omitted, time: .shortened))")
        } else {
            let pauses = model.breakTotal(on: model.today)
            if pauses >= 60 { parts.append("\(TimeMath.format(pauses)) h Pause") }
        }
        return parts.joined(separator: " · ")
    }
}

/// Linke Spalte auf Start: Heute, Erledigt, Eingang.
struct StartTaskColumn: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.showInboxKey) private var showInbox = true
    @State private var isInboxDropTarget = false

    var body: some View {
        let open = model.todayTasks.filter { !$0.isDone }
        let done = model.doneToday
        let planned = DayPlan.plannedMinutes(open)
        let free = model.freeMinutesToday
        let overplanned = DayPlan.isOverplanned(plannedMinutes: planned, availableMinutes: free)

        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    SectionLabel(text: "Heute", detail: "\(TimeMath.format(minutes: planned)) h geplant · \(TimeMath.format(minutes: free)) h frei")
                        .fixedSize()
                        .layoutPriority(1)
                    if overplanned {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                            .help("Mehr geplant, als zwischen den Terminen Zeit ist")
                    }
                    Spacer(minLength: 8)
                    // Wird die Spalte schmal, bleiben nur die Symbole (mit Hinweis beim Darüberfahren)
                    ViewThatFits(in: .horizontal) {
                        DayActions(compact: false)
                        DayActions(compact: true)
                    }
                }
                AddTaskField(day: model.today, takesNewTaskShortcut: true)
                if open.isEmpty {
                    Text(done.isEmpty
                         ? "Noch nichts geplant. Leg oben eine Aufgabe an oder hol eine aus dem Eingang."
                         : "Alles für heute erledigt. Stark.")
                        .foregroundStyle(Theme.tertiary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(open) { task in
                            TaskCard(task: task, dropDay: model.today)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                let ids = items.compactMap { UUID(uuidString: $0) }
                for id in ids { model.move(id, to: model.today, before: nil) }
                return !ids.isEmpty
            }

            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Erledigt", detail: "\(done.count)")
                    VStack(spacing: 6) {
                        ForEach(done) { task in
                            DoneRow(task: task)
                        }
                    }
                }
            }

            GoalStrip()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showInbox.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showInbox ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.tertiary)
                            SectionLabel(text: "Eingang", detail: "\(model.inboxTasks.count)")
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    if let message = model.inboxMessage ?? model.ticketSyncMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(1)
                            .help(model.ticketSyncDetail ?? message)
                    }
                    if model.canUseManageEngine {
                        Button {
                            Task { await model.importTickets() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.secondary)
                        .disabled(model.isSyncingTickets)
                        .help("Tickets aus ManageEngine abrufen")
                    }
                }
                if showInbox {
                    if model.inboxTasks.isEmpty {
                        Text("Leer. Zieh Mails aus Outlook hierher; Tickets aus ManageEngine landen automatisch hier.")
                            .font(.callout)
                            .foregroundStyle(Theme.tertiary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(model.inboxTasks) { task in
                                InboxRow(task: task)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(isInboxDropTarget ? Theme.accentSoft : Color.white.opacity(0.02)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isInboxDropTarget ? Theme.accent.opacity(0.6) : Theme.border))
            .onDrop(of: DropImporter.acceptedTypes, isTargeted: $isInboxDropTarget) { providers in
                DropImporter.handle(providers, model: model)
            }
        }
    }
}

/// Knöpfe neben „Heute“: Eintragen (Pause, Zeit, Abwesenheit), Tag planen, Tag abschließen.
/// `compact` zeigt nur Symbole, wenn die Spalte schmal ist.
struct DayActions: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                if model.runningBreak != nil {
                    Button("Pause beenden") { model.endBreak(resume: true) }
                } else {
                    Button("Pause machen") { model.startBreak() }
                }
                Button("Pause nachtragen …") { model.beginBreakEntry() }
                Button("Zeit nachtragen …") { model.beginTimeEntry() }
                Divider()
                Section("Abwesend") {
                    Button("Heute krank") { model.markAbsent(.sick, from: model.today, through: model.today) }
                    Button("Heute halber Tag krank") { model.markAbsent(.sick, from: model.today, through: model.today, halfDay: true) }
                    Button("Krank für mehrere Tage …") { model.beginAbsence(.sick) }
                    Button("Urlaub eintragen …") { model.beginAbsence(.vacation) }
                }
            } label: {
                label("Eintragen", systemImage: "square.and.pencil")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(GhostButtonStyle())
            .fixedSize()
            .help("Pause, vergessene Zeit oder Krank- und Urlaubstage eintragen")
            Button {
                model.selection = .planning
            } label: {
                label("Tag planen", systemImage: "sunrise")
            }
            .buttonStyle(GhostButtonStyle())
            .help("Geführte Tagesplanung (⌘0)")
            Button {
                model.selection = .close
            } label: {
                label("Tag abschließen", systemImage: "moon")
            }
            .buttonStyle(GhostButtonStyle())
            .help("Zeiten prüfen und buchen (⌘9)")
        }
        .fixedSize()
    }

    @ViewBuilder
    private func label(_ title: String, systemImage: String) -> some View {
        if compact {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

/// Erledigt heute: Done-Liste mit erfasster Zeit.
struct DoneRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleDone(task.id)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.done)
            }
            .buttonStyle(.plain)
            .help("Wieder öffnen")
            Text(task.title)
                .foregroundStyle(Theme.secondary)
                .strikethrough(color: Theme.tertiary)
                .lineLimit(1)
            if let customer = model.customer(task.customerID) {
                CustomerDot(colorIndex: customer.colorIndex, size: 6)
            }
            Spacer()
            Text(TimeMath.format(model.tracked(taskID: task.id, now: Date())))
                .monospacedDigit()
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contextMenu { TaskContextMenu(task: task) }
    }
}

/// Aufgabe im Eingang: mit einem Klick auf heute, sonst in der Woche einplanen.
struct InboxRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: task.source.systemImage)
                .foregroundStyle(Theme.tertiary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    CardMeta(task: task, compact: true)
                    SubtaskToggle(task: task)
                }
                if hovering || task.pspElement != nil || task.ticketNumber != nil {
                    BookingSummary(task: task)
                }
                if model.expandedTaskIDs.contains(task.id) {
                    SubtaskList(parent: task)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            if hovering {
                OpenDetailButton(task: task)
                AddSubtaskButton(task: task)
            }
            Button {
                model.plan(task.id, for: model.today)
            } label: {
                Text("Heute")
            }
            .buttonStyle(GhostButtonStyle())
            .help("Für heute einplanen")
        }
        .padding(10)
        .onHover { hovering = $0 }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
        .contentShape(Rectangle())
        .draggable(task.id.uuidString)
        .onTapGesture(count: 2) { model.openFocus(task.id) }
        .contextMenu { TaskContextMenu(task: task) }
    }
}

/// Hinweis auf Start, wenn heute ein Krank- oder Urlaubstag eingetragen ist.
struct AbsenceBanner: View {
    @Environment(AppModel.self) private var model
    let absence: Absence

    var body: some View {
        let open = model.todayTasks.filter { !$0.isDone }
        HStack(spacing: 12) {
            Image(systemName: absence.kind.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Theme.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Heute: \(absence.label)")
                    .font(.system(size: 14, weight: .medium))
                Text(absence.note.isEmpty ? (absence.kind == .sick ? "Gute Besserung. Das Wochenziel ist angepasst." : "Schönen freien Tag. Das Wochenziel ist angepasst.") : absence.note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 12)
            if !open.isEmpty, !absence.halfDay {
                Button("\(open.count) Aufgabe\(open.count == 1 ? "" : "n") verschieben") {
                    model.moveOpenTasks(from: model.today)
                }
                .buttonStyle(GhostButtonStyle(small: true))
                .help("Auf den nächsten Arbeitstag")
            }
            Button("Austragen") { model.removeAbsence(on: model.today) }
                .buttonStyle(GhostButtonStyle(small: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .surface(radius: Theme.Radius.control, elevation: .flat, fill: Theme.surfaceRaised)
    }
}
