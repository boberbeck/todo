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
            header
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
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                    .font(.system(size: 34, weight: .medium))
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

        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    SectionLabel(text: "Heute", detail: "\(TimeMath.format(minutes: planned)) h geplant · \(TimeMath.format(minutes: free)) h frei")
                    if overplanned {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                            .help("Mehr geplant, als zwischen den Terminen Zeit ist")
                    }
                    Spacer()
                    Button {
                        model.beginTimeEntry()
                    } label: {
                        Label("Nachtragen", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .help("Zeit nachtragen, wenn du vergessen hast, den Timer zu starten")
                    Button {
                        model.selection = .planning
                    } label: {
                        Label("Tag planen", systemImage: "sunrise")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .help("Geführte Tagesplanung (⌘0)")
                    Button {
                        model.selection = .close
                    } label: {
                        Label("Tag abschließen", systemImage: "moon")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .help("Zeiten prüfen und buchen (⌘9)")
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
                                .font(.caption2.weight(.semibold))
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
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(isInboxDropTarget ? Theme.accentSoft : Color.white.opacity(0.02)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isInboxDropTarget ? Theme.accent.opacity(0.6) : Theme.border))
            .onDrop(of: DropImporter.acceptedTypes, isTargeted: $isInboxDropTarget) { providers in
                DropImporter.handle(providers, model: model)
            }
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
