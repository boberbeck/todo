import AppKit
import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// Tagesplan: Aufgaben des Tages mit Ist- und Plan-Zeit, rechts der Eingang.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.showInboxKey) private var showInbox = true
    @AppStorage(Preferences.calendarWidthKey) private var calendarWidth = Preferences.defaultCalendarWidth
    @State private var showsInboxPopover = false

    private let taskColumnMinWidth: CGFloat = 320
    private let inboxWidth: CGFloat = 250

    var body: some View {
        GeometryReader { geometry in
            // Der Eingang bekommt eine eigene Spalte, wenn neben Liste und Kalender genug Platz bleibt.
            let wide = geometry.size.width >= taskColumnMinWidth + CGFloat(calendarWidth) + inboxWidth + 200
            let inboxShown = showInbox && wide
            let maxCalendar = max(Preferences.minCalendarWidth, Double(geometry.size.width - taskColumnMinWidth - 20 - (inboxShown ? inboxWidth : 0)))
            HStack(spacing: 0) {
                taskColumn
                    .frame(minWidth: taskColumnMinWidth, maxWidth: .infinity)

                ResizeHandle(
                    width: $calendarWidth,
                    range: Preferences.minCalendarWidth...max(Preferences.minCalendarWidth, min(Preferences.maxCalendarWidth, maxCalendar)),
                    defaultValue: Preferences.defaultCalendarWidth
                )

                CalendarColumn()
                    .frame(width: CGFloat(min(calendarWidth, maxCalendar)))

                if inboxShown {
                    Divider()
                    InboxPanel()
                        .frame(width: inboxWidth)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.selection = .planning
                    } label: {
                        Label("Tag planen", systemImage: "sunrise")
                    }
                    .help("Geführte Tagesplanung (⌘0)")

                    Button {
                        model.selection = .close
                    } label: {
                        Label("Tag abschließen", systemImage: "moon")
                    }
                    .help("Zeiten prüfen und buchen (⌘9)")

                    Button {
                        if wide {
                            showInbox.toggle()
                        } else {
                            showsInboxPopover.toggle()
                        }
                    } label: {
                        Label("Eingang", systemImage: showInbox && wide ? "tray.fill" : "tray")
                    }
                    .help("Eingang ein- oder ausblenden")
                    .popover(isPresented: $showsInboxPopover, arrowEdge: .bottom) {
                        InboxPanel()
                            .frame(width: 300, height: 460)
                    }
                }
            }
        }
        .navigationTitle("Heute")
    }

    private var taskColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            if model.todayTasks.isEmpty {
                ContentUnavailableView(
                    "Noch nichts geplant",
                    systemImage: "sun.max",
                    description: Text("Lege unten eine Aufgabe an oder hole eine aus dem Eingang.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.todayTasks) { task in
                        TaskRow(task: task)
                    }
                    .onMove { source, destination in
                        model.moveTodayTasks(from: source, to: destination)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            NewTaskBar(plannedDate: model.today)
        }
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap { UUID(uuidString: $0) }
            for id in ids {
                model.plan(id, for: model.today)
            }
            return !ids.isEmpty
        }
    }

    private var header: some View {
        let planned = DayPlan.plannedMinutes(model.todayTasks)
        let free = model.freeMinutesToday
        let overplanned = DayPlan.isOverplanned(plannedMinutes: planned, availableMinutes: free)
        let tracked = model.trackedToday(now: model.runningEntry == nil ? Date() : model.now)
        return VStack(alignment: .leading, spacing: 4) {
            Text(model.today.startDate().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.title2.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                if overplanned {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Mehr geplant, als Zeit da ist")
                }
                Text("\(TimeMath.format(minutes: planned)) h geplant von \(TimeMath.format(minutes: free)) h frei")
                    .foregroundStyle(overplanned ? Color.orange : Color.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(TimeMath.format(tracked)) h erfasst")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .lineLimit(1)
        }
    }
}

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        let running = model.isRunning(task.id)
        HStack(spacing: 10) {
            Button {
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Wieder öffnen" : "Erledigt")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .fontWeight(running ? .semibold : .regular)
                    .strikethrough(task.isDone, color: .secondary)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                    .lineLimit(2)
                TaskMetaLine(task: task)
            }

            Spacer(minLength: 8)

            if let start = task.scheduledStart, !task.isDone {
                Label(start.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(model.timeLabel(for: task, now: running ? model.now : Date()))
                .font(.callout.monospacedDigit())
                .foregroundStyle(running ? Color.primary : Color.secondary)

            if !task.isDone {
                Button {
                    model.toggleTimer(for: task.id)
                } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .help(running ? "Timer stoppen" : "Timer starten")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(running ? 0.12 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: running ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.openFocus(task.id)
        }
        .contextMenu {
            TaskContextMenu(task: task)
        }
    }
}

/// Noch nicht eingeplante Aufgaben. Später kommen hier Tickets und markierte Mails dazu.
struct InboxPanel: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eingang")
                        .font(.title3.weight(.semibold))
                    Text(model.inboxMessage ?? model.ticketSyncMessage ?? "Noch nicht eingeplant · Mails hierher ziehen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if model.canUseManageEngine {
                    Button {
                        Task { await model.importTickets() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isSyncingTickets)
                    .help("Tickets aus ManageEngine abrufen")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if model.inboxTasks.isEmpty {
                Text("Leer. Hier landen Kunden-Todos ohne Tag, später auch Tickets aus ManageEngine und markierte Mails.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.inboxTasks) { task in
                            InboxCard(task: task)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(isDropTarget ? 0.08 : 0.03))
        .onDrop(of: DropImporter.acceptedTypes, isTargeted: $isDropTarget) { providers in
            DropImporter.handle(providers, model: model)
        }
    }
}

struct InboxCard: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .fontWeight(.medium)
                    .lineLimit(2)
                TaskMetaLine(task: task)
            }
            Spacer(minLength: 4)
            Button {
                model.plan(task.id, for: model.today)
            } label: {
                Image(systemName: "arrow.left.circle")
            }
            .buttonStyle(.borderless)
            .help("Für heute einplanen")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1))
        )
        .draggable(task.id.uuidString)
        .contextMenu {
            TaskContextMenu(task: task)
        }
    }
}
