import AppKit
import SwiftUI
import TagwerkCore

/// Tagesplan: Aufgaben des Tages mit Ist- und Plan-Zeit, rechts der Eingang.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.workdayMinutesKey) private var workdayMinutes = Preferences.defaultWorkdayMinutes

    var body: some View {
        HStack(spacing: 0) {
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
            .frame(maxWidth: .infinity)
            .dropDestination(for: String.self) { items, _ in
                let ids = items.compactMap { UUID(uuidString: $0) }
                for id in ids {
                    model.plan(id, for: model.today)
                }
                return !ids.isEmpty
            }

            Divider()

            InboxPanel()
                .frame(width: 280)
        }
        .navigationTitle("Heute")
    }

    private var header: some View {
        let planned = DayPlan.plannedMinutes(model.todayTasks)
        let overplanned = DayPlan.isOverplanned(plannedMinutes: planned, availableMinutes: workdayMinutes)
        let tracked = model.trackedToday(now: model.runningEntry == nil ? Date() : model.now)
        return VStack(alignment: .leading, spacing: 4) {
            Text(model.today.startDate().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.title2.weight(.semibold))
            HStack(spacing: 6) {
                if overplanned {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Mehr geplant, als Zeit da ist")
                }
                Text("\(TimeMath.format(minutes: planned)) h geplant von \(TimeMath.format(minutes: workdayMinutes)) h frei")
                    .foregroundStyle(overplanned ? Color.orange : Color.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(TimeMath.format(tracked)) h erfasst")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
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
                TaskMetaLine(task: task)
            }

            Spacer(minLength: 8)

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Eingang")
                    .font(.title3.weight(.semibold))
                Text("Noch nicht eingeplant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .background(Color.primary.opacity(0.03))
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
