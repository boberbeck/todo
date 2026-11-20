import SwiftUI
import TagwerkCore

/// Unteraufgaben einer Aufgabe: abhaken, Timer starten, Ticket zuordnen, neue anlegen.
struct SubtaskList: View {
    @Environment(AppModel.self) private var model
    let parent: TaskItem
    var showsAddField = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(model.subtasks(of: parent.id)) { subtask in
                SubtaskRow(task: subtask)
            }
            if showsAddField, !parent.isDone {
                AddSubtaskField(parentID: parent.id)
            }
        }
    }
}

/// Fortschritt der Unteraufgaben („2/5“) mit Pfeil zum Auf- und Zuklappen.
struct SubtaskToggle: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        let subtasks = model.subtasks(of: task.id)
        let expanded = model.expandedTaskIDs.contains(task.id)
        if !subtasks.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { model.toggleSubtasks(task.id) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                    Text("\(subtasks.filter(\.isDone).count)/\(subtasks.count)")
                        .monospacedDigit()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Unteraufgaben zuklappen" : "Unteraufgaben zeigen")
        }
    }
}

struct SubtaskRow: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var hovering = false
    @State private var showsTicketPicker = false

    var body: some View {
        let running = model.isRunning(task.id)
        let tracked = model.tracked(taskID: task.id, now: running ? model.now : Date())
        HStack(spacing: 8) {
            Button {
                model.toggleDone(task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(task.isDone ? Theme.done : Theme.tertiary)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Wieder öffnen" : "Erledigt")

            Text(task.title)
                .font(.callout)
                .foregroundStyle(task.isDone ? Theme.secondary : Theme.text)
                .strikethrough(task.isDone, color: Theme.tertiary)
                .lineLimit(2)

            if let number = task.ticketNumber {
                Text("#\(number)")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .help("Zeit geht auch als Worklog an Ticket #\(number)")
            }

            Spacer(minLength: 4)

            if tracked > 0 || running {
                Text(TimeMath.format(tracked))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(running ? Theme.text : Theme.tertiary)
            }
            if !task.isDone, hovering || running {
                Button {
                    showsTicketPicker = true
                } label: {
                    Image(systemName: "ticket")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(task.ticketNumber == nil ? Theme.tertiary : Theme.accent)
                .help("Ticket zuordnen")
                .popover(isPresented: $showsTicketPicker, arrowEdge: .bottom) {
                    TicketPicker(taskID: task.id) { showsTicketPicker = false }
                }

                Button {
                    model.toggleTimer(for: task.id)
                } label: {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                        .font(.system(size: 9))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(running ? Theme.accent : Color.white.opacity(0.08)))
                        .foregroundStyle(running ? Color.black.opacity(0.85) : Theme.text)
                }
                .buttonStyle(.plain)
                .help(running ? "Timer stoppen" : "Timer für diese Unteraufgabe starten")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(running ? Theme.accentSoft : (hovering ? Color.white.opacity(0.04) : .clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.openFocus(task.id) }
        .contextMenu { TaskContextMenu(task: task) }
    }
}

/// Eingabe für eine neue Unteraufgabe. Eine Zeitangabe am Ende wird zur Schätzung.
struct AddSubtaskField: View {
    @Environment(AppModel.self) private var model
    let parentID: UUID

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 13)
            TextField("Unteraufgabe hinzufügen", text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($focused)
                .onSubmit {
                    if model.addSubtask(title: text, to: parentID) != nil {
                        text = ""
                        focused = true
                    }
                }
                .onExitCommand {
                    text = ""
                    focused = false
                }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .onAppear { takeFocusIfRequested() }
        .onChange(of: model.subtaskEntryTaskID) { takeFocusIfRequested() }
    }

    private func takeFocusIfRequested() {
        guard model.subtaskEntryTaskID == parentID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focused = true
            model.subtaskEntryTaskID = nil
        }
    }
}

/// Ticket zuordnen: Knopf mit Suche. Bei Tickets selbst nicht nötig, sie sind ihr eigenes Ticket.
struct TicketMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    @State private var showsPicker = false

    var body: some View {
        if task.source != .ticket {
            Button {
                showsPicker = true
            } label: {
                Text(label)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
                TicketPicker(taskID: task.id) { showsPicker = false }
            }
            .help("Ticket in ManageEngine, an das die Zeit zusätzlich als Worklog geht (freiwillig)")
        }
    }

    private var label: String {
        if let own = task.ticketNumber { return "Ticket #\(own)" }
        if let inherited = model.ticketNumber(for: task) { return "Ticket #\(inherited) (geerbt)" }
        return "Ticket zuordnen"
    }
}

/// Suche über die Tickets in Tagwerk, nach Nummer oder Betreff. Eine unbekannte Nummer fragt ManageEngine.
struct TicketPicker: View {
    @Environment(AppModel.self) private var model
    let taskID: UUID
    let onDone: () -> Void

    @State private var query = ""
    @State private var message: String?
    @State private var isLooking = false
    @FocusState private var focused: Bool

    var body: some View {
        let found = results
        let typedNumber = cleanedNumber
        let current = model.task(taskID)
        VStack(alignment: .leading, spacing: 8) {
            Text(current.map { "Ticket für „\($0.title)“" } ?? "Ticket zuordnen")
                .font(.headline)
                .lineLimit(1)
            TextField("Ticketnummer oder Betreff", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    if let first = found.first {
                        choose(first)
                    } else if let typedNumber {
                        lookUp(typedNumber)
                    }
                }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(found) { ticket in
                        Button {
                            choose(ticket)
                        } label: {
                            HStack(spacing: 8) {
                                Text("#\(ticket.linkedTicketNumber ?? "?")")
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ticket.title)
                                        .lineLimit(1)
                                    if let customer = model.customer(ticket.customerID) {
                                        Text(customer.name + (ticket.isDone ? " · erledigt" : ""))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if current?.ticketNumber == ticket.linkedTicketNumber {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if let typedNumber, !found.contains(where: { $0.linkedTicketNumber == typedNumber }) {
                        Button {
                            lookUp(typedNumber)
                        } label: {
                            Label(isLooking ? "Sucht in ManageEngine …" : "Ticket #\(typedNumber) zuordnen", systemImage: "magnifyingglass")
                        }
                        .disabled(isLooking)
                        .padding(8)
                    }
                    if found.isEmpty, typedNumber == nil {
                        Text(model.ticketTasks.isEmpty
                             ? "Noch keine Tickets in Tagwerk. Tippe die Ticketnummer ein."
                             : "Nichts gefunden. Tippe die Ticketnummer ein, dann fragt Tagwerk ManageEngine.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
            }
            .frame(height: 240)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Text("Die Zeit geht dann auch als Worklog an das Ticket. SAP bleibt Pflicht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if current?.ticketNumber != nil || current?.ticketKey != nil {
                    Button("Kein Ticket") {
                        model.unlinkTicket(from: taskID)
                        onDone()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .frame(width: 440)
        .onAppear { focused = true }
    }

    private var cleanedNumber: String? {
        let value = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return !value.isEmpty && value.allSatisfy(\.isNumber) ? value : nil
    }

    private var results: [TaskItem] {
        let words = query.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "#", with: "")
            .split(separator: " ")
            .map(String.init)
        return model.ticketTasks
            .filter { $0.id != taskID }
            .filter { ticket in
                guard !words.isEmpty else { return !ticket.isDone }
                let haystack = ["\(ticket.linkedTicketNumber ?? "")", ticket.title, model.customer(ticket.customerID)?.name ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                    .folding(options: .diacriticInsensitive, locale: nil)
                return words.allSatisfy { haystack.contains($0) }
            }
            .prefix(50)
            .map { $0 }
    }

    private func choose(_ ticket: TaskItem) {
        model.linkTicket(ticket, to: taskID)
        onDone()
    }

    private func lookUp(_ number: String) {
        isLooking = true
        message = nil
        Task {
            let result = await model.linkTicket(number: number, to: taskID)
            isLooking = false
            if let result {
                message = result
            } else {
                onDone()
            }
        }
    }
}

/// „Vergessen zu starten?“: Timer rückwirkend starten oder Zeit nachtragen.
struct BackdatedStartMenu: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem
    /// Als eigener Menü-Knopf (Fokus) statt als Untermenü im Rechtsklick.
    var asButton = false

    var body: some View {
        if asButton {
            Menu {
                items
            } label: {
                Label(model.isRunning(task.id) ? "Früher angefangen?" : "Vergessen zu starten?", systemImage: "clock.arrow.circlepath")
                    .font(.callout)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(Theme.tertiary)
            .help("Timer rückwirkend starten oder Zeit nachtragen")
        } else {
            Menu(model.isRunning(task.id) ? "Läuft eigentlich schon seit" : "Timer starten, läuft schon seit") {
                items
            }
        }
    }

    @ViewBuilder
    private var items: some View {
        if let last = model.lastEntryEndToday, Date().timeIntervalSince(last) >= 60, Date().timeIntervalSince(last) <= 10 * 3600 {
            Button("dem letzten Eintrag (\(last.formatted(date: .omitted, time: .shortened)))") {
                model.startTimer(task.id, since: last)
            }
        }
        ForEach([5, 10, 15, 30, 45, 60, 90], id: \.self) { minutes in
            Button(minutes < 60 ? "\(minutes) Minuten" : "\(TimeMath.format(minutes: minutes)) Stunden") {
                model.startTimer(task.id, since: Date().addingTimeInterval(TimeInterval(-minutes * 60)))
            }
        }
        if asButton {
            Divider()
            Button("Zeit nachtragen …") { model.beginTimeEntry(for: task.id) }
        }
    }
}

/// Unteraufgaben unter einer Zeile, wenn sie aufgeklappt sind (Eingang, Kunden).
struct ExpandedSubtasks: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        if model.expandedTaskIDs.contains(task.id) {
            SubtaskList(parent: task)
                .padding(.leading, 26)
                .padding(.top, 2)
        }
    }
}

/// Kleiner Knopf „Unteraufgabe“ zum Aufklappen und Anlegen, erscheint beim Darüberfahren.
struct AddSubtaskButton: View {
    @Environment(AppModel.self) private var model
    let task: TaskItem

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { model.beginSubtaskEntry(for: task.id) }
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 11))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .help("Unteraufgabe hinzufügen")
    }
}
